import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
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

final _location = sw.LocationSuccess(
  position: sw.Position(
    coordinates: sw.Coordinates(lat: 25.033964, lng: 121.564468),
    source: sw.PositionSource.gps,
    accuracyMeters: 8,
    observedAt: null,
  ),
);

class _Platform implements PlatformService {
  _Platform({this.failure});
  final sw.LocationFailure? failure;

  /// When set, the location request stays pending until this completes.
  Completer<sw.LocationResult>? gate;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    if (gate != null) return gate!.future;
    if (failure != null) return failure!;
    return _location;
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
  int fetchCalls = 0;
  bool fail = false;

  /// When set, the nearby RPC stays pending until this completes.
  Completer<int>? gate;

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
    if (gate != null) return gate!.future;
    return 3;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    fetchCalls++;
    return [];
  }
}

class _Sms implements SmsSender {
  _Sms({this.status = SmsHandoffStatus.handedToSystem});
  SmsHandoffStatus status;
  final sent = <({String number, String body})>[];

  @override
  Future<SmsHandoffStatus> send({
    required String number,
    required String body,
  }) async {
    sent.add((number: number, body: body));
    return status;
  }
}

class _Contacts implements EmergencyContactStore {
  _Contacts([this.value]);
  String? value;

  /// When set, the contact read stays pending until this completes.
  Completer<String?>? readGate;

