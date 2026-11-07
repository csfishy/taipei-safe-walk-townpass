import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/platform/integration/avoiding_route_service.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

sw.RouteCandidate _route(String id) => sw.RouteCandidate(
  id: id,
  kind: sw.RouteKind.direct,
  geometry: sw.LineString(coordinates: const [(longitude: 121.5, latitude: 25.0), (longitude: 121.51, latitude: 25.0)]),
  distanceMeters: 1000,
  durationSeconds: 700,
  viaPointIds: const [],
  provider: 'valhalla-pedestrian',
  walkingNetworkVerified: true,
  explanations: [id],
  warnings: const ['不保證安全'],
);

sw.RouteRequest _request(sw.DataMode mode) => sw.RouteRequest(
  requestId: 'r1',
  mode: mode,
  origin: sw.Position(
    coordinates: sw.Coordinates(lat: 25.0, lng: 121.5),
    source: mode == sw.DataMode.live ? sw.PositionSource.gps : sw.PositionSource.mock,
    accuracyMeters: 10,
    observedAt: DateTime.now().toUtc().toIso8601String(),
  ),
  destination: sw.Coordinates(lat: 25.0, lng: 121.51),
  departAt: DateTime.now().toUtc().toIso8601String(),
  preference: sw.RouteKind.direct,
  maxExtraDistanceMeters: 500,
  assistancePointIds: const [],
);

void main() {
  test('report radius matches between map and planner', () {
    expect(reportAvoidRadiusMeters, AvoidArea.reportRadiusMeters);
  });

  test('live: most-avoiding option first, areas passed through, inside warning', () async {
    final planner = _Planner(
      AvoidRoutePlan(
        options: [
          AvoidRouteOption(level: AvoidLevel.none, route: _route('none'), passedAreaIds: const ['a']),
          AvoidRouteOption(level: AvoidLevel.full, route: _route('full'), passedAreaIds: const []),
        ],
        originInsideAreaIds: const ['b'],
        destinationInsideAreaIds: const [],
      ),
    );
    final areas = [AvoidArea(id: 'a', center: sw.Coordinates(lat: 25.0, lng: 121.505), radiusMeters: 50, source: 'report')];
    final service = AvoidingRouteService(planner: planner, fallback: _Fallback(), areas: () => areas);
    final result = await service.planRoute(_request(sw.DataMode.live)) as sw.RouteSuccess;
    expect(result.routes.map((r) => r.id), ['full', 'none']);
    expect(result.warnings.first, AvoidingRouteService.insideWarning);
    expect(planner.areas.single.id, 'a');
  });

  test('planner unreachable: falls back to OSRM with a warning', () async {
    final fallback = _Fallback();
    final service = AvoidingRouteService(planner: _Planner(null), fallback: fallback, areas: () => const []);
    final result = await service.planRoute(_request(sw.DataMode.live)) as sw.RouteSuccess;
    expect(fallback.calls, 1);
    expect(result.warnings.first, AvoidingRouteService.fallbackWarning);
  });

  test('no options: no_route failure', () async {
    final service = AvoidingRouteService(
      planner: _Planner(const AvoidRoutePlan(options: [], originInsideAreaIds: [], destinationInsideAreaIds: [])),
      fallback: _Fallback(),
      areas: () => const [],
    );
    final result = await service.planRoute(_request(sw.DataMode.live));
    expect((result as sw.RouteFailure).status, sw.RouteFailureStatus.noRoute);
  });

  test('mock requests never reach the planner', () async {
    final planner = _Planner(null);
    final fallback = _Fallback();
    await AvoidingRouteService(planner: planner, fallback: fallback, areas: () => const []).planRoute(_request(sw.DataMode.mock));
    expect(planner.calls, 0);
    expect(fallback.calls, 1);
  });
}

final class _Planner implements AvoidingRoutePlanner {
  _Planner(this.plan_);
  final AvoidRoutePlan? plan_;
  int calls = 0;
  List<AvoidArea> areas = const [];

  @override
  Future<AvoidRoutePlan> plan({required sw.Coordinates origin, required sw.Coordinates destination, required List<AvoidArea> areas, SafeWalkCancellation? cancellation}) async {
    calls++;
    this.areas = areas;
    if (plan_ == null) throw const WalkingRouteProviderUnavailable();
    return plan_!;
  }
}

final class _Fallback implements RouteService {
  int calls = 0;
  @override
  Future<sw.RouteResult> planRoute(sw.RouteRequest request, {SafeWalkCancellation? cancellation}) async {
    calls++;
    return sw.RouteSuccess(requestId: request.requestId, mode: request.mode, generatedAt: DateTime.now().toUtc().toIso8601String(), routes: [_route('osrm')], warnings: const ['一般路線']);
  }
}
