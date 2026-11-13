import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';

import '../../../support/safe_walk_fixtures.dart';

import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Synthetic annotations only; no device position or live database operation.
Anomaly _report(String id) => Anomaly(
  id: id,
  category: AnomalyCategory.lighting,
  at: const LatLng(0.5, 0.75),
  firstReportedAt: DateTime.utc(2026, 11, 8),
  reportCount: 1,
  status: AnomalyStatus.pending,
  mode: sw.DataMode.live,
);

sw.Position _gps() => sw.Position(
  coordinates: sw.Coordinates(lat: 0.5, lng: 0.75),
  source: sw.PositionSource.gps,
  accuracyMeters: 10,
  observedAt: DateTime.now().toUtc().toIso8601String(),
);

Future<void> _pump(WidgetTester t, SafeWalkFlow flow) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: flow));
  await t.pumpAndSettle();
  await t.tap(find.text('點擊開始'));
  await t.pumpAndSettle();
}

List<Anomaly> _reports(WidgetTester t) =>
    t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).anomalies;

Future<void> _detail(WidgetTester t, String id) async {
  t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).onAnomaly!(id);
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('已排除'));
  await t.pumpAndSettle();
}

Future<void> _form(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('回報狀況，在地圖上標出異常'));
  await t.pumpAndSettle();
  t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).onPick!(
    const LatLng(0.5, 0.75),
  );
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('標示到地圖'));
}

