import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Synthetic coordinates only. No GPS, database, or routing requests.
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

sw.RouteSuccess _routes({double? seconds = 120}) => sw.RouteSuccess(
  requestId: 'review-50m',
  mode: sw.DataMode.live,
  generatedAt: '2026-11-08T02:00:00+08:00',
  warnings: const ['人工測試路線'],
  routes: [
    for (final alternate in [false, true])
      sw.RouteCandidate(
        id: alternate ? 'detour' : 'direct',
        kind: sw.RouteKind.direct,
        geometry: sw.LineString(
          coordinates: alternate
              ? const [
                  (longitude: 0.75, latitude: 0.5),
                  (longitude: 0.752, latitude: 0.5),
                  (longitude: 0.752, latitude: 0.501),
                  (longitude: 0.75, latitude: 0.501),
                ]
              : const [
                  (longitude: 0.75, latitude: 0.5),
                  (longitude: 0.75, latitude: 0.501),
                ],
        ),
        distanceMeters: alternate ? 550 : 110,
        durationSeconds: seconds,
        viaPointIds: const [],
        provider: 'test-only',
        walkingNetworkVerified: true,
        explanations: [alternate ? '避讓測試路線' : '直接測試路線'],
        warnings: const ['人工測試路線'],
      ),
  ],
);