  @override
  Future<String?> read() async {
    if (readGate != null) return readGate!.future;
    return value;
  }

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

/// Lets already-completed futures and their continuations run.
Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  _nearbyPopupTests();
  group('emergency message', () {
    test('contains exact coordinates, accuracy and an OpenStreetMap link', () {
      final body = buildEmergencyMessage(
        location: sw.Coordinates(lat: 25.033964, lng: 121.564468),
        sentAt: _sentAt,
        accuracyMeters: 8.4,
      );
      expect(body, contains('25.033964, 121.564468'));
      expect(body, contains('精度約 8 公尺'));
      expect(
        body,
        contains('https://www.openstreetmap.org/?mlat=25.033964&mlon=121.564468'),
      );
      expect(body, isNot(contains('google')));
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
      expect(result.smsStatus, SmsHandoffStatus.handedToSystem);
      expect(result.cancelled, isFalse);
      expect(result.message, '已通知 3 位附近的求助者；已交給系統發送簡訊（尚未確認送達）');
      expect(result.message, isNot(contains('已送簡訊')));
    });

    test('without a saved contact, only the nearby alert is sent', () async {
      final sms = _Sms();
      final result = await _dispatch(
        sms: sms,
        contacts: _Contacts(),
      ).sos(mode: sw.DataMode.live, senderId: 'sender');

      expect(sms.sent, isEmpty);
      expect(result.smsStatus, isNull);
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

    test('SMS rejected by the platform is reported as a failure', () async {
      final result = await _dispatch(
        sms: _Sms(status: SmsHandoffStatus.failed),
      ).sos(mode: sw.DataMode.live, senderId: 'sender');
      expect(result.smsStatus, SmsHandoffStatus.failed);
      expect(result.message, contains('簡訊傳送失敗'));
      expect(result.message, isNot(contains('已交給系統')));
    });

    test('missing SMS permission asks the user to tap again', () async {
      final result = await _dispatch(
        sms: _Sms(status: SmsHandoffStatus.permissionRequested),
      ).sos(mode: sw.DataMode.live, senderId: 'sender');
      expect(result.smsStatus, SmsHandoffStatus.permissionRequested);
      expect(result.message, contains('簡訊權限尚未授權'));
      expect(result.message, contains('請再按一次 SOS'));
    });

    test('platform without silent SMS says so', () async {
      final result = await _dispatch(
        sms: _Sms(status: SmsHandoffStatus.unavailable),
      ).sos(mode: sw.DataMode.live, senderId: 'sender');
      expect(result.smsStatus, SmsHandoffStatus.unavailable);
      expect(result.message, contains('此裝置無法自動傳送簡訊'));
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

  group('SOS cancellation', () {
    test('cancelled before starting sends nothing', () async {
      final transport = _Transport();
      final sms = _Sms();
      final cancel = ManualCancellation()..cancel();
      final result = await _dispatch(transport: transport, sms: sms).sos(
        mode: sw.DataMode.live,
        senderId: 'sender',
        cancellation: cancel,
      );
      expect(result.cancelled, isTrue);
      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
    });

    test('location arriving after cancellation is dropped', () async {
      final platform = _Platform()..gate = Completer<sw.LocationResult>();
      final transport = _Transport();
      final sms = _Sms();
      final cancel = ManualCancellation();
      final future = _dispatch(
        platform: platform,
        transport: transport,
        sms: sms,
      ).sos(mode: sw.DataMode.live, senderId: 'sender', cancellation: cancel);

      await _flush();
      cancel.cancel();
      final result = await future;
      platform.gate!.complete(_location);
      await _flush();

      expect(result.cancelled, isTrue);
      expect(result.located, isFalse);
      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
    });

    test('nearby RPC still pending when cancelled: no SMS, honest message', () async {
      final transport = _Transport()..gate = Completer<int>();
      final sms = _Sms();
      final cancel = ManualCancellation();
      final future = _dispatch(transport: transport, sms: sms).sos(
        mode: sw.DataMode.live,
        senderId: 'sender',
        cancellation: cancel,
      );

      await _flush();
      expect(transport.sendCalls, 1);
      cancel.cancel();
      final result = await future;
      transport.gate!.complete(3);
      await _flush();

      expect(result.cancelled, isTrue);
      expect(result.located, isTrue);
      expect(result.nearbyRecipients, isNull);
      expect(result.message, contains('可能已送出'));
      expect(sms.sent, isEmpty);
    });

    test('contact read still pending when cancelled: no SMS', () async {
      final contacts = _Contacts('0912345678')
        ..readGate = Completer<String?>();
      final transport = _Transport();
      final sms = _Sms();
      final cancel = ManualCancellation();
      final future = _dispatch(
        transport: transport,
        sms: sms,
        contacts: contacts,
      ).sos(mode: sw.DataMode.live, senderId: 'sender', cancellation: cancel);

      await _flush();
      expect(transport.sendCalls, 1);
      cancel.cancel();
      final result = await future;
      contacts.readGate!.complete('0912345678');
      await _flush();

      expect(result.cancelled, isTrue);
      expect(result.smsStatus, isNull);
      // The RPC had already completed, so its count is reported as confirmed.
      expect(result.message, '已取消；附近已通知 3 位，未傳簡訊。');
      expect(sms.sent, isEmpty);
    });
  });

  group('live SOS page', () {
    Future<void> pump(
      WidgetTester tester, {
      _Platform? platform,
      _Transport? transport,
      _Sms? sms,
      bool configured = true,
    }) {
      final p = platform ?? _Platform();
      final t = transport ?? _Transport();
      final s = sms ?? _Sms();
      final contacts = _Contacts('0912345678');
      return tester.pumpWidget(
        MaterialApp(
          home: NearbyLiveTestPage(
            service: configured
                ? NearbyEmergencyService(platform: p, transport: t)
                : null,
            dispatch: configured
                ? EmergencyDispatch(
                    platform: p,
                    transport: t,
                    sms: s,
                    contacts: contacts,
                    clock: () => _sentAt,
                  )
                : null,
            contacts: contacts,
            helperId: 'helper-1',
          ),
        ),
      );
    }

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

    testWidgets('leaving the page cancels a pending SOS', (tester) async {
      final platform = _Platform()..gate = Completer<sw.LocationResult>();
      final transport = _Transport();
      final sms = _Sms();
      await pump(tester, platform: platform, transport: transport, sms: sms);
      await tester.pump();
      await tester.tap(find.text('SOS：送出座標給聯絡人並通知附近'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      platform.gate!.complete(_location);
      await tester.pumpAndSettle();

      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
    });

    testWidgets('backgrounding the app cancels a pending SOS', (tester) async {
      final platform = _Platform()..gate = Completer<sw.LocationResult>();
      final transport = _Transport();
      final sms = _Sms();
      await pump(tester, platform: platform, transport: transport, sms: sms);
      await tester.pump();
      await tester.tap(find.text('SOS：送出座標給聯絡人並通知附近'));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      platform.gate!.complete(_location);
      await tester.pumpAndSettle();

      expect(transport.sendCalls, 0);
      expect(sms.sent, isEmpty);
      expect(find.textContaining('已取消'), findsOneWidget);
    });

    testWidgets('inactive state (permission dialog) does not cancel', (tester) async {
      final platform = _Platform()..gate = Completer<sw.LocationResult>();
      final transport = _Transport();
      final sms = _Sms();
      await pump(tester, platform: platform, transport: transport, sms: sms);
      await tester.pump();
      await tester.tap(find.text('SOS：送出座標給聯絡人並通知附近'));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      platform.gate!.complete(_location);
      await tester.pumpAndSettle();

      expect(transport.sendCalls, 1);
      expect(sms.sent, hasLength(1));
      expect(find.textContaining('已通知 3 位附近的求助者'), findsOneWidget);
    });

    testWidgets('revoking help cancels a pending SOS', (tester) async {
      final platform = _Platform();
      final transport = _Transport();
      final sms = _Sms();
      await pump(tester, platform: platform, transport: transport, sms: sms);
      await tester.pump();

      // Opt in while location is still immediate.
      await tester.tap(find.text('開啟協助附近的人（分享一次位置）'));
      await tester.pumpAndSettle();
      expect(find.text('關閉協助附近的人'), findsOneWidget);

      platform.gate = Completer<sw.LocationResult>();
      await tester.tap(find.text('SOS：送出座標給聯絡人並通知附近'));
      await tester.pump();

      await tester.tap(find.text('關閉協助附近的人'));
      await tester.pumpAndSettle();
      platform.gate!.complete(_location);
      await tester.pumpAndSettle();

      expect(sms.sent, isEmpty);
      expect(find.textContaining('已取消'), findsOneWidget);
    });

    testWidgets('page never polls for alerts in the background', (tester) async {
      final transport = _AlertTransport()..alerts.add(_alert);
      await pump(tester, transport: transport);
      await tester.pump(const Duration(seconds: 60));

      expect(transport.fetchCalls, 0);
      expect(find.text('附近有人需要協助'), findsNothing);
    });
  });
}

class _AlertTransport extends _Transport {
  final alerts = <NearbyAlert>[];

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    fetchCalls++;
    final out = List<NearbyAlert>.of(alerts);
    alerts.clear();
    return out;
  }
}

final _alert = NearbyAlert(
  alertId: 'a1',
  senderId: 's1',
  location: sw.Coordinates(lat: 25.033964, lng: 121.564468),
  radiusMeters: 500,
  createdAt: DateTime.utc(2026, 11, 7),
);

void _nearbyPopupTests() {
  final alert = _alert;

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

  test('popup text has exact coordinates and an OpenStreetMap link', () {
    final text = nearbyAlertPopupText(alert);
    expect(text, contains('25.033964, 121.564468'));
    expect(
      text,
      contains('https://www.openstreetmap.org/?mlat=25.033964&mlon=121.564468'),
    );
    expect(text, isNot(contains('google')));
  });

  testWidgets('a manual check shows a popup for a waiting alert', (tester) async {
    final transport = _AlertTransport()..alerts.add(alert);
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
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('查看收到的附近求助'));
    await tester.pumpAndSettle();

    expect(transport.fetchCalls, 1);
    expect(find.text('附近有人需要協助'), findsOneWidget);
    expect(find.textContaining('25.033964, 121.564468'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
