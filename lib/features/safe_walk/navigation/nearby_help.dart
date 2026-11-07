import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// One open nearby store with the walking routes to it (same avoiding routes
/// as a saved destination).
final class NearbyHelpOption {
  const NearbyHelpOption({required this.point, required this.route});

  final sw.AssistancePoint point;
  final sw.RouteSuccess route;
}

/// Nearest help points worth routing to: convenience stores and police,
/// closest first. Points recorded as closed are dropped. Points whose hours
/// are unknown are allowed, but at most [maxUnknown] of them, so most of the
/// suggestions are known to be open.
List<sw.AssistancePoint> pickNearbyCandidates(
  sw.Coordinates origin,
  Iterable<sw.AssistancePoint> points, {
  int count = 4,
  int maxUnknown = 1,
}) {
  final sorted =
      [
        for (final p in points)
          if ((p.kind == sw.AssistancePointKind.convenienceStore ||
                  p.kind == sw.AssistancePointKind.police) &&
              p.availability != sw.OpeningStatus.closed &&
              pointProblems(p).isEmpty)
            p,
      ]..sort((a, b) {
        final d = distanceMeters(
          origin,
          a.coordinates,
        ).compareTo(distanceMeters(origin, b.coordinates));
        return d != 0 ? d : a.id.compareTo(b.id);
      });
  final picked = <sw.AssistancePoint>[];
  var unknown = 0;
  for (final p in sorted) {
    if (picked.length == count) break;
    if (p.availability == sw.OpeningStatus.unknown) {
      if (unknown == maxUnknown) continue;
      unknown++;
    }
    picked.add(p);
  }
  return picked;
}
