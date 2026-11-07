import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Only injected synthetic fixtures are used. No native SMS, GPS, or HTTP IO.
final _time = DateTime.utc(2026, 11, 7, 12, 30);
sw.LocationResult _fix() => sw.LocationSuccess(
  position: sw.Position(
    coordinates: sw.Coordinates(lat: 25.03, lng: 121.56),
    source: sw.PositionSource.gps,
    accuracyMeters: 8,
    observedAt: _time.toIso8601String(),
  ),
);

class _Platform implements PlatformService {
  int calls = 0;
  Future<sw.LocationResult> Function()? handler;
  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    calls++;
    return handler?.call() ?? Future.value(_fix());
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
  int sends = 0;
  int polls = 0;
  int optIns = 0;
  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    sends++;
    return 2;
  }

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    optIns++;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    polls++;
    return [];
  }
}

class _Sms implements SmsSender {
  int calls = 0;
  SmsHandoffStatus status = SmsHandoffStatus.handedToSystem;
  @override
  Future<SmsHandoffStatus> send({
    required String number,
    required String body,
  }) async {
    calls++;
    return status;
  }
}

class _Contacts implements EmergencyContactStore {
  Future<String?> Function()? readHandler;
  Future<void> Function(String)? writeHandler;
  @override
  Future<String?> read() => readHandler?.call() ?? Future.value('0912345678');
  @override
  Future<void> write(String phone) =>
      writeHandler?.call(phone) ?? Future.value();
}

class _Harness {
  final platform = _Platform();
  final transport = _Transport();
  final sms = _Sms();
  final contacts = _Contacts();

