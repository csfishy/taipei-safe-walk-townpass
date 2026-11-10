import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';
import '../../../support/safe_walk_fixtures.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial routes and positions only; no device or network services.
sw.RouteCandidate _candidate(String id, {double? duration = 1200}) =>
    sw.RouteCandidate(
      id: id,
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: [
          (longitude: 121.5, latitude: 25.0),
          if (id == 'alternative') (longitude: 121.505, latitude: 25.001),
          (longitude: 121.51, latitude: 25.0),
        ],
      ),
      distanceMeters: 1000,
      durationSeconds: duration,
      viaPointIds: const [],
      provider: 'osrm-foot (test)',
      walkingNetworkVerified: true,
      explanations: [id == 'alternative' ? '替代路線' : '第一條路線'],
      warnings: const ['人工測試路線'],
    );

sw.RouteSuccess _result(List<sw.RouteCandidate> routes) => sw.RouteSuccess(
  requestId: 'test',
  mode: sw.DataMode.live,
  generatedAt: '2026-11-08T00:00:00Z',
  routes: routes,
  warnings: const ['人工測試資料'],
);

Widget _map(
  sw.RouteResult result, {
  Map<String, sw.RouteResult> pointRoutes = const {},
  List<sw.AssistancePoint> points = const [],
  String? targetPointId,
  ValueChanged<sw.AssistancePoint?>? onTarget,
  MapStartView start = MapStartView.route,
  VoidCallback? onStart,
  VoidCallback? onEnd,
}) => SafeWalkMapView(
  position: sw.Position(
    coordinates: sw.Coordinates(lat: 25, lng: 121.50501),
    source: sw.PositionSource.gps,
    accuracyMeters: 5,
    observedAt: '2026-11-08T00:00:00Z',
  ),
  pointsState: PointsState(points: points, routes: pointRoutes),
  targetPointId: targetPointId,
  onTarget: onTarget,
  startView: start,
  routeState: RouteState(result: result,),
  anomalies: [],
  onAnomaliesChanged: () {},
  onBack: () {},
  onCall: () {},
  onEmergency: () {},
  places: const [SavedPlace('home', '家', LatLng(25, 121.51))],
  placeId: 'home',
  onSelectPlace: (_) {},
  onAddPlace: (_, _) {},
  onDeletePlace: (_) {},
  onStartNavigation: onStart,
  onEndNavigation: onEnd,
  showMapTiles: false,
);

Future<void> _mount(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(900, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: child));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('guidance discloses absent turns and uses provider duration', (
    t,
  ) async {
    var starts = 0;
    var ends = 0;
    await _mount(
      t,
      _map(
        _result([_candidate('direct')]),
        onStart: () => starts++,
        onEnd: () => ends++,
      ),
    );
    await t.ensureVisible(find.text('開始導覽'));
    await t.tap(find.text('開始導覽'));
    await t.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('此路線未提供轉向指示'), findsOneWidget);
    expect(find.textContaining('約 10 分鐘'), findsOneWidget);
    expect(find.textContaining('後抵達'), findsNothing);
    await t.tap(find.text('結束導覽'));
    await t.pumpAndSettle();
    expect(ends, 1);
  });

  testWidgets('guidance keeps missing provider duration unknown', (t) async {
    await _mount(t, _map(_result([_candidate('direct', duration: null)])));
    await t.ensureVisible(find.text('開始導覽'));
    await t.tap(find.text('開始導覽'));
    await t.pumpAndSettle();
    expect(find.textContaining('時間未知'), findsOneWidget);
    expect(find.textContaining('比例估計'), findsNothing);
  });

  testWidgets('later help routes preserve the selected route option', (
    t,
  ) async {
    final route = _result([_candidate('direct'), _candidate('alternative')]);
    final places = demoAssistancePoints().take(3).toList();
    var points = [places.first];
    var pointRoutes = <String, sw.RouteResult>{places.first.id: route};
    String? target;
    late StateSetter rebuild;
    await _mount(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return _map(
            route,
            points: points,
            pointRoutes: pointRoutes,
            targetPointId: target,
            onTarget: (p) => rebuild(() => target = p?.id),
            start: MapStartView.points,
          );
        },
      ),
    );
    await t.tap(find.text('帶我去這裡').first);
    await t.pumpAndSettle();
    expect(target, places.first.id);
    await t.ensureVisible(find.text('替代路線'));
    await t.tap(find.text('替代路線'));
    await t.pumpAndSettle();
    expect(t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).path, hasLength(3));
    for (final p in places.skip(1)) {
      rebuild(() {
        points = [...points, p];
        pointRoutes = {...pointRoutes, p.id: route};
      });
      await t.pumpAndSettle();
      expect(t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).path, hasLength(3));
    }
  });
}
