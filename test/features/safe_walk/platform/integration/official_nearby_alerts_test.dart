// The official entry's nearby backend: absent without configuration, builds
// nothing and creates no account until used, and works end to end with an
// anonymous identity. Fake HTTP and fake store only.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/integration/official_nearby_alerts.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/authenticated_nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/supabase_anonymous_nearby_session.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

import '../supabase/fake_http_backend.dart';

const _env = {
  'SUPABASE_URL': 'https://artificial.example',
  'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_artificial-local-test-key',
};
final _here = sw.Coordinates(lat: 25.033, lng: 121.5654);

class _Store implements NearbySessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String refreshToken) async => value = refreshToken;
  @override
  Future<void> clear() async => value = null;
}

FakeHttpBackend _project({int signUpStatus = 200}) => FakeHttpBackend((call) {
  switch (call.url.path) {
    case '/auth/v1/signup':
      return signUpStatus == 200
          ? (
              status: 200,
              body: authSessionJson(
                refresh: 'refresh-0',
                expiresAt:
                    DateTime.now()
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch ~/
                    1000,
              ),
            )
          : (
              status: signUpStatus,
              body: '{"error_code":"anonymous_provider_disabled"}',
            );
    case '/rest/v1/rpc/nearby_sos_send':
      return (status: 200, body: '2');
    default:
      return (status: 404, body: '{}');
  }
});

void main() {
  test('no Supabase configuration: the feature is simply absent', () {
    expect(createOfficialNearbyAlerts(environment: const {}), isNull);
    expect(
      createOfficialNearbyAlerts(
        environment: const {'SUPABASE_URL': 'https://artificial.example'},
      ),
      isNull,
    );
  });

  test('on the web (no native HTTP client) it is absent too', () {
    expect(createOfficialNearbyAlerts(environment: _env, isWeb: true), isNull);
  });

  test('building it opens nothing and creates no account', () async {
    final backend = _project();
    final store = _Store();
    final transport = createOfficialNearbyAlerts(
      environment: _env,
      isWeb: false,
      store: store,
      createHttpClient: backend.client,
    );
    expect(transport, isA<AuthenticatedNearbyAlertTransport>());
    expect(transport, isA<NearbyAlertPreparation>());
    expect(nearbyBackendUnavailableReason(transport!), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls, isEmpty);
    expect(store.value, isNull);
  });

  test(
    'the first real use creates one anonymous identity and uses it',
    () async {
      final backend = _project();
      final store = _Store();
      final transport = createOfficialNearbyAlerts(
        environment: _env,
        isWeb: false,
        store: store,
        createHttpClient: backend.client,
      )!;

      expect(await (transport as NearbyAlertPreparation).prepare(), isNull);
      expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
      expect(store.value, 'refresh-0');

      final count = await transport.sendEmergencyAlert(
        senderId: 'ignored',
        location: _here,
        radiusMeters: 500,
      );
      expect(count, 2);
      // Still one identity, and the RPC ran under it.
      expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
      final rpc = backend.callsTo('/rest/v1/rpc/nearby_sos_send').single;
      expect(rpc.headers['authorization'], 'Bearer aaaa.bbbb.cccc');
      expect(rpc.headers['apikey'], _env['SUPABASE_PUBLISHABLE_KEY']);
      expect(jsonDecode(rpc.body).keys, containsAll(['p_lat', 'p_lng']));
      expect(rpc.body, isNot(contains('ignored')));
    },
  );

  test(
    'a project that refuses anonymous sign-ins stays unavailable, with no RPC',
    () async {
      final backend = _project(signUpStatus: 422);
      final transport = createOfficialNearbyAlerts(
        environment: _env,
        isWeb: false,
        store: _Store(),
        createHttpClient: backend.client,
      )!;

      final reason = await (transport as NearbyAlertPreparation).prepare();
      expect(
        reason,
        AuthenticatedNearbyAlertTransport.identityUnavailableReason,
      );
      // It now reports unavailable instead of retrying on every tap.
      expect(nearbyBackendUnavailableReason(transport), isNotNull);
      await expectLater(
        transport.sendEmergencyAlert(
          senderId: 'ignored',
          location: _here,
          radiusMeters: 500,
        ),
        throwsA(isA<NearbyAlertException>()),
      );
      expect(backend.callsTo('/rest/v1/rpc/nearby_sos_send'), isEmpty);
      expect(backend.callsTo('/auth/v1/signup'), hasLength(1));
    },
  );
}