void main() {
  testWidgets(
    'Resolve waits for storage, disables duplicates, and refreshes avoidance once',
    (t) async {
      final confirmation = Completer<void>();
      final stored = [_report('selected'), _report('other')];
      final removals = <String>[];
      final areas = <List<String>>[];
      var plans = 0;
      await _pump(
        t,
        SafeWalkFlow(
          livePosition: _gps(),
          mode: sw.DataMode.live,
          showMapTiles: false,
          homeLocation: sw.Coordinates(lat: 0.6, lng: 0.8),
          onLoadReports: () async => List.of(stored),
          onResolveReport: (id) async {
            removals.add(id);
            await confirmation.future;
            stored.removeWhere((a) => a.id == id);
          },
          onReportsChanged: (spots) =>
              areas.add(spots.map((a) => a.id).toList()),
          onRetryPoints: () => plans++,
        ),
      );
      await _detail(t, 'selected');
      expect(
        t.getCenter(find.text('已排除')).dx,
        greaterThan(t.getCenter(find.text('照明不足')).dx),
      );
      final plansBefore = plans;
      await t.tap(find.text('已排除'));
      await t.pump();
      expect(removals, ['selected']);
      expect(_reports(t), hasLength(2));
      expect(find.text('排除中…'), findsOneWidget);
      expect(find.text('已排除這則回報'), findsNothing);
      expect(t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).onAnomaly, isNull);
      expect(t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).onPick, isNull);
      await t.tap(find.text('排除中…'));
      await t.pump();
      expect(removals, ['selected']);
      confirmation.complete();
      await t.pumpAndSettle();
      expect(_reports(t).map((a) => a.id), ['other']);
      expect(areas.last, ['other']);
      expect(plans, plansBefore + 1);
      expect(find.text('已排除這則回報'), findsOneWidget);
      expect(find.text('已排除'), findsNothing);
      await t.tap(find.bySemanticsLabel('返回'));
      await t.pumpAndSettle();
      await t.tap(find.text('點擊開始'));
      await t.pumpAndSettle();
      expect(_reports(t).map((a) => a.id), ['other']);
    },
  );

  testWidgets(
    'Resolve failure retains detail and marker, then retries the same ID',
    (t) async {
      final removals = <String>[];
      await _pump(
        t,
        SafeWalkFlow(
          livePosition: _gps(),
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async => [_report('selected')],
          onResolveReport: (id) async {
            removals.add(id);
            if (removals.length == 1) throw StateError('synthetic offline');
          },
        ),
      );
      await _detail(t, 'selected');
      await t.tap(find.text('已排除'));
      await t.pumpAndSettle();
      expect(_reports(t).single.id, 'selected');
      expect(find.textContaining('尚未確認回報已排除'), findsOneWidget);
      expect(find.text('已排除'), findsOneWidget);
      expect(find.text('已排除這則回報'), findsNothing);
      await t.tap(find.text('已排除'));
      await t.pumpAndSettle();
      expect(removals, ['selected', 'selected']);
      expect(_reports(t), isEmpty);
      expect(find.text('已排除這則回報'), findsOneWidget);
    },
  );

  testWidgets(
    'Missing Live removal configuration cannot remove a local marker',
    (t) async {
      await _pump(
        t,
        SafeWalkFlow(
          livePosition: _gps(),
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async => [_report('selected')],
        ),
      );
      await _detail(t, 'selected');
      await t.tap(find.text('已排除'));
      await t.pumpAndSettle();
      expect(_reports(t).single.id, 'selected');
      expect(find.textContaining('回報排除功能尚未配置'), findsOneWidget);
      expect(find.text('已排除這則回報'), findsNothing);
    },
  );

  testWidgets(
    'A stale in-flight query cannot resurrect a confirmed resolved marker',
    (t) async {
      final oldQuery = Completer<List<Anomaly>>();
      var queries = 0;
      await _pump(
        t,
        SafeWalkFlow(
          livePosition: _gps(),
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async =>
              ++queries == 1 ? [_report('selected')] : await oldQuery.future,
          onResolveReport: (_) async {},
        ),
      );
      await _detail(t, 'selected');
      t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).onRetryReports!();
      await t.pump();
      await t.tap(find.text('已排除'));
      await t.pumpAndSettle();
      expect(_reports(t), isEmpty);
      oldQuery.complete([_report('selected'), _report('other')]);
      await t.pumpAndSettle();
      expect(_reports(t).map((a) => a.id), ['other']);
    },
  );

  testWidgets(
    'An authoritative reload honors another client removing a locally saved report',
    (t) async {
      await _pump(
        t,
        SafeWalkFlow(
          livePosition: _gps(),
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async => [],
          onSaveReport: (draft) async => _report(draft.id),
        ),
      );
      await _form(t);
      await t.tap(find.text('標示到地圖'));
      await t.pumpAndSettle();
      expect(_reports(t), hasLength(1));
      t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).onRetryReports!();
      await t.pumpAndSettle();
      expect(_reports(t), isEmpty);
    },
  );

  testWidgets(
    'An old save acknowledgment cannot restore a locally resolved report',
    (t) async {
      final pendingSave = Completer<Anomaly>();
      Anomaly? draft;
      var queries = 0;
      await _pump(
        t,
        SafeWalkFlow(
          livePosition: _gps(),
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async => ++queries == 1 ? [] : [_report(draft!.id)],
          onSaveReport: (value) {
            draft = value;
            return pendingSave.future;
          },
          onResolveReport: (_) async {},
        ),
      );
      await _form(t);
      await t.tap(find.text('標示到地圖'));
      await t.pump();
      await t.tap(find.bySemanticsLabel('返回'));
      await t.pumpAndSettle();
      await t.tap(find.text('點擊開始'));
      await t.pumpAndSettle();
      await _detail(t, draft!.id);
      await t.tap(find.text('已排除'));
      await t.pumpAndSettle();
      expect(_reports(t), isEmpty);
      pendingSave.complete(_report(draft!.id));
      await t.pumpAndSettle();
      expect(_reports(t), isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'A late resolve updates stored reports without restarting offscreen routing',
    (t) async {
      final pending = Completer<void>();
      final areas = <List<String>>[];
      var plans = 0;
      await _pump(
        t,
        SafeWalkFlow(
          livePosition: _gps(),
          mode: sw.DataMode.live,
          showMapTiles: false,
          homeLocation: sw.Coordinates(lat: 0.6, lng: 0.8),
          onLoadReports: () async => [_report('selected')],
          onResolveReport: (_) => pending.future,
          onReportsChanged: (spots) =>
              areas.add(spots.map((a) => a.id).toList()),
          onRetryPoints: () => plans++,
        ),
      );
      await _detail(t, 'selected');
      await t.tap(find.text('已排除'));
      await t.pump();
      final plansBefore = plans;
      await t.tap(find.bySemanticsLabel('返回'));
      await t.pumpAndSettle();
      pending.complete();
      await t.pumpAndSettle();
      expect(plans, plansBefore);
      expect(areas.last, isEmpty);
      expect(find.text('已排除這則回報'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('default flow has no demo reports to remove', (t) async {
    var calls = 0;
    await _pump(
      t,
      SafeWalkFlow(
        livePosition: _gps(),
        showMapTiles: false,
        onResolveReport: (_) async => calls++,
      ),
    );
    expect(_reports(t), isEmpty);
    expect(calls, 0);
    expect(find.text('已移除示範回報'), findsNothing);
  });
}
