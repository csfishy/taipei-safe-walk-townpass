import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';

enum SupabaseConnectionFailure {
  closed,
  timeout,
  network,
  httpStatus,
  responseTooLarge,
  invalidResponse,
}

/// Contains no response body, endpoint, or API key.
final class SupabaseConnectionException implements Exception {
  const SupabaseConnectionException(this.failure, {this.statusCode});

  final SupabaseConnectionFailure failure;
  final int? statusCode;

  @override
  String toString() =>
      'Supabase connection failed: ${failure.name}'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

/// These confirm API access, not table permissions or nearby-alert setup.
enum SupabaseConnectionStatus { apiReachable, postgrestReachable }

/// Native, explicit connection probe. Construction never opens a connection.
/// Checks API metadata, with a zero-row reserved-resource probe if public keys
/// cannot read OpenAPI. It never reads existing records or invokes an RPC.
final class SupabaseConnection {
  SupabaseConnection({
    required this.config,
    this.timeout = const Duration(seconds: 10),
    this.maxResponseBytes = 1024 * 1024,
  }) {
    if (timeout <= Duration.zero || maxResponseBytes < 1) {
      throw ArgumentError('A positive timeout and response limit are required');
    }
  }

  final SafeWalkSupabaseConfig config;
  final Duration timeout;
  final int maxResponseBytes;
  final Set<HttpClient> _activeClients = {};
  bool _closed = false;
  static const _probeTable = '__safe_walk_connection_probe__';

  Future<SupabaseConnectionStatus> checkConnection() async {
    if (_closed) {
      throw const SupabaseConnectionException(SupabaseConnectionFailure.closed);
    }
    final client = HttpClient()..connectionTimeout = timeout;
    _activeClients.add(client);
    try {
      final status = await _readOpenApi(client).timeout(timeout);
      if (_closed) {
        throw const SupabaseConnectionException(
          SupabaseConnectionFailure.closed,
        );
      }
      return status;
    } on SupabaseConnectionException {
      rethrow;
    } on TimeoutException {
      throw SupabaseConnectionException(
        _closed
            ? SupabaseConnectionFailure.closed
            : SupabaseConnectionFailure.timeout,
      );
    } catch (_) {
      throw SupabaseConnectionException(
        _closed
            ? SupabaseConnectionFailure.closed
            : SupabaseConnectionFailure.network,
      );
    } finally {
      _activeClients.remove(client);
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri url,
    String accept,
  ) async {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, accept);
    config.requestHeaders.forEach(request.headers.set);
    return request.close();
  }

  Future<SupabaseConnectionStatus> _readOpenApi(HttpClient client) async {
    final response = await _get(
      client,
      config.url.resolve('/rest/v1/'),
      'application/openapi+json',
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      // Some projects require a secret for OpenAPI metadata. A public client
      // must keep using its public key and prove PostgREST access separately.
      await _readBytes(response);
      return _readPostgrestProbe(client);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw SupabaseConnectionException(
        SupabaseConnectionFailure.httpStatus,
        statusCode: response.statusCode,
      );
    }
    final document = await _readJson(response);
    if (document is! Map || !_isOpenApi(document)) {
      throw const SupabaseConnectionException(
        SupabaseConnectionFailure.invalidResponse,
      );
    }
    return SupabaseConnectionStatus.apiReachable;
  }

  Future<SupabaseConnectionStatus> _readPostgrestProbe(
    HttpClient client,
  ) async {
    final response = await _get(
      client,
      config.url
          .resolve('/rest/v1/$_probeTable')
          .replace(queryParameters: {'select': '*', 'limit': '0'}),
      'application/json',
    );
    if (response.statusCode != HttpStatus.notFound) {
      throw SupabaseConnectionException(
        SupabaseConnectionFailure.httpStatus,
        statusCode: response.statusCode,
      );
    }
    final document = await _readJson(response);
    if (document is! Map ||
        document['code'] != 'PGRST205' ||
        document['message'] is! String ||
        !(document['message'] as String).contains(_probeTable)) {
      throw const SupabaseConnectionException(
        SupabaseConnectionFailure.invalidResponse,
      );
    }
    return SupabaseConnectionStatus.postgrestReachable;
  }

  Future<Uint8List> _readBytes(HttpClientResponse response) async {
    if (response.contentLength > maxResponseBytes) {
      throw const SupabaseConnectionException(
        SupabaseConnectionFailure.responseTooLarge,
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > maxResponseBytes) {
        throw const SupabaseConnectionException(
          SupabaseConnectionFailure.responseTooLarge,
        );
      }
    }
    return bytes.takeBytes();
  }

  Future<Object?> _readJson(HttpClientResponse response) async {
    final bytes = await _readBytes(response);
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const SupabaseConnectionException(
        SupabaseConnectionFailure.invalidResponse,
      );
    }
  }

  bool _isOpenApi(Map<dynamic, dynamic> document) {
    final version = document['openapi'];
    final hasVersion =
        document['swagger'] == '2.0' ||
        (version is String &&
            RegExp(r'^3\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$').hasMatch(version));
    final info = document['info'];
    return hasVersion &&
        info is Map &&
        info['title'] is String &&
        info['version'] is String &&
        document['paths'] is Map;
  }

  /// Also aborts active checks. This is safe to call more than once.
  void close() {
    _closed = true;
    for (final client in _activeClients) {
      client.close(force: true);
    }
  }
}
