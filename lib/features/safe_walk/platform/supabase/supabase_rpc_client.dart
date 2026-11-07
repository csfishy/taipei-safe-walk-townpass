import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';

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
  }) {
    if (timeout <= Duration.zero || maxResponseBytes < 1) {
      throw ArgumentError('A positive timeout and response limit are required');
    }
  }

  final SafeWalkSupabaseConfig config;
  final Duration timeout;
  final int maxResponseBytes;

  static final _functionName = RegExp(r'^[a-z_][a-z0-9_]{0,62}$');

  /// `POST /rest/v1/rpc/<function>`. Throws [TimeoutException] on timeout;
  /// any other exception is a network failure. HTTP errors are returned.
  Future<SupabaseRpcResponse> call(
    String function,
    Map<String, Object?> arguments,
  ) async {
    if (!_functionName.hasMatch(function)) {
      throw ArgumentError('Invalid RPC function name');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await _post(client, function, arguments).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<SupabaseRpcResponse> _post(
    HttpClient client,
    String function,
    Map<String, Object?> arguments,
  ) async {
    final request = await client.postUrl(
      config.url.resolve('/rest/v1/rpc/$function'),
    );
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentType = ContentType.json;
    config.requestHeaders.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(arguments)));
    final response = await request.close();
    if (response.contentLength > maxResponseBytes) {
      throw const SupabaseRpcResponseTooLarge();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > maxResponseBytes) {
        throw const SupabaseRpcResponseTooLarge();
      }
    }
    return SupabaseRpcResponse(
      response.statusCode,
      utf8.decode(bytes.takeBytes(), allowMalformed: false),
    );
  }
}
