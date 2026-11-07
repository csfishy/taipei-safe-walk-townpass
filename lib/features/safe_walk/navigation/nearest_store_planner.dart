import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_point.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Finds the points to consider near [origin]. M1 wires this to
/// `OsmConvenienceStoreSource.findNear` or to M4's repository.
typedef NearbyPointFinder = Future<List<sw.AssistancePoint>> Function(
  sw.Coordinates origin, {
  SafeWalkCancellation? cancellation,
});

enum NearestStoreStatus {
  /// [NearestStoreResult.store] is set.
  found,

  /// The data holds no convenience store recorded as open. Not proof that
  /// none is nearby: OpenStreetMap coverage is incomplete.
  noKnownStore,

  /// The user has not agreed to the lookup; nothing was sent.
  consentRequired,

  /// The lookup failed (no network, server down, bad answer).
  lookupFailed,

  cancelled,
}

final class NearestStore {
  const NearestStore({
    required this.point,
    required this.straightLineMeters,
    required this.walkingRoute,
  });

  final sw.AssistancePoint point;
  final double straightLineMeters;

  /// The walking route our own provider found, or null when no route service
  /// was given or it could not route to this store.
  final sw.RouteCandidate? walkingRoute;
}

final class NearestStoreResult {
  const NearestStoreResult._({
    required this.status,
    this.store,
    this.reason,
    this.warnings = const [],
  });

  final NearestStoreStatus status;
  final NearestStore? store;

  /// A fixed, user-readable reason when [status] is not `found`.
  final String? reason;

  /// Limits the UI must show next to the answer (source, opening hours).
  final List<String> warnings;
}

/// "Take me to the nearest convenience store that is open now."
///
/// 1. Ask [find] for nearby points, then keep convenience stores recorded as
///    open and recently checked (`nearestPoints`).
/// 2. With a [routeService], route to the closest [candidates] stores one
///    after another and pick the shortest real walk; if none can be routed,
///    fall back to the straight-line nearest and say so. (One at a time:
///    `DefaultRouteService` keeps only the newest call.)
///
/// It reads no GPS; [origin] comes from M1. Guidance is only ever shown through
/// the in-app OSM/OSRM flow; no external map app is launched.
final class NearestStorePlanner {
  NearestStorePlanner({
    required this.find,
    this.routeService,
    this.candidates = 3,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NearbyPointFinder find;
  final RouteService? routeService;
  final int candidates;
  final DateTime Function() _clock;

  Future<NearestStoreResult> plan(
    sw.Position origin, {
    required String requestId,
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) async {
    NearestStoreResult failure(NearestStoreStatus status, String reason) =>
        NearestStoreResult._(status: status, reason: reason);
    final here = origin.coordinates;

    final List<sw.AssistancePoint> points;
    try {
      cancellation?.throwIfCancelled();
      points = await raceCancellation(
        find(here, cancellation: cancellation),
        cancellation,
      );
    } on SafeWalkCancelledException {
      return failure(NearestStoreStatus.cancelled, '使用者已取消');
    } on ConsentRequiredException {
      return failure(
        NearestStoreStatus.consentRequired,
        '尚未取得同意，不會向地圖服務查詢附近的便利商店',
      );
    } catch (_) {
      return failure(NearestStoreStatus.lookupFailed, '暫時查不到附近的便利商店，請稍後再試');
    }

    final nearest = nearestPoints(
      origin: here,
      points: points,
      limit: candidates < 1 ? 1 : candidates,
      now: _clock(),
    );
    if (nearest.isEmpty) {
      return failure(
        NearestStoreStatus.noKnownStore,
        '沒有已知營業中的便利商店（資料不完整，不代表附近沒有）',
      );
    }

    var chosen = nearest.first;
    sw.RouteCandidate? chosenRoute;
    final service = routeService;
    if (service != null) {
      for (var i = 0; i < nearest.length; i++) {
        if (cancellation?.isCancelled ?? false) {
          return failure(NearestStoreStatus.cancelled, '使用者已取消');
        }
        final route = await _walkingRoute(
          service,
          origin,
          nearest[i].point,
          '$requestId-${i + 1}',
          mode,
          cancellation,
        );
        if (route == null) continue;
        if (chosenRoute == null ||
            route.distanceMeters < chosenRoute.distanceMeters) {
          chosenRoute = route;
          chosen = nearest[i];
        }
      }
      if (cancellation?.isCancelled ?? false) {
        return failure(NearestStoreStatus.cancelled, '使用者已取消');
      }
    }

    final point = chosen.point;
    return NearestStoreResult._(
      status: NearestStoreStatus.found,
      store: NearestStore(
        point: point,
        straightLineMeters: chosen.distanceMeters,
        walkingRoute: chosenRoute,
      ),
      warnings: [
        ...point.source.limitations,
        if (service != null && chosenRoute == null)
          '無法規劃步行路線，僅依直線距離挑選，不是實際可走的路線；請留意現場路況',
        if (chosenRoute != null) ...chosenRoute.warnings,
      ],
    );
  }

  Future<sw.RouteCandidate?> _walkingRoute(
    RouteService service,
    sw.Position origin,
    sw.AssistancePoint point,
    String requestId,
    sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  ) async {
    try {
      final result = await service.planRoute(
        sw.RouteRequest(
          requestId: requestId,
          mode: mode,
          origin: origin,
          destination: point.coordinates,
          departAt: _clock().toUtc().toIso8601String(),
          preference: sw.RouteKind.direct,
          maxExtraDistanceMeters: 0,
          assistancePointIds: const [],
        ),
        cancellation: cancellation,
      );
      if (result is sw.RouteSuccess && result.routes.isNotEmpty) {
        return result.routes.first;
      }
    } on Object {
      // A failed route for one store must not hide the others.
    }
    return null;
  }
}
