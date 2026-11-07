import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// One open nearby store with the walking routes to it (same avoiding routes
/// as a saved destination).
final class NearbyHelpOption {
  const NearbyHelpOption({required this.point, required this.route});

  final sw.AssistancePoint point;
  final sw.RouteSuccess route;
}

/// How many avoid areas [route] comes within the radius of.
int areasPassed(sw.RouteCandidate route, List<AvoidArea> areas) => areas
    .where(
      (a) =>
          _minDistanceMeters(route.geometry.coordinates, a.center) <
          a.radiusMeters,
    )
    .length;

/// Safest first (fewest avoid areas on its best route), then fastest, then id.
/// A store's best route is its option with the fewest areas, then fastest.
List<NearbyHelpOption> rankNearbyHelp(
  List<NearbyHelpOption> options,
  List<AvoidArea> areas,
) {
  (int, double) score(NearbyHelpOption o) {
    (int, double)? best;
    for (final r in o.route.routes) {
      final s = (areasPassed(r, areas), _seconds(r));
      if (best == null || _less(s, best)) best = s;
    }
    return best ?? (1 << 30, double.infinity);
  }

  final scored = [for (final o in options) (o, score(o))];
  scored.sort((x, y) {
    if (_less(x.$2, y.$2)) return -1;
    if (_less(y.$2, x.$2)) return 1;
    return x.$1.point.id.compareTo(y.$1.point.id);
  });
  return [for (final (o, _) in scored) o];
}

bool _less((int, double) a, (int, double) b) =>
    a.$1 != b.$1 ? a.$1 < b.$1 : a.$2 < b.$2;

/// Walking time; distance at 1.2 m/s when the provider gives none.
double _seconds(sw.RouteCandidate r) =>
    r.durationSeconds ?? r.distanceMeters / 1.2;

double _minDistanceMeters(List<sw.GeoJsonCoordinate> line, sw.Coordinates p) {
  const metresPerDegree = 111320.0;
  final k = metresPerDegree * math.cos(p.lat * math.pi / 180);
  var best = double.infinity;
  for (var i = 0; i < line.length; i++) {
    final ax = (line[i].longitude - p.lng) * k;
    final ay = (line[i].latitude - p.lat) * metresPerDegree;
    if (i + 1 == line.length) {
      best = math.min(best, math.sqrt(ax * ax + ay * ay));
      break;
    }
    final bx = (line[i + 1].longitude - p.lng) * k;
    final by = (line[i + 1].latitude - p.lat) * metresPerDegree;
    final dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
    final t = len == 0 ? 0.0 : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    best = math.min(best, math.sqrt(x * x + y * y));
  }
  return best;
}