void main() {
  testWidgets('Live 未設定家不查詢，不顯示預設公司或假的起訖標記', (tester) async {
    final destinations = <sw.Coordinates>[];
    await _pump(
      tester,
      SafeWalkFlow(mode: sw.DataMode.live, onPlanRoute: destinations.add),
    );
    await tester.tap(find.text('安心行'));
    await tester.pumpAndSettle();
    final map = tester.widget<SafeWalkMapView>(find.byType(SafeWalkMapView));
    final renderer = tester.widget<DemoMap>(find.byType(DemoMap));
    expect(destinations, isEmpty);
    expect(map.places.where((p) => p.id == 'work'), isEmpty);
    expect(renderer.showDestination, isFalse);
    expect(renderer.showStart, isFalse);
    expect(map.routeState.path, isNull);
  });

  testWidgets('路線尚不可用仍可獨立管理犯罪查詢及撤回路線同意', (tester) async {
    var manage = 0;
    var revoke = 0;
    await _pump(
      tester,
      SafeWalkFlow(
        mode: sw.DataMode.live,
        crimeQueryStatus: '尚未同意犯罪資料查詢；未送出座標。',
        onManageCrimeConsent: () => manage++,
        onRevokeRoutingConsent: () => revoke++,
      ),
    );
    await tester.tap(find.text('安心行'));
    await tester.pumpAndSettle();
    expect(find.text('尚未同意犯罪資料查詢；未送出座標。'), findsOneWidget);
    await tester.ensureVisible(find.text('犯罪資料查詢同意設定'));
    await tester.tap(find.text('犯罪資料查詢同意設定'));
    await tester.ensureVisible(find.text('撤回路線查詢同意'));
    await tester.tap(find.text('撤回路線查詢同意'));
    expect(manage, 1);
    expect(revoke, 1);
  });

  testWidgets('50 公尺圓形保留，清楚標示產品緩衝且計入犯罪參考位置', (tester) async {
    await _pump(
      tester,
      SafeWalkFlow(
        mode: sw.DataMode.live,
        homeLocation: sw.Coordinates(lat: 0.501, lng: 0.75),
        route: _routes(),
        crimeSpots: const [
          (
            id: 'synthetic-reference',
            at: LatLng(0.5005, 0.75),
            label: '測試來源・2026-01-01・地址參考位置',
          ),
        ],
      ),
    );
    await tester.tap(find.text('安心行'));
    await tester.pumpAndSettle();
    final circles = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles;
    expect(circles, hasLength(1));
    expect(circles.single.radius, 50);
    expect(circles.single.useRadiusInMeter, isTrue);
    expect(find.text('經過 1 個避讓緩衝區'), findsOneWidget);
    expect(find.text('不經過避讓緩衝區'), findsOneWidget);
    await tester.ensureVisible(find.text('50 公尺避讓緩衝區'));
    expect(find.text('50 公尺避讓緩衝區'), findsOneWidget);
    expect(find.textContaining('圓形不是官方認定的犯罪範圍'), findsOneWidget);
    expect(find.text('測試來源・2026-01-01・地址參考位置'), findsOneWidget);
  });

  testWidgets('地圖編輯家先等待裝置儲存，完成後才規劃已選座標', (tester) async {
    final save = Completer<void>();
    final saved = <sw.Coordinates?>[];
    final destinations = <sw.Coordinates>[];
    await _pump(
      tester,
      SafeWalkFlow(
        mode: sw.DataMode.live,
        homeLocation: sw.Coordinates(lat: 0.501, lng: 0.75),
        onHomeChanged: (home) {
          saved.add(home);
          return save.future;
        },
        onPlanRoute: destinations.add,
      ),
    );
    await tester.tap(find.text('安心行'));
    await tester.pumpAndSettle();
    destinations.clear();
    final map = tester.widget<SafeWalkMapView>(find.byType(SafeWalkMapView));
    final pending = map.onEditPlace!('home', '家', const LatLng(0.51, 0.76));
    expect(saved.single!.lat, 0.51);
    expect(destinations, isEmpty);
    save.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(destinations.single.lat, 0.51);
    expect(destinations.single.lng, 0.76);
  });

  testWidgets('一般路線 fallback 的未避讓警告與來源可見', (tester) async {
    final base = _routes();
    await _pump(
      tester,
      SafeWalkFlow(
        mode: sw.DataMode.live,
        homeLocation: sw.Coordinates(lat: 0.501, lng: 0.75),
        route: sw.RouteSuccess(
          requestId: base.requestId,
          mode: base.mode,
          generatedAt: base.generatedAt,
          routes: [base.routes.first],
          warnings: const ['暫時無法避讓緩衝區，這是一般步行路線'],
        ),
      ),
    );
    await tester.tap(find.text('安心行'));
    await tester.pumpAndSettle();
    expect(find.text('路線來源：test-only'), findsOneWidget);
    expect(find.text('暫時無法避讓緩衝區，這是一般步行路線'), findsOneWidget);
  });

  for (final boundary in ['SOS', '背景', '新目的地']) {
    testWidgets('地圖改家的儲存晚到，$boundary 後不重新啟動導航', (tester) async {
      final save = Completer<void>();
      final destinations = <sw.Coordinates>[];
      await _pump(
        tester,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          homeLocation: sw.Coordinates(lat: 0.501, lng: 0.75),
          onHomeChanged: (_) => save.future,
          onPlanRoute: destinations.add,
        ),
      );
      await tester.tap(find.text('安心行'));
      await tester.pumpAndSettle();
      destinations.clear();
      final map = tester.widget<SafeWalkMapView>(find.byType(SafeWalkMapView));
      final pending = map.onEditPlace!('home', '家', const LatLng(0.51, 0.76));
      switch (boundary) {
        case 'SOS':
          await tester.tap(find.text('緊急求助').first);
          await tester.pumpAndSettle();
        case '背景':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        case '新目的地':
          map.onAddPlace('人工目的地', const LatLng(0.52, 0.77));
          await tester.pumpAndSettle();
          expect(destinations.single.lat, 0.52);
          destinations.clear();
      }
      save.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(destinations, isEmpty);
    });
  }

  for (final entry in ['安心行', '回報狀況', '附近求助地點']) {
    testWidgets('$entry 進入 SOS 都通知平台停止導航', (tester) async {
      var left = 0;
      await _pump(tester, SafeWalkFlow(onLeaveMap: () => left++));
      await tester.tap(find.text(entry).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('緊急求助').first);
      await tester.pumpAndSettle();
      expect(left, 1);
    });
  }

  test('選路後保留 Live 無示範政策，未知時間保持未知', () {
    final state = RouteState(
      result: _routes(seconds: null),
      allowDemoFallback: false,
    ).select(1);
    expect(state.allowDemoFallback, isFalse);
    expect(state.best!.id, 'detour');
    expect(state.minutes, isNull);
    expect(
      const RouteState(allowDemoFallback: false).select(1).configured,
      isTrue,
    );
  });
}
