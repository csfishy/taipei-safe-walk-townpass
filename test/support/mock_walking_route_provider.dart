import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Demo provider for `DataMode.mock` only. It draws a straight polyline
/// between origin and destination, labelled as unverified, and never reads
/// files, the network or the device location.
final class MockWalkingRouteProvider implements WalkingRouteProvider {
  const MockWalkingRouteProvider();

  static const providerId = 'mock-straight-line';

  @override
  Future<List<sw.RouteCandidate>> findRoutes(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final line = [
      toGeoJson(request.origin.coordinates),
      toGeoJson(request.destination),
    ];
    final wantsVia =
        request.preference == sw.RouteKind.viaAssistance &&
        request.assistancePointIds.isNotEmpty;
    return [
      sw.RouteCandidate(
        id: 'mock-route-1',
        kind: wantsVia ? sw.RouteKind.viaAssistance : sw.RouteKind.direct,
        geometry: sw.LineString(coordinates: line),
        distanceMeters: polylineLengthMeters(line),
        durationSeconds: null,
        viaPointIds: wantsVia ? request.assistancePointIds : const [],
        provider: providerId,
        walkingNetworkVerified: false,
        explanations: [
          if (request.preference == sw.RouteKind.viaAssistance && !wantsVia)
            '未指定途經據點，回傳直接路線',
          '僅測試 M2 → M3 資料交換',
        ],
        warnings: const ['示範折線，未驗證道路，禁止實地導航'],
      ),
    ];
  }
}
