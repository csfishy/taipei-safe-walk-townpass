import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:town_pass/features/safe_walk/presentation/report_range.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_models.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Synthetic coordinates near 0,0; no native GPS, network or persistent data.
sw.Position _fix({
  double lat = 0,
  double accuracy = 10,
  sw.PositionSource source = sw.PositionSource.gps,
  DateTime? at,
}) => sw.Position(
  coordinates: sw.Coordinates(lat: lat, lng: 0),
  source: source,
  accuracyMeters: accuracy,
  observedAt: (at ?? DateTime.now()).toUtc().toIso8601String(),
);
LatLng _north(double meters) => LatLng(meters / 6371000 * 180 / math.pi, 0);
Anomaly _report(String id, double meters) => Anomaly(
  id: id,
  category: AnomalyCategory.lighting,
  at: _north(meters),
  firstReportedAt: DateTime.utc(2026, 11, 13),
  reportCount: 1,
  status: AnomalyStatus.pending,
  updates: ['人工內容 $id'],
);

void main() {
  test('range uses geographic meters and includes the exact boundary', () {
    const center = LatLng(0, 0);
    for (final radius in [100.0, 500.0]) {
      expect(withinReportRange(center, _north(radius - .01), radius), isTrue);
      expect(withinReportRange(center, _north(radius), radius), isTrue);
      expect(withinReportRange(center, _north(radius + .01), radius), isFalse);
    }
    expect(withinReportRange(null, center, 100), isFalse);
    expect(
      withinReportRange(center, const LatLng(double.nan, 0), 500),
      isFalse,
    );
  });

  test('GPS requires fresh real coordinates and at most 30m accuracy', () {
    final now = DateTime.utc(2026, 11, 13);
    expect(reportGpsCenter(_fix(at: now, accuracy: 30), now: now), isNotNull);
    for (final p in [
      _fix(at: now, accuracy: 30.01),
      _fix(at: now, source: sw.PositionSource.manual),
      _fix(at: now, source: sw.PositionSource.mock),
      _fix(at: now.subtract(const Duration(seconds: 61))),
      _fix(at: now.add(const Duration(seconds: 31))),
    ]) {
      expect(reportGpsCenter(p, now: now), isNull);
    }
  });

  late sw.Position? gps;
  late StateSetter update;
  late List<Anomaly> reports;
  late int saves, resolves;
  Future<sw.LocationResult> Function()? locate;
  SafeWalkMap map(WidgetTester t) =>
      t.widget<SafeWalkMap>(find.byType(SafeWalkMap));

  Future<void> mount(WidgetTester t, {LatLng? manual}) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SafeWalkFlow(
              showMapTiles: false,
              livePosition: gps,
              onRefreshMapPosition: () => locate != null
                  ? locate!()
                  : Future.value(
                      gps == null
                          ? sw.LocationFailure(
                              status: sw.LocationFailureStatus.unavailable,
                              message: 'test',
                            )
                          : sw.LocationSuccess(position: gps!),
                    ),
              onLoadReports: () async => reports,
              onStartChanged: (_) {},
              onSaveReport: (draft) async {
                saves++;
                return draft;
              },
              onResolveReport: (_) async {
                resolves++;
              },
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('點擊開始'));
    await t.pumpAndSettle();
    if (manual != null) {
      // A manually picked route origin must never determine a report range.
      await t.tap(find.textContaining('→ 求助地點').first);
      await t.pumpAndSettle();
      await t.tap(find.text('在地圖上選起點'));
      await t.pumpAndSettle();
      map(t).onPick!(manual);
      await t.pumpAndSettle();
    }
  }

  Future<void> begin(WidgetTester t) async {
    await t.tap(find.bySemanticsLabel('回報狀況，在地圖上標出異常'));
    await t.pumpAndSettle();
  }

  setUp(() {
    gps = _fix();
    reports = [];
    saves = 0;
    resolves = 0;
    locate = null;
  });

  testWidgets(
    '500m center is captured GPS, not manual origin, and stays fixed',
    (t) async {
      await mount(t, manual: const LatLng(.1, .1));
      await begin(t);
      expect(map(t).rangeRadiusMeters, 500);
      expect(map(t).rangeCenter!.lat, 0);
      expect(map(t).reportCameraCenter!.lat, 0);
      final camera = MapCamera.of(t.element(find.byType(MarkerLayer)));
      expect(
        camera.visibleBounds.contains(ll.LatLng(_north(500).lat, 0)),
        isTrue,
      );
      expect(
        camera.visibleBounds.contains(ll.LatLng(_north(-500).lat, 0)),
        isTrue,
      );
      update(() => gps = _fix(lat: _north(200).lat));
      await t.pumpAndSettle();
      expect(map(t).rangeCenter!.lat, 0);
      map(t).onPick!(_north(500.1));
      await t.pumpAndSettle();
      expect(map(t).pin, isNull);
      expect(find.textContaining('只能回報啟動時 GPS'), findsOneWidget);
      map(t).onPick!(_north(500));
      await t.pumpAndSettle();
      expect(map(t).pin, isNotNull);
      await t.ensureVisible(find.text('標示到地圖'));
      await t.tap(find.text('標示到地圖'));
      await t.pumpAndSettle();
      expect(saves, 1);
      expect(map(t).rangeRadiusMeters, 100);
      expect(map(t).rangeCenter!.lat, gps!.coordinates.lat);
      expect(
        find.text('關閉回報詳情'),
        findsNothing,
        reason: 'saved point is outside 100m',
      );
    },
  );

  testWidgets(
    '100m follows GPS, hides outside details and closes an expired selection',
    (t) async {
      reports = [_report('near', 70), _report('far', 150)];
      await mount(t);
      expect(map(t).visibleReportIds, {'near'});
      expect(find.bySemanticsLabel('範圍外回報標示'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('人工內容 far')), findsNothing);
      map(t).onAnomaly!('far');
      await t.pumpAndSettle();
      expect(find.text('人工內容 far'), findsNothing);
      map(t).onAnomaly!('near');
      await t.pumpAndSettle();
      expect(find.textContaining('人工內容 near'), findsOneWidget);
      update(() => gps = _fix(lat: _north(400).lat));
      await t.pumpAndSettle();
      expect(map(t).rangeCenter!.lat, gps!.coordinates.lat);
      expect(map(t).visibleReportIds, isEmpty);
      expect(find.textContaining('人工內容 near'), findsNothing);
      expect(find.text('已排除'), findsNothing);
      expect(resolves, 0);
    },
  );

  testWidgets(
    'GPS loss blocks submission even after a valid pin was selected',
    (t) async {
      await mount(t);
      await begin(t);
      map(t).onPick!(_north(40));
      await t.pumpAndSettle();
      update(() => gps = _fix(accuracy: 50));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('標示到地圖'));
      await t.tap(find.text('標示到地圖'));
      await t.pumpAndSettle();
      expect(saves, 0);
      expect(find.textContaining('請重新定位或選點'), findsWidgets);
    },
  );

  testWidgets('stale GPS leaves only triangles and cannot authorize a report', (
    t,
  ) async {
    gps = _fix(at: DateTime.now().subtract(const Duration(seconds: 61)));
    reports = [_report('near', 10)];
    await mount(t, manual: const LatLng(.1, .1));
    expect(map(t).rangeCenter, isNull);
    expect(map(t).visibleReportIds, isEmpty);
    await begin(t);
    map(t).onPick!(_north(10));
    await t.pumpAndSettle();
    expect(map(t).pin, isNull);
    expect(saves, 0);
  });

  testWidgets('cancel and background reject late report GPS results', (
    t,
  ) async {
    final delayed = Completer<sw.LocationResult>();
    locate = () => delayed.future;
    await mount(t);
    await begin(t);
    expect(map(t).rangeCenter, isNull);
    await t.tap(find.text('取消回報'));
    await t.pumpAndSettle();
    delayed.complete(sw.LocationSuccess(position: _fix()));
    await t.pumpAndSettle();
    expect(map(t).reporting, isFalse);
    final background = Completer<sw.LocationResult>();
    locate = () => background.future;
    await begin(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pumpAndSettle();
    background.complete(sw.LocationSuccess(position: _fix()));
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(map(t).reporting, isFalse);
    expect(map(t).reportCameraCenter, isNull);
  });
}
