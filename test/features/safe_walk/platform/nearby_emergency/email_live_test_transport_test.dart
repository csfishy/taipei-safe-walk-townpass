import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  late HttpServer server;
  late SharedPreferences prefs;
  late EmailLiveTestTransport transport;
  late FutureOr<Object?> Function(String, Map<String, dynamic>) handle;
  final calls = <String>[];
  final token = 'a' * 64;
  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handle = (name, body) => name == 'login'
        ? [
            {
              'account_id': 'test-only',
              'test_session': token,
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            },
          ]
        : null;
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, startsWith('/rest/v1/rpc/swtest_'));
      final name = request.uri.path.split('swtest_').last;
      calls.add(name);
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      final result = await handle(name, body);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
    transport = EmailLiveTestTransport(
      prefs: prefs,
      rpc: SupabaseRpcClient(
        config: SafeWalkSupabaseConfig(
          url: Uri.parse('http://127.0.0.1:${server.port}'),
          apiKey: 'sb_publishable_test',
          allowInsecureLocalhost: true,
        ),
      ),
    );
  });
  tearDown(() async => server.close(force: true));

  test('invalid email and guest operations make no requests', () async {
    await expectLater(
      transport.login('bad'),
      throwsA(isA<NearbyAlertException>()),
    );
    expect(await transport.restoreExistingIdentity(), isFalse);
    await expectLater(
      transport.fetchPendingAlerts('forged'),
      throwsA(isA<NearbyAlertException>()),
    );
    expect(calls, isEmpty);
  });

  test('email login persists only normalized label, never bearer', () async {
    await transport.login(' Alice@Example.invalid ');
    expect(transport.email, 'alice@example.invalid');
    expect(transport.hasSession, isTrue);
    expect(
      prefs.getString(EmailLiveTestTransport.emailKey),
      'alice@example.invalid',
    );
    expect(
      prefs.getKeys().any((key) => prefs.get(key).toString().contains(token)),
      isFalse,
    );
    expect(calls, ['login']);
  });

  test('helper opt-in, location, send and fetch use only test RPCs', () async {
    await transport.login('a@example.invalid');
    handle = (name, args) {
      expect(args['p_test_session'], token);
      expect(args.containsKey('helperId'), isFalse);
      expect(args.containsKey('senderId'), isFalse);
      if (name == 'send') return 1;
      if (name == 'fetch') {
        return [
          {
            'alert_id': 'test-alert',
            'lat': 25.033,
            'lng': 121.565,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        ];
      }
      return null;
    };
    final location = sw.Coordinates(lat: 25.033, lng: 121.565);
    await transport.setHelperOptIn(
      helperId: 'ignored',
      enabled: true,
      location: location,
    );
    expect(
      await transport.sendEmergencyAlert(
        senderId: 'ignored',
        location: location,
        radiusMeters: 500,
      ),
      1,
    );
    final alerts = await transport.fetchPendingAlerts('ignored');
    expect(alerts.single.alertId, 'test-alert');
    expect(alerts.single.senderId, isNull);
    await transport.setHelperOptIn(helperId: 'ignored', enabled: false);
    expect(calls, [
      'login',
      'opt_in',
      'report_location',
      'send',
      'fetch',
      'opt_out',
    ]);
  });

  test(
    'logout removes this label and never falls back to anonymous signup',
    () async {
      await transport.login('a@example.invalid');
      expect(await transport.logout(), isTrue);
      expect(transport.hasSession, isFalse);
      expect(prefs.containsKey(EmailLiveTestTransport.emailKey), isFalse);
      expect(await transport.restoreExistingIdentity(), isFalse);
      expect(calls, ['login', 'logout']);
    },
  );

  test('late login result cannot restore identity after logout', () async {
    final response = Completer<Object?>();
    final started = Completer<void>();
    handle = (name, args) {
      started.complete();
      return response.future;
    };
    final login = transport.login('late@example.invalid');
    await started.future;
    await transport.logout();
    response.complete([
      {
        'test_session': token,
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      },
    ]);
    await login;
    expect(transport.hasSession, isFalse);
    expect(prefs.containsKey(EmailLiveTestTransport.emailKey), isFalse);
  });

  test('backend rejection stays unavailable and hides raw response', () async {
    handle = (name, args) => {'unexpected': 'not a session'};
    await expectLater(
      transport.login('a@example.invalid'),
      throwsA(isA<NearbyAlertException>()),
    );
    expect(transport.hasSession, isFalse);
    expect(prefs.containsKey(EmailLiveTestTransport.emailKey), isFalse);
  });
}
