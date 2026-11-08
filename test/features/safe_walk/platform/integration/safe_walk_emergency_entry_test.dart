// 正式入口的求助接線：110／119 只在「Live＋明確開啟撥號器」時才交給手機，
// 線上報案只在注入時出現；示範與預設一律不碰手機。全部用假的平台，沒有真實撥號。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

typedef _Request = ({
  sw.DataMode mode,
  sw.EmergencyChannel channel,
  bool userInitiated,
  bool allowRealCalls,
});

class _Store implements HomeLocationStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Speaker implements SafeWalkRouteSpeaker {
  int emergencyStops = 0;
  @override
  bool get available => false;
  @override
  void speak(String text, {void Function()? onDone}) => onDone?.call();
  @override
  void stop() {}
  @override
  void setLifecycleActive(bool active) {}
  @override
  Future<void> stopForEmergency() async => emergencyStops++;
  @override
  Future<void> dispose() async {}
}

class _Platform implements PlatformService {
  final requests = <_Request>[];

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async {
    requests.add((
      mode: mode,
      channel: channel,
      userInitiated: userInitiated,
      allowRealCalls: allowRealCalls,
    ));
    return sw.EmergencyActionResult.fromJson({
      'schemaVersion': '1.0.0',
      'channel': channel.wireValue,
      'action': allowRealCalls ? 'dial_link_activated' : 'not_configured',
      'officialReceipt': null,
      'message': allowRealCalls ? '測試：已開啟撥號畫面' : '測試：沒有撥號',
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester t, {
  required bool live,
  required _Platform platform,
  bool dialer = false,
  VoidCallback? officialReport,
  _Speaker? speaker,
}) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: SafeWalkCompositionRoot(
        liveRoutes: live,
        platform: platform,
        allowEmergencyDialer: dialer,
        onOpenOfficialReport: officialReport,
        homeLocationStore: _Store(),
        speaker: speaker ?? _Speaker(),
        watchPosition: () => const Stream<sw.Position>.empty(),
        findStores: (origin, {cancellation}) async => const [],
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('緊急求助').first);
  await t.pumpAndSettle();
}

Finder _t(String s) => find.text(s, skipOffstage: false);
Finder _tc(String s) => find.textContaining(s, skipOffstage: false);

void main() {
  testWidgets('default: 110 never reaches the phone, and the page says so', (
    t,
  ) async {
    final platform = _Platform();
    await _pump(t, live: true, platform: platform);
    expect(_tc('目前沒有撥號設定'), findsOneWidget);
    await t.tap(_t('撥打 110 報警'));
    await t.pumpAndSettle();
    expect(platform.requests, hasLength(1));
    expect(platform.requests.single.allowRealCalls, isFalse);
    expect(platform.requests.single.mode, sw.DataMode.live);
    expect(platform.requests.single.userInitiated, isTrue);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('official entry setup: the tap hands 110 to the phone', (
    t,
  ) async {
    final platform = _Platform();
    await _pump(t, live: true, platform: platform, dialer: true);
    expect(_tc('按下後由手機開啟撥號，不代表已接通或已受理'), findsOneWidget);
    expect(platform.requests, isEmpty, reason: 'nothing happens before a tap');

    await t.tap(_t('撥打 110 報警'));
    await t.pumpAndSettle();
    expect(platform.requests, hasLength(1));
    expect(platform.requests.single.channel, sw.EmergencyChannel.police);
    expect(platform.requests.single.allowRealCalls, isTrue);
    expect(platform.requests.single.userInitiated, isTrue);
    expect(_tc('測試：已開啟撥號畫面'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('119 is its own tap and its own channel', (t) async {
    final platform = _Platform();
    await _pump(t, live: true, platform: platform, dialer: true);
    await t.tap(_t('撥打 119'));
    await t.pumpAndSettle();
    expect(platform.requests.single.channel, sw.EmergencyChannel.fire);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('demo mode ignores the dialer switch', (t) async {
    final platform = _Platform();
    await _pump(t, live: false, platform: platform, dialer: true);
    await t.tap(_t('撥打 110 報警'));
    await t.pumpAndSettle();
    expect(platform.requests.single.mode, sw.DataMode.mock);
    expect(platform.requests.single.allowRealCalls, isFalse);
    await t.pumpWidget(const SizedBox.shrink());
  });

  group('official online reporting', () {
    testWidgets('hidden unless an opener is injected', (t) async {
      await _pump(t, live: true, platform: _Platform(), dialer: true);
      expect(_t('線上報案（臺北通）'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('hidden in demo mode even with an opener', (t) async {
      await _pump(t, live: false, platform: _Platform(), officialReport: () {});
      expect(_t('線上報案（臺北通）'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a tap stops speech first, then opens it once', (t) async {
      var opened = 0;
      final speaker = _Speaker();
      await _pump(
        t,
        live: true,
        platform: _Platform(),
        officialReport: () => opened++,
        speaker: speaker,
      );
      final stopsBefore = speaker.emergencyStops;
      expect(opened, 0);
      await t.tap(_t('線上報案（臺北通）'));
      await t.pumpAndSettle();
      expect(opened, 1);
      expect(speaker.emergencyStops, greaterThan(stopsBefore));
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('it does not place a call or send anything by itself', (
      t,
    ) async {
      final platform = _Platform();
      await _pump(
        t,
        live: true,
        platform: platform,
        dialer: true,
        officialReport: () {},
      );
      await t.tap(_t('線上報案（臺北通）'));
      await t.pumpAndSettle();
      expect(platform.requests, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    });
  });
}
