import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';
import '../../../support/safe_walk_fixtures.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial test coordinates only; no device position or external write.
Anomaly _saved(String id) => Anomaly(
  id: id,
  category: AnomalyCategory.lighting,
  at: const LatLng(0.5, 0.75),
  firstReportedAt: DateTime.utc(2026, 11, 8),
  reportCount: 1,
  status: AnomalyStatus.pending,
  mode: sw.DataMode.live,
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

Future<void> _form(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('回報狀況，在地圖上標出異常'));
  await t.pumpAndSettle();
  t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).onPick!(const LatLng(0.5, 0.75));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('標示到地圖'));
  await t.pumpAndSettle();
}

List<Anomaly> _reports(WidgetTester t) =>
    t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).anomalies;

void main() {
  testWidgets('Saving during initial load preserves other persisted reports', (
    t,
  ) async {
    final query = Completer<List<Anomaly>>();
    await _pump(
      t,
      SafeWalkFlow(
        mode: sw.DataMode.live,
        showMapTiles: false,
        onLoadReports: () => query.future,
        onSaveReport: (draft) async => _saved(draft.id),
      ),
    );
    await _form(t);
    await t.tap(find.text('標示到地圖'));
    await t.pumpAndSettle();
    final savedId = _reports(t).single.id;
    expect(find.text('正在載入已儲存的回報…'), findsOneWidget);
    query.complete([_saved('already-persisted')]);
    await t.pumpAndSettle();
    expect(
      _reports(t).map((report) => report.id),
      containsAll([savedId, 'already-persisted']),
    );
    expect(find.text('正在載入已儲存的回報…'), findsNothing);
  });

  testWidgets(
    'Interrupted initial report load stays visible and can be retried',
    (t) async {
      final interrupted = Completer<List<Anomaly>>();
      final published = <List<String>>[];
      var attempts = 0;
      await _pump(
        t,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () => ++attempts == 1
              ? interrupted.future
              : Future.value([_saved('retried-after-resume')]),
          onReportsChanged: (spots) =>
              published.add(spots.map((spot) => spot.id).toList()),
        ),
      );
      expect(find.text('正在載入已儲存的回報…'), findsOneWidget);
      addTearDown(
        () =>
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.textContaining('回報資料載入已中斷'), findsOneWidget);
      expect(find.text('重新載入回報'), findsOneWidget);
      expect(find.text('正在載入已儲存的回報…'), findsNothing);
      await t.tap(find.text('重新載入回報'));
      await t.pumpAndSettle();
      expect(_reports(t).single.id, 'retried-after-resume');
      expect(published.last, ['retried-after-resume']);
      expect(find.textContaining('回報資料載入已中斷'), findsNothing);
      // A cancelled query completing later cannot replace the retry's results.
      interrupted.complete([]);
      await t.pumpAndSettle();
      expect(_reports(t).single.id, 'retried-after-resume');
    },
  );

  testWidgets('Mock does not call injected live report callbacks', (t) async {
    var calls = 0;
    await _pump(
      t,
      SafeWalkFlow(
        mode: sw.DataMode.mock,
        showMapTiles: false,
        onLoadReports: () async {
          calls++;
          return [];
        },
        onSaveReport: (draft) async {
          calls++;
          return draft;
        },
      ),
    );
    await _form(t);
    await t.tap(find.text('標示到地圖'));
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('已標示在地圖上'), findsNothing);
    expect(find.textContaining('尚未配置'), findsWidgets);
  });

  testWidgets(
    'Live waits for database confirmation and prevents duplicate writes',
    (t) async {
      final response = Completer<Anomaly>();
      final drafts = <Anomaly>[];
      var homeWrites = 0;
      await _pump(
        t,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          showMapTiles: false,
          onHomeChanged: (_) async {
            homeWrites++;
          },
          onLoadReports: () async => [],
          onSaveReport: (draft) {
            drafts.add(draft);
            return response.future;
          },
        ),
      );
      expect(find.text('家在哪裡？'), findsOneWidget);
      await _form(t);
      expect(find.text('這裡發生什麼事？'), findsOneWidget);
      expect(homeWrites, 0, reason: '回報選點不得被尚未設定家的編輯流程攔截');
      await t.enterText(find.byType(TextField), '人工測試');
      await t.tap(find.text('標示到地圖'));
      await t.pump();
      expect(find.text('儲存中…'), findsOneWidget);
      expect(_reports(t), isEmpty);
      await t.tap(find.text('儲存中…'));
      await t.pump();
      expect(drafts, hasLength(1));
      expect(drafts.single.mode, sw.DataMode.live);
      expect(
        drafts.single.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      response.complete(_saved(drafts.single.id));
      await t.pumpAndSettle();
      expect(_reports(t).single.id, drafts.single.id);
      expect(find.text('已儲存並標示在地圖上'), findsOneWidget);
      expect(find.text('仍在發生'), findsNothing);
      expect(find.textContaining('示範轉通報'), findsNothing);
      expect(homeWrites, 0);
    },
  );

  testWidgets(
    'Live failed write retains form and retries with the same request ID',
    (t) async {
      final drafts = <Anomaly>[];
      await _pump(
        t,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async => [],
          onSaveReport: (draft) async {
            drafts.add(draft);
            if (drafts.length == 1) throw StateError('connection failed');
            return _saved(draft.id);
          },
        ),
      );
      await _form(t);
      await t.enterText(find.byType(TextField), '保留補充內容');
      await t.tap(find.text('標示到地圖'));
      await t.pumpAndSettle();
      expect(find.text('尚未確認回報已儲存，請再試一次。'), findsOneWidget);
      expect(find.text('保留補充內容'), findsOneWidget);
      expect(_reports(t), isEmpty);
      expect(find.textContaining('已儲存並標示'), findsNothing);
      await t.tap(find.text('標示到地圖'));
      await t.pumpAndSettle();
      expect(drafts, hasLength(2));
      expect(drafts.first.id, drafts.last.id);
      expect(_reports(t), hasLength(1));
    },
  );

  testWidgets('Live without storage never creates a local success', (t) async {
    await _pump(
      t,
      const SafeWalkFlow(mode: sw.DataMode.live, showMapTiles: false),
    );
    await _form(t);
    await t.tap(find.text('標示到地圖'));
    await t.pumpAndSettle();
    expect(find.text('回報資料庫尚未配置，無法儲存；請稍後再試。'), findsOneWidget);
    expect(_reports(t), isEmpty);
    expect(find.textContaining('已標示在地圖上'), findsNothing);
  });

  testWidgets(
    'Live without position cannot report the default viewport as GPS',
    (t) async {
      await _pump(
        t,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async => [],
        ),
      );
      await t.tap(find.bySemanticsLabel('回報狀況，在地圖上標出異常'));
      await t.pumpAndSettle();
      await t.tap(find.text('用我目前的位置'));
      await t.pumpAndSettle();
      expect(find.text('要回報哪裡？'), findsOneWidget);
      expect(find.text('這裡發生什麼事？'), findsNothing);
    },
  );

  testWidgets(
    'Live reloads persisted reports before requesting an avoiding route',
    (t) async {
      final response = Completer<List<Anomaly>>();
      final events = <String>[];
      await _pump(
        t,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          showMapTiles: false,
          homeLocation: sw.Coordinates(lat: 0.6, lng: 0.8),
          onLoadReports: () => response.future,
          onReportsChanged: (spots) => events.add('reports:${spots.length}'),
          onPlanRoute: (_) => events.add('route'),
        ),
      );
      expect(events, isEmpty);
      expect(find.text('正在載入已儲存的回報…'), findsOneWidget);
      response.complete([_saved('persisted')]);
      await t.pumpAndSettle();
      expect(_reports(t).single.id, 'persisted');
      expect(events, ['reports:1', 'route']);
      await t.tap(find.bySemanticsLabel('返回'));
      await t.pumpAndSettle();
      await t.tap(find.text('點擊開始'));
      await t.pumpAndSettle();
      expect(_reports(t).single.id, 'persisted');
    },
  );

  testWidgets(
    'Live load error is visible and retry replaces it with stored data',
    (t) async {
      var attempts = 0;
      await _pump(
        t,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async {
            if (++attempts == 1) throw StateError('offline');
            return [_saved('loaded')];
          },
        ),
      );
      expect(find.textContaining('回報資料載入失敗'), findsOneWidget);
      await t.tap(find.text('重新載入回報'));
      await t.pumpAndSettle();
      expect(attempts, 2);
      expect(_reports(t).single.id, 'loaded');
      expect(find.textContaining('回報資料載入失敗'), findsNothing);
    },
  );

  testWidgets(
    'A late save preserves a new map query and its confirmed marker',
    (t) async {
      final save = Completer<Anomaly>();
      final newQuery = Completer<List<Anomaly>>();
      var queries = 0;
      await _pump(
        t,
        SafeWalkFlow(
          mode: sw.DataMode.live,
          showMapTiles: false,
          onLoadReports: () async =>
              ++queries == 1 ? [] : await newQuery.future,
          onSaveReport: (_) => save.future,
        ),
      );
      await _form(t);
      await t.tap(find.text('標示到地圖'));
      await t.pump();
      await t.tap(find.bySemanticsLabel('返回'));
      await t.pumpAndSettle();
      await t.tap(find.text('點擊開始'));
      await t.pumpAndSettle();
      save.complete(_saved('confirmed'));
      await t.pumpAndSettle();
      expect(_reports(t).single.id, 'confirmed');
      expect(find.text('正在載入已儲存的回報…'), findsOneWidget);
      // Even a stale read cannot erase a server-confirmed write.
      newQuery.complete([_saved('other')]);
      await t.pumpAndSettle();
      expect(_reports(t).map((a) => a.id), containsAll(['confirmed', 'other']));
      expect(find.text('正在載入已儲存的回報…'), findsNothing);
      expect(find.text('已儲存並標示在地圖上'), findsNothing);
    },
  );

  testWidgets('A late save also refreshes avoidance after a reentered query', (
    t,
  ) async {
    final save = Completer<Anomaly>();
    final published = <List<String>>[];
    await _pump(
      t,
      SafeWalkFlow(
        mode: sw.DataMode.live,
        showMapTiles: false,
        onLoadReports: () async => [],
        onSaveReport: (_) => save.future,
        onReportsChanged: (spots) =>
            published.add(spots.map((spot) => spot.id).toList()),
      ),
    );
    await _form(t);
    await t.tap(find.text('標示到地圖'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('返回'));
    await t.pumpAndSettle();
    await t.tap(find.text('點擊開始'));
    await t.pumpAndSettle();
    expect(published.last, isEmpty);
    save.complete(_saved('late-confirmed'));
    await t.pumpAndSettle();
    expect(_reports(t).single.id, 'late-confirmed');
    expect(published.last, ['late-confirmed']);
  });
}
