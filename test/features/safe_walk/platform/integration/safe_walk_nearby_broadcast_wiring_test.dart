// 「通知附近的人」按鈕在組合根的接線：預設一律不可用；只有明確注入可用的後端
// 才會送出，而且只在使用者確認之後才取得位置。全部使用假資料，沒有任何網路。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final _here = sw.Coordinates(lat: 25.033, lng: 121.5654);

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
  int locations = 0;
  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    expect(mode, sw.DataMode.live);
    expect(userInitiated, isTrue);
    locations++;
    return sw.LocationSuccess(
      position: sw.Position(
        coordinates: _here,
        source: sw.PositionSource.gps,
        accuracyMeters: 10,
        observedAt: '2026-11-08T00:00:00Z',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements NearbyAlertTransport {
  final sent = <({sw.Coordinates location, int radius})>[];
  int recipients = 2;

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    sent.add((location: location, radius: radiusMeters));
    return recipients;
  }

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {}

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async => [];
}

Future<void> _pump(
  WidgetTester t, {
  required bool live,
  _Platform? platform,
  NearbyAlertTransport? nearby,
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
        nearbyAlerts: nearby,
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

Future<void> _show(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String text) async {
  await _show(t, find.text(text));
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('demo mode never offers to notify anyone', (t) async {
    final platform = _Platform();
    await _pump(t, live: false, platform: platform);
    await _show(t, find.text('通知附近的人：目前無法使用'));
    expect(find.textContaining('示範模式不會通知任何人'), findsOneWidget);
    expect(find.text('通知附近協助者'), findsNothing);
    expect(platform.locations, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live by default: unavailable with the real reason, no GPS', (
    t,
  ) async {
    final platform = _Platform();
    await _pump(t, live: true, platform: platform);
    await _show(t, find.text('通知附近的人：目前無法使用'));
    expect(find.textContaining('目前無法使用；請使用電話或緊急聯絡人求助'), findsOneWidget);
    expect(find.text('通知附近協助者'), findsNothing);
    expect(find.text('確認通知'), findsNothing);
    expect(platform.locations, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('with a usable backend: confirm first, then GPS and one send', (
    t,
  ) async {
    final platform = _Platform();
    final transport = _Transport();
    final speaker = _Speaker();
    await _pump(
      t,
      live: true,
      platform: platform,
      nearby: transport,
      speaker: speaker,
    );
    await _tap(t, '通知附近協助者');
    // Asking to confirm reads no location and sends nothing.
    expect(platform.locations, 0);
    expect(transport.sent, isEmpty);

    await _tap(t, '確認通知');
    expect(platform.locations, 1);
    expect(transport.sent, hasLength(1));
    expect(transport.sent.single.radius, 500);
    expect(transport.sent.single.location.lat, _here.lat);
    expect(speaker.emergencyStops, greaterThan(0));
    await _show(t, find.text('已通知 2 位附近協助者'));
    expect(find.textContaining('不代表有人會趕到'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('declining the confirmation sends nothing and reads no GPS', (
    t,
  ) async {
    final platform = _Platform();
    final transport = _Transport();
    await _pump(t, live: true, platform: platform, nearby: transport);
    await _tap(t, '通知附近協助者');
    await _tap(t, '取消');
    expect(platform.locations, 0);
    expect(transport.sent, isEmpty);
    expect(find.text('通知附近協助者'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
