import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Source of walking route candidates. M1 injects a verified live provider;
/// this module ships none, so live requests report `provider_unavailable`.
///
/// Implementations must honour [cancellation] and must not start a GPS
/// listener. A live candidate has to come from a real walking network
/// (`walkingNetworkVerified: true`); never join points with straight lines.
abstract interface class WalkingRouteProvider {
  Future<List<sw.RouteCandidate>> findRoutes(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  });
}

/// Looks up the full assistance points for [ids]. M1 wires this to M4; M2
/// never imports the safety-data module. Unknown ids are simply absent.
typedef AssistancePointLookup = Future<List<sw.AssistancePoint>> Function(
  List<String> ids, {
  SafeWalkCancellation? cancellation,
});

/// The provider answered and there is no walkable route between the points.
final class WalkingRouteNotFound implements Exception {
  const WalkingRouteNotFound();

  @override
  String toString() => 'No walking route found';
}

/// The provider could not be reached or is not configured. Internal signal;
/// the payload status is `provider_unavailable`.
final class WalkingRouteProviderUnavailable implements Exception {
  const WalkingRouteProviderUnavailable();

  @override
  String toString() => 'Walking route provider unavailable';
}
