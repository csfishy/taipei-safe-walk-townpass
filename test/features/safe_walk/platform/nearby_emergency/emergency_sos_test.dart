import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_message.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
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
        observedAt: null,
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
  group('emergency message', () {
    test('contains exact coordinates, accuracy and a Google Maps link', () {
      final body = buildEmergencyMessage(
        location: sw.Coordinates(lat: 25.033964, lng: 121.564468),
        sentAt: _sentAt,
        accuracyMeters: 8.4,
      );
      expect(body, contains('25.033964, 121.564468'));
      expect(body, contains('精度約 8 公尺'));
      expect(body, contains('https://maps.google.com/?q=25.033964,121.564468'));
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
      );

      expect(transport.sendCalls, 1);
      expect(sms.sent.single.number, '0912345678');
      expect(sms.sent.single.body, contains('25.033964, 121.564468'));
      expect(result.nearbyRecipients, 3);
      expect(result.smsSent, isTrue);
      expect(result.message, '已通知 3 位附近的求助者；已送簡訊給緊急聯絡人');
    });

    test('without a saved contact, only the nearby alert is sent', () async {
      final sms = _Sms();
      final result = await _dispatch(
        sms: sms,
        contacts: _Contacts(),
      ).sos(mode: sw.DataMode.live, senderId: 'sender');

      expect(sms.sent, isEmpty);
      expect(result.smsSent, isFalse);
      expect(result.message, contains('尚未設定緊急聯絡人'));
    });

    test('a failed nearby alert still tries the SMS', () async {
      final transport = _Transport()..fail = true;
      final sms = _Sms();
      final result = await _dispatch(transport: transport, sms: sms).sos(
        mode: sw.DataMode.live,
        senderId: 'sender',
      );

      expect(sms.sent, hasLength(1));
      expect(result.nearbyRecipients, isNull);
      expect(result.message, contains('附近求助者通知失敗'));
    });

    test('location failure sends nothing', () async {
      final transport = _Transport();
      final sms = _Sms();
      final result = await _dispatch(
        platform: _Platform(
          failure: sw.LocationFailure(
            status: sw.LocationFailureStatus.denied,
            message: '定位權限未開啟',
          ),
        ),
        transport: transport,
        sms: sms,
      ).sos(mode: sw.DataMode.live, senderId: 'sender');

      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
      expect(result.located, isFalse);
      expect(result.message, contains('定位權限未開啟'));
    });

    test('mock mode never sends anything', () async {
      final transport = _Transport();
      final sms = _Sms();
      await _dispatch(transport: transport, sms: sms).sos(
        mode: sw.DataMode.mock,
        senderId: 'sender',
      );
      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
    });
  });

  group('live SOS page', () {
    Future<void> pump(WidgetTester tester, {bool configured = true}) =>
        tester.pumpWidget(
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

    testWidgets('unconfigured page disables SOS', (tester) async {
      await pump(tester, configured: false);
      expect(find.textContaining('所有按鈕已停用'), findsOneWidget);
      final sos = tester.widget<FilledButton>(
        find.ancestor(
          of: find.textContaining('SOS'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(sos.onPressed, isNull);
    });

    testWidgets('SOS shows the combined result', (tester) async {
      await pump(tester);
      await tester.pump();
      await tester.tap(find.text('SOS：送出座標給聯絡人並通知附近'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已通知 3 位附近的求助者'), findsOneWidget);
    });
  });
}