  Future<void> pump(WidgetTester tester, {bool nearbyAvailable = true}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyLiveTestPage(
          service: nearbyAvailable
              ? NearbyEmergencyService(platform: platform, transport: transport)
              : null,
          dispatch: EmergencyDispatch(
            platform: platform,
            transport: transport,
            sms: sms,
            contacts: contacts,
            clock: () => _time,
          ),
          contacts: contacts,
          helperId: 'synthetic-helper',
          pollInterval: const Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pump();
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('status'))).data!;

void main() {
  testWidgets('initial page collects no location and never starts polling', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(h.platform.calls, 0);
    expect(h.transport.polls, 0);
    expect(h.transport.sends, 0);
    expect(h.sms.calls, 0);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('sos'))).onPressed,
      isNull,
    );
  });

  testWidgets('SMS remains independently usable without a nearby service', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, nearbyAvailable: false);
    await _tap(tester, 'consent-location');
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('sos'))).onPressed,
      isNull,
    );
    await _tap(tester, 'consent-sms');
    await _tap(tester, 'sos');
    expect(h.sms.calls, 1);
    expect(h.transport.sends, 0);
    expect(h.transport.polls, 0);
    expect(_status(tester), contains('尚未確認發送或送達'));
  });

  testWidgets(
    'missing SMS permission is shown without claiming a dialog or retrying',
    (tester) async {
      final h = _Harness();
      h.sms.status = SmsHandoffStatus.permissionRequired;
      await h.pump(tester, nearbyAvailable: false);
      await _tap(tester, 'consent-location');
      await _tap(tester, 'consent-sms');
      await _tap(tester, 'sos');

      expect(_status(tester), contains('缺少簡訊權限，本次未提交簡訊'));
      expect(_status(tester), isNot(contains('已要求權限')));
      await tester.pump(const Duration(seconds: 1));
      expect(h.sms.calls, 1);
    },
  );

  for (final interruption in ['cancel', 'background', 'leave', 'consent']) {
    testWidgets('$interruption prevents sending after delayed GPS completes', (
      tester,
    ) async {
      final h = _Harness();
      final pending = Completer<sw.LocationResult>();
      h.platform.handler = () => pending.future;
      await h.pump(tester);
      await _tap(tester, 'consent-location');
      await _tap(tester, 'consent-sms');
      await _tap(tester, 'consent-nearby');
      await _tap(tester, 'sos');
      expect(h.platform.calls, 1);
      switch (interruption) {
        case 'cancel':
          await _tap(tester, 'cancel-operation');
        case 'background':
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pump();
        case 'leave':
          await tester.pumpWidget(const SizedBox());
        case 'consent':
          await _tap(tester, 'consent-location');
      }
      pending.complete(_fix());
      await tester.pump();
      expect(h.transport.sends, 0);
      expect(h.transport.optIns, 0);
      expect(h.transport.polls, 0);
      expect(h.sms.calls, 0);
      expect(tester.takeException(), isNull);
      if (interruption == 'background') {
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const Key('consent-location')),
              )
              .value,
          isFalse,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('consent-sms')))
              .value,
          isFalse,
        );
      }
    });
  }

  testWidgets('late contact read cannot replace user input', (tester) async {
    final h = _Harness();
    final pending = Completer<String?>();
    h.contacts.readHandler = () => pending.future;
    await h.pump(tester);
    await tester.enterText(
      find.byKey(const Key('contact-phone')),
      '0987654321',
    );
    pending.complete('0912345678');
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('contact-phone')))
          .controller!
          .text,
      '0987654321',
    );
  });

  testWidgets('cancelled operation cannot finish a newer SOS operation', (
    tester,
  ) async {
    final h = _Harness();
    final first = Completer<sw.LocationResult>();
    final second = Completer<sw.LocationResult>();
    h.platform.handler = () =>
        h.platform.calls == 1 ? first.future : second.future;
    await h.pump(tester);
    await _tap(tester, 'consent-location');
    await _tap(tester, 'consent-sms');
    await _tap(tester, 'sos');
    await _tap(tester, 'cancel-operation');
    await _tap(tester, 'sos');
    expect(h.platform.calls, 2);
    first.complete(_fix());
    await tester.pump();
    expect(h.sms.calls, 0);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('sos'))).onPressed,
      isNull,
    );
    second.complete(_fix());
    await tester.pump();
    expect(h.sms.calls, 1);
    expect(_status(tester), contains('尚未確認發送或送達'));
  });

  testWidgets('background stops polling and resume requires new consent', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await _tap(tester, 'consent-location');
    await _tap(tester, 'consent-nearby');
    await _tap(tester, 'nearby-opt-in');
    await tester.pump(const Duration(milliseconds: 20));
    expect(h.transport.polls, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final pollsBeforeResume = h.transport.polls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(h.transport.polls, pollsBeforeResume);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('consent-nearby')))
          .value,
      isFalse,
    );
    expect(_status(tester), contains('停止接收不代表伺服器已刪除位置'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('contact write errors are contained without leaking data', (
    tester,
  ) async {
    final h = _Harness();
    h.contacts.writeHandler = (_) async =>
        throw StateError('private contact 0912345678 lat=25.03');
    await h.pump(tester);
    await tester.tap(find.text('儲存緊急聯絡人'));
    await tester.pump();
    expect(_status(tester), contains('操作未完成'));
    expect(_status(tester), isNot(contains('0912345678')));
    expect(_status(tester), isNot(contains('25.03')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed helper location never starts polling or claims acceptance',
    (tester) async {
      final h = _Harness();
      h.platform.handler = () async => sw.LocationFailure(
        status: sw.LocationFailureStatus.unavailable,
        message: 'private provider error lat=25.03',
      );
      await h.pump(tester);
      await _tap(tester, 'consent-location');
      await _tap(tester, 'consent-nearby');
      await _tap(tester, 'nearby-opt-in');
      await tester.pump(const Duration(seconds: 1));
      expect(h.transport.optIns, 0);
      expect(h.transport.polls, 0);
      expect(_status(tester), contains('操作未完成'));
      expect(_status(tester), isNot(contains('25.03')));
      expect(_status(tester), isNot(contains('已接受')));
    },
  );
}
