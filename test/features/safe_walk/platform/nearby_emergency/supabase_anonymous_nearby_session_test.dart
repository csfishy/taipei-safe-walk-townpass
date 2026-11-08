// Anonymous per-phone identity for the nearby feature: it is created only on
// first use, survives restarts, is never thrown away because of a flaky network,
// and stops retrying for a while after the server refuses. Fake HTTP, fake store,
// fake clock; no real project or token.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/supabase_anonymous_nearby_session.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_auth_client.dart';

import '../supabase/fake_http_backend.dart';

final _config = SafeWalkSupabaseConfig(
  url: Uri.parse('https://artificial.example'),
  apiKey: 'sb_publishable_artificial-local-test-key',
);

class _Store implements NearbySessionStore {
  String? value;
  int writes = 0;
  int clears = 0;
  bool failWrites = false;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String refreshToken) async {
    if (failWrites) throw StateError('disk full');
    writes++;
    value = refreshToken;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

void main() {
  late DateTime now;
  late _Store store;
  late int refreshCounter;
  late FakeHttpBackend backend;
  // Per-endpoint behaviour the tests can change.
  late FakeAnswer Function(FakeCall) signUp;
  late FakeAnswer Function(FakeCall) refresh;

  int epoch(Duration fromNow) =>
      now.add(fromNow).millisecondsSinceEpoch ~/ 1000;

  FakeAnswer ok(String access, String refreshToken, Duration lifetime) => (
    status: 200,
    body: authSessionJson(
      access: access,
      refresh: refreshToken,
      expiresAt: epoch(lifetime),
    ),
  );

  setUp(() {
    now = DateTime.utc(2026, 11, 8, 12);
    store = _Store();
    refreshCounter = 0;
    signUp = (_) => ok('sign.up.token', 'refresh-0', const Duration(hours: 1));
    refresh = (_) {
      refreshCounter++;
      return ok(
        'refreshed.$refreshCounter.token',
        'refresh-$refreshCounter',
        const Duration(hours: 1),
      );
    };
    backend = FakeHttpBackend(
      (call) =>
          call.url.path == '/auth/v1/signup' ? signUp(call) : refresh(call),
    );
  });

  SupabaseAnonymousNearbySession session({
    Duration blockFor = const Duration(minutes: 5),
    Duration retryAfterFailure = const Duration(seconds: 30),
  }) => SupabaseAnonymousNearbySession(
    auth: SupabaseAuthClient(
      config: _config,
      createHttpClient: backend.client,
      clock: () => now,
      timeout: const Duration(seconds: 2),
    ),
    store: store,
    clock: () => now,
    blockFor: blockFor,
    retryAfterFailure: retryAfterFailure,
  );

  test('nothing is created or requested until a token is asked for', () async {
    final s = session();
    expect(s.isSignedIn, isTrue, reason: 'it can supply a token on demand');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls, isEmpty);
    expect(store.value, isNull);
  });

  test(
    'the first request creates one identity and keeps its refresh token',
    () async {
      final s = session();
      expect(await s.accessToken(), 'sign.up.token');
      expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
      expect(store.value, 'refresh-0');
      // A valid token is reused without any further request.
      expect(await s.accessToken(), 'sign.up.token');
      expect(backend.calls, hasLength(1));
    },
  );

  test('simultaneous callers share a single request', () async {
    final gate = Completer<void>();
    backend = FakeHttpBackend((call) async {
      await gate.future;
      return signUp(call);
    });
    final s = session();
    final results = [s.accessToken(), s.accessToken(), s.accessToken()];
    gate.complete();
    expect(await Future.wait(results), everyElement('sign.up.token'));
    expect(backend.calls, hasLength(1));
  });

  test('an expiring token is refreshed with the same identity', () async {
    final s = session();
    await s.accessToken();
    now = now.add(
      const Duration(minutes: 59, seconds: 30),
    ); // inside the margin
    expect(await s.accessToken(), 'refreshed.1.token');
    expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
    final call = backend.callsTo('/auth/v1/token').single;
    expect(jsonDecode(call.body), {'refresh_token': 'refresh-0'});
    expect(store.value, 'refresh-1', reason: 'the rotated token is kept');
  });

  test(
    'after a restart the stored identity is refreshed, not recreated',
    () async {
      store.value = 'refresh-from-last-run';
      final s = session();
      expect(await s.accessToken(), 'refreshed.1.token');
      expect(backend.callsTo('/auth/v1/signup'), isEmpty);
      expect(jsonDecode(backend.callsTo('/auth/v1/token').single.body), {
        'refresh_token': 'refresh-from-last-run',
      });
      expect(store.value, 'refresh-1');
    },
  );

  test(
    'a refresh token the server no longer honours starts a new identity',
    () async {
      store.value = 'revoked';
      refresh = (_) =>
          (status: 400, body: '{"error_code":"refresh_token_not_found"}');
      final s = session();
      expect(await s.accessToken(), 'sign.up.token');
      expect(store.clears, 1);
      expect(store.value, 'refresh-0');
    },
  );

  test('a flaky network never throws the identity away', () async {
    store.value = 'refresh-from-last-run';
    refresh = (_) => (status: 503, body: '');
    final s = session();
    expect(await s.accessToken(), isNull);
    expect(store.value, 'refresh-from-last-run');
    expect(store.clears, 0);
    expect(
      backend.callsTo('/auth/v1/signup'),
      isEmpty,
      reason: 'a transient failure must not mint a second identity',
    );
    expect(s.isSignedIn, isFalse);

    // After a short pause it tries the same identity again.
    now = now.add(const Duration(seconds: 31));
    refresh = (_) =>
        ok('back.again.token', 'refresh-9', const Duration(hours: 1));
    expect(s.isSignedIn, isTrue);
    expect(await s.accessToken(), 'back.again.token');
    expect(backend.callsTo('/auth/v1/signup'), isEmpty);
  });

  test(
    'when the server refuses anonymous sign-ups it stops trying for a while',
    () async {
      signUp = (_) =>
          (status: 422, body: '{"error_code":"anonymous_provider_disabled"}');
      final s = session();
      expect(await s.accessToken(), isNull);
      expect(s.isSignedIn, isFalse);
      expect(store.value, isNull);
      final requests = backend.calls.length;

      // Inside the block: no new request at all.
      now = now.add(const Duration(minutes: 4));
      expect(s.isSignedIn, isFalse);
      expect(await s.accessToken(), isNull);
      expect(backend.calls, hasLength(requests));

      // After it: tries again, and succeeds once the project allows it.
      now = now.add(const Duration(minutes: 2));
      signUp = (_) =>
          ok('later.token.ok', 'refresh-7', const Duration(hours: 1));
      expect(s.isSignedIn, isTrue);
      expect(await s.accessToken(), 'later.token.ok');
      expect(s.isSignedIn, isTrue);
    },
  );

  test(
    'failing to save the token does not lose this run\'s identity',
    () async {
      store.failWrites = true;
      final s = session();
      expect(await s.accessToken(), 'sign.up.token');
      expect(await s.accessToken(), 'sign.up.token');
      expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
      expect(s.isSignedIn, isTrue);
    },
  );

  test(
    'only the refresh token is ever stored, never the access token',
    () async {
      final s = session();
      await s.accessToken();
      expect(store.value, isNot(contains('sign.up.token')));
      expect(store.value, 'refresh-0');
    },
  );

  group('existingAccessToken (restore without creating)', () {
    test(
      'nothing stored and no session: null, and no request at all',
      () async {
        final s = session();
        expect(await s.existingAccessToken(), isNull);
        expect(backend.calls, isEmpty);
        expect(backend.callsTo('/auth/v1/signup'), isEmpty);
        expect(store.value, isNull);
        expect(s.isSignedIn, isTrue);
      },
    );

    test(
      'a stored token is refreshed once, never signed up, and rotated',
      () async {
        store.value = 'stored-refresh';
        final s = session();
        expect(await s.existingAccessToken(), 'refreshed.1.token');
        expect(backend.callsTo('/auth/v1/signup'), isEmpty);
        expect(backend.callsTo('/auth/v1/token'), hasLength(1));
        expect(jsonDecode(backend.callsTo('/auth/v1/token').single.body), {
          'refresh_token': 'stored-refresh',
        });
        expect(store.value, 'refresh-1', reason: 'the rotated token is kept');
        expect(store.clears, 0);
      },
    );

    test(
      'a rejected refresh token is cleared and returns null, with no signup',
      () async {
        store.value = 'revoked';
        refresh = (_) =>
            (status: 400, body: '{"error_code":"refresh_token_not_found"}');
        final s = session();
        expect(await s.existingAccessToken(), isNull);
        expect(store.clears, 1);
        expect(store.value, isNull);
        expect(backend.callsTo('/auth/v1/signup'), isEmpty);
        expect(s.isSignedIn, isTrue, reason: 'a rejection is not an outage');
      },
    );

    test('a transient failure keeps the identity, makes no signup and does not block', () async {
      store.value = 'stored-refresh';
      refresh = (_) => (status: 503, body: '');
      final s = session();
      expect(await s.existingAccessToken(), isNull);
      expect(store.value, 'stored-refresh');
      expect(store.clears, 0);
      expect(backend.callsTo('/auth/v1/signup'), isEmpty);
      // A failed background restore (app start) must not penalise the
      // person's first explicit action.
      expect(s.isSignedIn, isTrue);

      refresh = (_) =>
          ok('back.token.ok', 'refresh-5', const Duration(hours: 1));
      expect(await s.accessToken(), 'back.token.ok');
      expect(backend.callsTo('/auth/v1/signup'), isEmpty);
    });

    test('a fresh cached session is returned without any request', () async {
      final s = session();
      expect(await s.accessToken(), 'sign.up.token');
      final requests = backend.calls.length;
      expect(await s.existingAccessToken(), 'sign.up.token');
      expect(backend.calls, hasLength(requests));
    });

    test(
      'after an explicit attempt failed it makes no request either',
      () async {
        store.value = 'stored-refresh';
        refresh = (_) => (status: 503, body: '');
        final s = session();
        // A real action (not a background restore) failed, so it backs off.
        expect(await s.accessToken(), isNull);
        final requests = backend.calls.length;
        expect(s.isSignedIn, isFalse);
        expect(await s.existingAccessToken(), isNull);
        expect(backend.calls, hasLength(requests));
      },
    );

    test(
      'while blocked after a signup refusal it makes no request either',
      () async {
        signUp = (_) =>
            (status: 422, body: '{"error_code":"anonymous_provider_disabled"}');
        final s = session();
        expect(await s.accessToken(), isNull);
        final requests = backend.calls.length;
        expect(await s.existingAccessToken(), isNull);
        expect(backend.calls, hasLength(requests));
      },
    );

    test('restore followed by use shares one request', () async {
      store.value = 'stored-refresh';
      final gate = Completer<void>();
      backend = FakeHttpBackend((call) async {
        await gate.future;
        return call.url.path == '/auth/v1/signup'
            ? signUp(call)
            : refresh(call);
      });
      final s = session();
      final restored = s.existingAccessToken();
      final used = s.accessToken();
      gate.complete();
      expect(await restored, 'refreshed.1.token');
      expect(await used, 'refreshed.1.token');
      expect(backend.calls, hasLength(1));
      expect(backend.callsTo('/auth/v1/signup'), isEmpty);
    });

    test('use followed by restore shares one request', () async {
      store.value = 'stored-refresh';
      final gate = Completer<void>();
      backend = FakeHttpBackend((call) async {
        await gate.future;
        return call.url.path == '/auth/v1/signup'
            ? signUp(call)
            : refresh(call);
      });
      final s = session();
      final used = s.accessToken();
      final restored = s.existingAccessToken();
      gate.complete();
      expect(await used, 'refreshed.1.token');
      expect(await restored, 'refreshed.1.token');
      expect(backend.calls, hasLength(1));
    });

    test(
      'after an empty restore, a later accessToken still creates the identity',
      () async {
        final s = session();
        expect(await s.existingAccessToken(), isNull);
        expect(backend.calls, isEmpty);

        expect(await s.accessToken(), 'sign.up.token');
        expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
        expect(store.value, 'refresh-0');
        // And from then on the existing identity can be restored without a signup.
        final again = session();
        expect(await again.existingAccessToken(), 'refreshed.1.token');
        expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
      },
    );

    test(
      'an expiring session is refreshed by restore with the same identity',
      () async {
        final s = session();
        await s.accessToken();
        now = now.add(const Duration(minutes: 59, seconds: 30));
        expect(await s.existingAccessToken(), 'refreshed.1.token');
        expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
        expect(jsonDecode(backend.callsTo('/auth/v1/token').single.body), {
          'refresh_token': 'refresh-0',
        });
      },
    );
  });
}
