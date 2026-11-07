import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// Raw PostgREST answer. The body is returned as text for the caller to parse;
/// this client never logs it.
final class SupabaseRpcResponse {
  const SupabaseRpcResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// Response exceeded [SupabaseRpcClient.maxResponseBytes].
final class SupabaseRpcResponseTooLarge implements Exception {
  const SupabaseRpcResponseTooLarge();

  @override
  String toString() => 'Supabase RPC response too large';
}

/// Native read-only RPC caller using only the public client key from
/// [SafeWalkSupabaseConfig] (publishable or legacy anon; never service_role).
/// Construction opens nothing. Not supported on Flutter web (dart:io).
final class SupabaseRpcClient {
  SupabaseRpcClient({
    required this.config,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 2 * 1024 * 1024,
    HttpClient Function()? createHttpClient,
  }) : _createHttpClient = createHttpClient ?? (() => HttpClient()) {
    if (timeout <= Duration.zero || maxResponseBytes < 1) {
      throw ArgumentError('A positive timeout and response limit are required');
    }
  }

  final SafeWalkSupabaseConfig config;
  final Duration timeout;
  final int maxResponseBytes;

  /// A separate owned client per call: cancelling a request cannot close the
  /// transport used by another call or a later retry.
  final HttpClient Function() _createHttpClient;

  static final _functionName = RegExp(r'^[a-z_][a-z0-9_]{0,62}$');

  /// `POST /rest/v1/rpc/<function>`. Throws [TimeoutException] on timeout and
  /// [SafeWalkCancelledException] on cancellation. HTTP errors are returned.
  Future<SupabaseRpcResponse> call(
    String function,
    Map<String, Object?> arguments, {
    SafeWalkCancellation? cancellation,
  }) async {
    if (!_functionName.hasMatch(function)) {
      throw ArgumentError('Invalid RPC function name');
    }
    cancellation?.throwIfCancelled();
    final client = _createHttpClient()..connectionTimeout = timeout;
    var finished = false;
    void requireActive() {
      cancellation?.throwIfCancelled();
      if (finished) throw TimeoutException('Supabase RPC deadline elapsed');
    }

    final cancelled = Completer<SupabaseRpcResponse>();
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) {
          if (finished) return;
          client.close(force: true);
          cancelled.completeError(const SafeWalkCancelledException());
        }),
      );
    }
    try {
      return await Future.any<SupabaseRpcResponse>([
        _post(client, function, arguments, requireActive),
        if (cancellation != null) cancelled.future,
      ]).timeout(timeout);
    } catch (_) {
      cancellation?.throwIfCancelled();
      rethrow;
    } finally {
      finished = true;
      client.close(force: true);
    }
  }

  Future<SupabaseRpcResponse> _post(
    HttpClient client,
    String function,
    Map<String, Object?> arguments,
    void Function() requireActive,
  ) async {
    requireActive();
    final request = await client.postUrl(
      config.url.resolve('/rest/v1/rpc/$function'),
    );
    // The query may contain a trip bounding box. A connection completing after
    // consent revocation, navigation exit or timeout must never write it.
    requireActive();
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentType = ContentType.json;
    config.requestHeaders.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(arguments)));
    final response = await request.close();
    requireActive();
    if (response.contentLength > maxResponseBytes) {
      throw const SupabaseRpcResponseTooLarge();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      requireActive();
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const SupabaseRpcResponseTooLarge();
      }
      bytes.add(chunk);
    }
    requireActive();
    return SupabaseRpcResponse(
      response.statusCode,
      utf8.decode(bytes.takeBytes(), allowMalformed: false),
    );
  }
}
