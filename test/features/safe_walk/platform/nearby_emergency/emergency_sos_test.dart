import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_message.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_watcher.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

class _Platform implements PlatformService {
  _Platform({this.failure});
  final sw.LocationFailure? failure;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    if (failure != null) return failure!;
    return sw.LocationSuccess(
      position: sw.Position(
        coordinates: sw.Coordinates(lat: 25.033964, lng: 121.564468),
        source: sw.PositionSource.gps,
        accuracyMeters: 8,
        observedAt: _sentAt.toIso8601String(),
      ),
    );
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) => throw UnimplementedError();
}

class _Transport implements NearbyAlertTransport {
  int sendCalls = 0;
  bool fail = false;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {}

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    sendCalls++;
    if (fail) throw const NearbyAlertException('down');
    return 3;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async => [];
}

class _Sms implements SmsSender {
  final sent = <({String number, String body})>[];

  @override
  Future<bool> send({required String number, required String body}) async {
    sent.add((number: number, body: body));
    return true;
  }
}

class _Contacts implements EmergencyContactStore {
  _Contacts([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String phone) async => value = phone;
}

final _sentAt = DateTime.utc(2026, 11, 7, 12, 30);

EmergencyDispatch _dispatch({
  PlatformService? platform,
  _Transport? transport,
  _Sms? sms,
  _Contacts? contacts,
}) => EmergencyDispatch(
  platform: platform ?? _Platform(),
  transport: transport ?? _Transport(),
  sms: sms ?? _Sms(),
  contacts: contacts ?? _Contacts('0912345678'),
  clock: () => _sentAt,
);

void main() {
  _nearbyPopupTests();
  group('emergency message', () {
    test('contains exact coordinates and accuracy without external URLs', () {
      final body = buildEmergencyMessage(
        location: sw.Coordinates(lat: 25.033964, lng: 121.564468),
        sentAt: _sentAt,
        accuracyMeters: 8.4,
      );
      expect(body, contains('25.033964, 121.564468'));
      expect(body, contains('精度約 8 公尺'));
      expect(body, isNot(contains('https://')));
      expect(body, contains('2026-11-07'));
    });
  });

  group('emergency contact', () {
    test('accepts digits with separators and rejects bad input', () {
      expect(isValidEmergencyPhone('0912-345 678'), isTrue);
      expect(isValidEmergencyPhone('+886 912 345 678'), isTrue);
      expect(isValidEmergencyPhone('abc'), isFalse);
      expect(isValidEmergencyPhone('123'), isFalse);
    });

    test('normalizes separators before storing', () {
      expect(normalizeEmergencyPhone(' 0912-345 678 '), '0912345678');
    });
  });

  group('SOS dispatch', () {
    test('sends nearby alert and SMS with the location', () async {
      final transport = _Transport();
      final sms = _Sms();
      final result = await _dispatch(transport: transport, sms: sms).sos(
        mode: sw.DataMode.live,
        senderId: 'sender',
        hasLocationConsent: () => true,
        hasNearbyConsent: () => true,
        hasSmsConsent: () => true,
      );

      expect(transport.sendCalls, 1);
      expect(sms.sent.single.number, '0912345678');
      expect(sms.sent.single.body, contains('25.033964, 121.564468'));
      expect(result.nearbyRecipients, 3);
      expect(result.smsSubmitted, isTrue);
      expect(result.message, contains('後端回報 3 位接收者'));
      expect(result.message, contains('尚未確認發送或送達'));
    });

    test('without a saved contact, only the nearby alert is sent', () async {
      final sms = _Sms();
      final result = await _dispatch(sms: sms, contacts: _Contacts()).sos(
        mode: sw.DataMode.live,
        senderId: 'sender',
        hasLocationConsent: () => true,
        hasNearbyConsent: () => true,
        hasSmsConsent: () => true,
      );

      expect(sms.sent, isEmpty);
      expect(result.smsSubmitted, isFalse);
      expect(result.message, contains('尚未設定有效緊急聯絡人'));
    });

    test('a failed nearby alert still tries the SMS', () async {
      final transport = _Transport()..fail = true;
      final sms = _Sms();
      final result = await _dispatch(transport: transport, sms: sms).sos(
        mode: sw.DataMode.live,
        senderId: 'sender',
        hasLocationConsent: () => true,
        hasNearbyConsent: () => true,
        hasSmsConsent: () => true,
      );

      expect(sms.sent, hasLength(1));
      expect(result.nearbyRecipients, isNull);
      expect(result.message, contains('附近通知請求結果未確認'));
    });

    test('location failure sends nothing', () async {
      final transport = _Transport();
      final sms = _Sms();
      final result =
          await _dispatch(
            platform: _Platform(
              failure: sw.LocationFailure(
                status: sw.LocationFailureStatus.denied,
                message: '定位權限未開啟',
              ),
            ),
            transport: transport,
            sms: sms,
          ).sos(
            mode: sw.DataMode.live,
            senderId: 'sender',
            hasLocationConsent: () => true,
            hasNearbyConsent: () => true,
            hasSmsConsent: () => true,
          );

      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
      expect(result.located, isFalse);
      expect(result.message, contains('無法取得新鮮且精確的 GPS 位置'));
    });

    test('mock mode never sends anything', () async {
      final transport = _Transport();
      final sms = _Sms();
      await _dispatch(
        transport: transport,
        sms: sms,
      ).sos(mode: sw.DataMode.mock, senderId: 'sender');
      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
    });
  });

  group('live SOS page', () {
    Future<void> pump(WidgetTester tester, {bool configured = true}) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: NearbyLiveTestPage(
            service: configured
                ? NearbyEmergencyService(
                    platform: _Platform(),
                    transport: _Transport(),
                  )
                : null,
            dispatch: configured ? _dispatch() : null,
            contacts: _Contacts('0912345678'),
            helperId: 'helper-1',
          ),
        ),
      );
    }

