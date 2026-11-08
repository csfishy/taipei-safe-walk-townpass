// GoTrue client for the nearby identity: request shapes and how each answer is
// classified. Synthetic HTTP only; no real project, key or token.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_auth_client.dart';

import 'fake_http_backend.dart';

final _config = SafeWalkSupabaseConfig(
  url: Uri.parse('https://artificial.example'),
  apiKey: 'sb_publishable_artificial-local-test-key',
);
final _now = DateTime.utc(2026, 11, 8, 12);

SupabaseAuthClient _client(
  FakeHttpBackend backend, {
  Duration timeout = const Duration(seconds: 5),
  int maxResponseBytes = 64 * 1024,
}) => SupabaseAuthClient(
  config: _config,
  createHttpClient: backend.client,
  clock: () => _now,
  timeout: timeout,
  maxResponseBytes: maxResponseBytes,
);

FakeHttpBackend _answering(int status, String body) =>
    FakeHttpBackend((_) => (status: status, body: body));

void main() {
  test(
    'anonymous sign-up posts an empty body with only the public key',
    () async {
      final backend = _answering(
        200,
        authSessionJson(expiresAt: _now.millisecondsSinceEpoch ~/ 1000 + 3600),
      );
      final session = await _client(backend).signUpAnonymously();
      final call = backend.calls.single;
      expect(call.url.path, '/auth/v1/signup');
      expect(call.url.hasQuery, isFalse);
      expect(jsonDecode(call.body), isEmpty);
      expect(call.headers['apikey'], _config.apiKey);
      expect(call.headers.containsKey('authorization'), isFalse);
      expect(call.headers['content-type'], contains('application/json'));
      expect(session.accessToken, 'aaaa.bbbb.cccc');
      expect(session.refreshToken, 'refresh-1');
      expect(session.expiresAt, _now.add(const Duration(hours: 1)));
    },
  );

  test('refresh sends only the refresh token, as a grant', () async {
    final backend = _answering(
      200,
      authSessionJson(refresh: 'refresh-2', expiresIn: 1800),
    );
    final session = await _client(backend).refresh('refresh-1');
    final call = backend.calls.single;
    expect(call.url.path, '/auth/v1/token');
    expect(call.url.queryParameters, {'grant_type': 'refresh_token'});
    expect(jsonDecode(call.body), {'refresh_token': 'refresh-1'});
    expect(session.refreshToken, 'refresh-2');
    // No expires_at: the lifetime counts from the client's clock.
    expect(session.expiresAt, _now.add(const Duration(minutes: 30)));
  });

  test('answers that say no are rejected, not treated as outages', () async {
    for (final status in [400, 401, 403, 404, 422, 429]) {
      await expectLater(
        _client(_answering(status, '{"error_code":"x"}')).signUpAnonymously(),
        throwsA(
          isA<SupabaseAuthRejected>().having(
            (e) => e.statusCode,
            'statusCode',
            status,
          ),
        ),
        reason: 'HTTP $status',
      );
    }
  });

  test('server errors and timeouts are outages', () async {
    for (final status in [408, 500, 502, 503]) {
      await expectLater(
        _client(_answering(status, '')).signUpAnonymously(),
        throwsA(isA<SupabaseAuthUnavailable>()),
        reason: 'HTTP $status',
      );
    }
  });

  test('a network failure is an outage', () async {
    final backend = FakeHttpBackend((_) => throw const FormatException('boom'));
    await expectLater(
      _client(backend).signUpAnonymously(),
      throwsA(isA<SupabaseAuthUnavailable>()),
    );
  });

  test('a stalled connection times out as an outage', () async {
    final backend = FakeHttpBackend((_) => Completer<FakeAnswer>().future);
    await expectLater(
      _client(
        backend,
        timeout: const Duration(milliseconds: 30),
      ).signUpAnonymously(),
      throwsA(isA<SupabaseAuthUnavailable>()),
    );
  });

  test(
    'malformed or incomplete success bodies are outages, not guesses',
    () async {
      for (final body in [
        'not json',
        '[]',
        '{}',
        '{"access_token":"a","refresh_token":"b"}',
        '{"access_token":"","refresh_token":"b","expires_in":10}',
        '{"access_token":"a","refresh_token":"","expires_in":10}',
        '{"access_token":1,"refresh_token":"b","expires_in":10}',
      ]) {
        await expectLater(
          _client(_answering(200, body)).signUpAnonymously(),
          throwsA(isA<SupabaseAuthUnavailable>()),
          reason: body,
        );
      }
    },
  );

  test('an oversized answer is refused', () async {
    await expectLater(
      _client(
        _answering(200, authSessionJson(expiresIn: 60)),
        maxResponseBytes: 20,
      ).signUpAnonymously(),
      throwsA(isA<SupabaseAuthUnavailable>()),
    );
  });

  test('nothing printable contains a token', () async {
    final session = await _client(
      _answering(
        200,
        authSessionJson(
          access: 'SECRET.ACCESS.TOKEN',
          refresh: 'SECRET-REFRESH',
          expiresIn: 60,
        ),
      ),
    ).signUpAnonymously();
    expect('$session', isNot(contains('SECRET')));
    expect(
      const SupabaseAuthRejected(422).toString(),
      isNot(contains('SECRET')),
    );
    expect(
      const SupabaseAuthUnavailable().toString(),
      isNot(contains('SECRET')),
    );
  });
}
