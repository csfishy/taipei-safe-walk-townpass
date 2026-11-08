import 'package:town_pass/features/safe_walk/navigation/route_preference.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// A product-defined routing buffer around a report or reference position.
/// The radius is a routing preference, not an official incident boundary or
/// an estimate of how accurately the source locates the incident.
final class AvoidArea {
  const AvoidArea({
    required this.id,
    required this.center,
    required this.radiusMeters,
    required this.source,
  });

  /// Product-selected buffer for reports and crime reference positions.
  static const reportRadiusMeters = 50.0;

  /// A route may graze a circle but must stay this far from its centre to
  /// count as "not through the centre".
  static const centerRadiusMeters = 15.0;

  final String id;
  final sw.Coordinates center;
  final double radiusMeters;

  /// Where the area came from, e.g. `report` or `crime`.
  final String source;
}

/// Which areas a route keeps out of.
enum AvoidLevel {
  /// Best walking route, ignoring every area.
  none,

  /// Stays [AvoidArea.centerRadiusMeters] away from every centre.
  center,

  /// Never enters any circle.
  full,
}

/// One planned route and what it still passes.
final class AvoidRouteOption {
  const AvoidRouteOption({
    required this.level,
    required this.route,
    required this.passedAreaIds,
  });

  final AvoidLevel level;

  /// A walking-network route: `walkingNetworkVerified: true`, real provider id.
  final sw.RouteCandidate route;

  /// Areas whose circle this route still enters (empty for [AvoidLevel.full]
  /// unless the walker starts or ends inside one).
  final List<String> passedAreaIds;
}

final class AvoidRoutePlan {
  const AvoidRoutePlan({
    required this.options,
    required this.originInsideAreaIds,
    required this.destinationInsideAreaIds,
    required this.preference,
  });

  /// Up to three options in [AvoidLevel] order; an option identical to the
  /// previous one is dropped. Empty when no walkable route exists at all.
  final List<AvoidRouteOption> options;

  /// Circles the start or end point is already inside. These are ignored by
  /// [AvoidLevel.full] because they cannot be avoided.
  final List<String> originInsideAreaIds;
  final List<String> destinationInsideAreaIds;

  /// The shade/lit preference that was requested and whether it was applied
  /// to every option in this plan.
  final RoutePreference preference;

  AvoidRouteOption? operator [](AvoidLevel level) =>
      options.where((o) => o.level == level).firstOrNull;
}

/// Plans the three route options. Implementations must honour [cancellation],
/// must not read GPS and must only send data after the caller's consent check.
/// [preference] applies to all three options; a planner that cannot honour it
/// reports `applied: false` in [AvoidRoutePlan.preference].
abstract interface class AvoidingRoutePlanner {
  Future<AvoidRoutePlan> plan({
    required sw.Coordinates origin,
    required sw.Coordinates destination,
    required List<AvoidArea> areas,
    required RoutePreferenceKind preference,
    SafeWalkCancellation? cancellation,
  });
}
