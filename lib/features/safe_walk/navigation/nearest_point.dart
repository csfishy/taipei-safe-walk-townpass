import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// An assistance point with its straight-line distance from the origin.
final class NearestPoint {
  const NearestPoint({required this.point, required this.distanceMeters});

  final sw.AssistancePoint point;

  /// Great-circle distance, not walking distance. Ask `RouteService` for the
  /// real walking route to the chosen point.
  final double distanceMeters;
}

/// How recent an `open` check must be to count as open now.
const Duration defaultMaxAvailabilityAge = Duration(hours: 1);

/// Nearest points from an injected list (M1 supplies M4's data). Pure: no I/O.
///
/// Defaults to convenience stores of every chain. The shared contract has no
/// "opens 24 hours" field, so this cannot promise that; what it can say is
/// "recorded as open, and checked recently". With [requireOpenNow], `unknown`
/// and `closed` points are never returned, and neither is an `open` point
/// whose check time is missing, unparseable, in the future or older than
/// [maxAvailabilityAge]. Points that fail the shared semantic checks are
/// skipped. Results are sorted by distance, then id, and may be empty; an
/// empty list means "none known", not "none nearby".
List<NearestPoint> nearestPoints({
  required sw.Coordinates origin,
  required Iterable<sw.AssistancePoint> points,
  Set<sw.AssistancePointKind> kinds = const {
    sw.AssistancePointKind.convenienceStore,
  },
  bool requireOpenNow = true,
  Duration maxAvailabilityAge = defaultMaxAvailabilityAge,
  double? maxDistanceMeters,
  int? limit,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final found = <NearestPoint>[];
  for (final point in points) {
    if (!kinds.contains(point.kind)) continue;
    if (pointProblems(point).isNotEmpty) continue;
    if (requireOpenNow && !_isOpenNow(point, clock, maxAvailabilityAge)) {
      continue;
    }
    final distance = distanceMeters(origin, point.coordinates);
    if (maxDistanceMeters != null && distance > maxDistanceMeters) continue;
    found.add(NearestPoint(point: point, distanceMeters: distance));
  }
  found.sort((a, b) {
    final byDistance = a.distanceMeters.compareTo(b.distanceMeters);
    return byDistance != 0 ? byDistance : a.point.id.compareTo(b.point.id);
  });
  return limit == null || limit >= found.length
      ? List.unmodifiable(found)
      : List.unmodifiable(found.take(limit < 0 ? 0 : limit));
}

bool _isOpenNow(sw.AssistancePoint point, DateTime now, Duration maxAge) {
  if (point.availability != sw.OpeningStatus.open) return false;
  final checkedAt = point.availabilityCheckedAt;
  if (checkedAt == null) return false;
  final parsed = DateTime.tryParse(checkedAt);
  if (parsed == null) return false;
  final age = now.difference(parsed);
  return age >= const Duration(seconds: -30) && age <= maxAge;
}
