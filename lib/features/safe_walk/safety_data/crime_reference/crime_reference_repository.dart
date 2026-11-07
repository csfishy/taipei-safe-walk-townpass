import 'dart:async';
import 'dart:convert';

import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_parser.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Reviewed PostgREST function name (`04_app_read_api.sql`).
const crimeReferenceRpcFunction = 'safe_walk_crime_reference_query';

/// Raw HTTP answer from the RPC call. Transport implementations must not
/// follow redirects and must send only the public client key.
final class CrimeReferenceHttpResponse {
  const CrimeReferenceHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// Calls `POST /rest/v1/rpc/<crimeReferenceRpcFunction>` with the JSON
/// [arguments]. [TimeoutException] means timeout; [SafeWalkCancelledException]
/// preserves cancellation. Other throws mean network failure. Injected by M1.
/// Transports must check cancellation after connecting, before writing the
/// potentially location-bearing body, and abort their request when cancelled.
typedef CrimeReferenceRpcTransport =
    Future<CrimeReferenceHttpResponse> Function(
      Map<String, Object?> arguments, {
      SafeWalkCancellation? cancellation,
    });

enum CrimeReferenceFailure {
  /// Network error before an HTTP answer.
  network,
  timeout,

  /// 401/403: the public key was rejected or EXECUTE is not granted.
  unauthorized,

  /// The reviewed SQL has not been applied (PostgREST PGRST202 / 404).
  interfaceMissing,

  /// The server rejected the arguments (SQLSTATE 22023).
  invalidArgument,

  /// The pinned snapshot is missing or incomplete on the server.
  snapshotUnavailable,

  /// 429 or 5xx.
  serverUnavailable,

  /// The answer did not match interface version 1.
  invalidResponse,
}

/// A configured live query failed. Distinct from [SafeWalkDataUnavailable]
/// (not configured / not live) and from an empty result. Never carries the
/// response body, endpoint or key.
final class CrimeReferenceQueryException implements Exception {
  const CrimeReferenceQueryException(this.failure, {this.statusCode});

  final CrimeReferenceFailure failure;
  final int? statusCode;

  @override
  String toString() =>
      'Crime reference query failed: ${failure.name}'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

/// Live-only, read-only access to the reviewed crime reference snapshot.
///
/// There is no mock dataset and no fallback: a mock mode or a missing
/// transport throws [SafeWalkDataUnavailable]; a failing live call throws
/// [CrimeReferenceQueryException]; cancellation throws
/// [SafeWalkCancelledException]. An empty `records` list is a real answer.
final class CrimeReferenceRepository {
  CrimeReferenceRepository({required this.transport, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Null when live access is not configured.
  final CrimeReferenceRpcTransport? transport;
  final DateTime Function() _now;

  bool get isConfigured => transport != null;

  Future<CrimeReferenceResult> query({
    required sw.DataMode mode,
    CrimeReferenceQuery query = const CrimeReferenceQuery(),
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    query.validate();
    final transport = this.transport;
    if (mode != sw.DataMode.live || transport == null) {
      throw const SafeWalkDataUnavailable();
    }
    final CrimeReferenceHttpResponse response;
    try {
      final pending = transport(
        query.toRpcArguments(),
        cancellation: cancellation,
      );
      response = await (cancellation == null
          ? pending
          : Future.any<CrimeReferenceHttpResponse>([
              pending,
              cancellation.whenCancelled.then<CrimeReferenceHttpResponse>(
                (_) => throw const SafeWalkCancelledException(),
              ),
            ]));
    } on SafeWalkCancelledException {
      rethrow;
    } on TimeoutException {
      cancellation?.throwIfCancelled();
      throw const CrimeReferenceQueryException(CrimeReferenceFailure.timeout);
    } on Object {
      cancellation?.throwIfCancelled();
      throw const CrimeReferenceQueryException(CrimeReferenceFailure.network);
    }
    cancellation?.throwIfCancelled();
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw CrimeReferenceQueryException(
        _failureFor(status, response.body),
        statusCode: status,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const CrimeReferenceQueryException(
        CrimeReferenceFailure.invalidResponse,
      );
    }
    try {
      return parseCrimeReferenceResponse(
        decoded,
        query: query,
        retrievedAt: _now().toUtc().toIso8601String(),
      );
    } on CrimeReferenceFormatException {
      throw const CrimeReferenceQueryException(
        CrimeReferenceFailure.invalidResponse,
      );
    }
  }

  /// Maps PostgREST errors (`{code, message, details, hint}`) by code only.
  static CrimeReferenceFailure _failureFor(int status, String body) {
    String? code;
    String? message;
    try {
      final error = jsonDecode(body);
      if (error is Map) {
        if (error['code'] is String) code = error['code'] as String;
        if (error['message'] is String) message = error['message'] as String;
      }
    } on FormatException {
      // Fall back to the status code; the body is never surfaced.
    }
    if (code == 'PGRST202' || status == 404) {
      return CrimeReferenceFailure.interfaceMissing;
    }
    if (code == '22023') return CrimeReferenceFailure.invalidArgument;
    if (code == 'P0001' && message == 'crime_reference_snapshot_unavailable') {
      return CrimeReferenceFailure.snapshotUnavailable;
    }
    // 42501 insufficient_privilege: EXECUTE not granted to the key's role.
    if (status == 401 || status == 403 || code == '42501') {
      return CrimeReferenceFailure.unauthorized;
    }
    if (status == 429 || status >= 500) {
      return CrimeReferenceFailure.serverUnavailable;
    }
    return CrimeReferenceFailure.invalidResponse;
  }
}
