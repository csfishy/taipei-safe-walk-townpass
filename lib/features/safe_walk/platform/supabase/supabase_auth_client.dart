import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';

/// A server-issued session. Tokens are credentials: never log or display them.
final class SupabaseAuthSession {
  const SupabaseAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  @override
  String toString() => 'SupabaseAuthSession(redacted)';
}

/// The server answered and said no (anonymous sign-ins disabled, rate limited,
/// refresh token no longer valid). Retrying the same request will not help soon.
final class SupabaseAuthRejected implements Exception {
  const SupabaseAuthRejected(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Supabase auth rejected ($statusCode)';
}

/// No usable answer: network error, timeout, 5xx, malformed body. Nothing is
/// known about the account, so callers must not assume it was or was not made.
final class SupabaseAuthUnavailable implements Exception {
  const SupabaseAuthUnavailable();
  @override
  String toString() => 'Supabase auth unavailable';
}

/// Native client for the two GoTrue calls the nearby feature needs: creating an
/// anonymous user and refreshing its session. Uses only the public client key,
/// never service_role. Construction opens nothing; not supported on Flutter web.
final class SupabaseAuthClient {
  SupabaseAuthClient({
    required this.config,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 64 * 1024,
    HttpClient Function()? createHttpClient,
    DateTime Function()? clock,
  }) : _createHttpClient = createHttpClient ?? (() => HttpClient()),
       _clock = clock ?? DateTime.now;

  final SafeWalkSupabaseConfig config;
  final Duration timeout;
  final int maxResponseBytes;
  final HttpClient Function() _createHttpClient;
  final DateTime Function() _clock;

  /// Creates an anonymous user (no name, phone or email) and returns its first
  /// session. Fails with [SupabaseAuthRejected] when the project has anonymous
  /// sign-ins turned off.
  Future<SupabaseAuthSession> signUpAnonymously() =>
      _session('/auth/v1/signup', const <String, Object?>{});

  /// Exchanges a refresh token for a new session (the refresh token rotates).
  Future<SupabaseAuthSession> refresh(String refreshToken) => _session(
    '/auth/v1/token?grant_type=refresh_token',
    {'refresh_token': refreshToken},
  );

  Future<SupabaseAuthSession> _session(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _post(path, body);
    if (response.statusCode >= 500 || response.statusCode == 408) {
      throw const SupabaseAuthUnavailable();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseAuthRejected(response.statusCode);
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final access = json['access_token'] as String;
      final refresh = json['refresh_token'] as String;
      final expiresAt = json['expires_at'];
      final expiresIn = json['expires_in'];
      final DateTime expires;
      if (expiresAt is int) {
        expires = DateTime.fromMillisecondsSinceEpoch(
          expiresAt * 1000,
          isUtc: true,
        );
      } else if (expiresIn is int) {
        expires = _clock().toUtc().add(Duration(seconds: expiresIn));
      } else {
        throw const FormatException();
      }
      if (access.isEmpty || refresh.isEmpty) throw const FormatException();
      return SupabaseAuthSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expires,
      );
    } on Object {
      throw const SupabaseAuthUnavailable();
    }
  }

  Future<({int statusCode, String body})> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final client = _createHttpClient()..connectionTimeout = timeout;
    try {
      return await Future(() async {
        final request = await client.postUrl(config.url.resolve(path));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.contentType = ContentType.json;
        config.requestHeaders.forEach(request.headers.set);
        request.add(utf8.encode(jsonEncode(body)));
        final response = await request.close();
        if (response.contentLength > maxResponseBytes) {
          throw const SupabaseAuthUnavailable();
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const SupabaseAuthUnavailable();
          }
          bytes.add(chunk);
        }
        return (
          statusCode: response.statusCode,
          body: utf8.decode(bytes.takeBytes(), allowMalformed: true),
        );
      }).timeout(timeout);
    } on SupabaseAuthUnavailable {
      rethrow;
    } on Object {
      throw const SupabaseAuthUnavailable();
    } finally {
      client.close(force: true);
    }
  }
}