    testWidgets('unconfigured page disables SOS', (tester) async {
      await pump(tester, configured: false);
      expect(find.textContaining('SOS 按鈕已停用'), findsOneWidget);
      final sos = tester.widget<FilledButton>(find.byKey(const Key('sos')));
      expect(sos.onPressed, isNull);
    });

    testWidgets('SOS shows the combined result', (tester) async {
      await pump(tester);
      await tester.pump();
      for (final consent in ['location', 'sms', 'nearby']) {
        await tester.tap(find.byKey(Key('consent-$consent')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('sos')));
      await tester.pumpAndSettle();
      expect(find.textContaining('後端回報 3 位接收者'), findsOneWidget);
      expect(find.textContaining('尚未確認發送或送達'), findsOneWidget);
    });
  });
}

class _AlertTransport extends _Transport {
  final alerts = <NearbyAlert>[];
  int fetchCalls = 0;

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    fetchCalls++;
    final out = List<NearbyAlert>.of(alerts);
    alerts.clear();
    return out;
  }
}

void _nearbyPopupTests() {
  final alert = NearbyAlert(
    alertId: 'a1',
    senderId: 's1',
    location: sw.Coordinates(lat: 25.033964, lng: 121.564468),
    radiusMeters: 500,
    createdAt: DateTime.utc(2026, 11, 7),
  );

  test('watcher emits each alert once', () async {
    final transport = _AlertTransport()..alerts.add(alert);
    final service = NearbyEmergencyService(
      platform: _Platform(),
      transport: transport,
    );
    final watcher = NearbyAlertWatcher(service: service, helperId: 'h');
    final got = <NearbyAlert>[];
    final sub = watcher.alerts.listen(got.add);

    await watcher.poll();
    transport.alerts.add(alert);
    await watcher.poll();

    expect(got.map((a) => a.alertId), ['a1']);
    await sub.cancel();
    watcher.dispose();
  });

  test('popup text has coordinates and creation time without a map link', () {
    final text = nearbyAlertPopupText(alert);
    expect(text, contains('25.033964, 121.564468'));
    expect(text, contains('2026-11-07T00:00:00.000Z（UTC）'));
    expect(text, isNot(contains('http')));
  });

  testWidgets('nearby alerts require explicit helper consent and opt-in', (
    tester,
  ) async {
    final transport = _AlertTransport();
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyLiveTestPage(
          service: NearbyEmergencyService(
            platform: _Platform(),
            transport: transport,
          ),
          dispatch: _dispatch(),
          contacts: _Contacts('0912345678'),
          helperId: 'helper-1',
          pollInterval: const Duration(milliseconds: 10),
        ),
      ),
    );
    transport.alerts.add(alert);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(transport.fetchCalls, 0);
    expect(find.text('附近有人需要協助'), findsNothing);
    expect(find.textContaining('25.033964, 121.564468'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('consent-location')));
    await tester.tap(find.byKey(const Key('consent-location')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('consent-nearby')));
    await tester.tap(find.byKey(const Key('consent-nearby')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('nearby-opt-in')));
    await tester.tap(find.byKey(const Key('nearby-opt-in')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(transport.fetchCalls, greaterThan(0));
    expect(find.text('附近有人需要協助'), findsOneWidget);
    expect(find.textContaining('25.033964, 121.564468'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('consent-nearby')));
    await tester.tap(find.byKey(const Key('consent-nearby')));
    await tester.pump();
    final callsAfterWithdrawal = transport.fetchCalls;
    await tester.pump(const Duration(milliseconds: 50));
    expect(transport.fetchCalls, callsAfterWithdrawal);
    expect(find.text('附近有人需要協助'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
