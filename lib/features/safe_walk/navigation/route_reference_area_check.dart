import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// A reviewed reference *area* (a polygon with documented geographic
/// evidence) that real route candidates may be compared against.
///
/// Only an area whose boundary was checked against official geography may be
/// passed in. A single reference coordinate (an address or MRT-exit match) is
/// not an area and must never be turned into one here, by a radius or a box.
/// M1 maps reviewed M4 data into this type; navigation never imports M4.
final class RouteReferenceArea {
  RouteReferenceArea({
    required this.id,
    required this.label,
    required List<sw.GeoJsonCoordinate> ring,
    required this.evidence,
  }) : ring = List.unmodifiable(ring) {
    if (id.isEmpty || label.isEmpty || evidence.isEmpty) {
      throw ArgumentError('id, label and evidence are required');
    }
    if (ring.length < 3 ||
        !ring.every((c) => isValidLatLng(c.latitude, c.longitude))) {
      throw ArgumentError('ring needs at least three valid WGS84 points');
    }
  }

  final String id;
  final String label;

  /// Outer boundary, GeoJSON `[lng, lat]` order; open or closed.
  final List<sw.GeoJsonCoordinate> ring;

  /// Where the boundary came from (shown to the user with the comparison).
  final String evidence;
}

enum RouteAreaComparisonStatus {
  /// No reviewed area exists for this comparison; nothing was compared.
  noReliableArea,

  /// Reviewed areas exist, and no candidate geometry passes through them.
  noCandidateCrosses,

  /// Every candidate crosses an area; there is no other real route to offer.
  noAlternativeRoute,

  /// At least one real candidate crosses an area and another does not.
  alternativeAvailable,
}

/// Facts about one unchanged route candidate.
final class RouteAreaCandidateCheck {
  const RouteAreaCandidateCheck({
    required this.candidateId,
    required this.distanceMeters,
    required this.crossedAreaIds,
  });

  final String candidateId;
  final double distanceMeters;
  final List<String> crossedAreaIds;

  bool get crossesArea => crossedAreaIds.isNotEmpty;
}

final class RouteAreaComparison {
  const RouteAreaComparison({
    required this.status,
    required this.candidates,
    required this.areas,
  });

  final RouteAreaComparisonStatus status;

  /// One entry per input candidate, in input order.
  final List<RouteAreaCandidateCheck> candidates;
  final List<RouteReferenceArea> areas;
}

/// Compares real walking route candidates with reviewed reference areas.
///
/// The candidates are read, never modified: no geometry is rewritten,
/// shortened or detoured to fake an avoidance, and no candidate is ranked as
/// "safe". The result only states which unchanged candidate geometry passes
/// through which reviewed boundary.
RouteAreaComparison compareRoutesWithReferenceAreas(
  List<sw.RouteCandidate> candidates,
  List<RouteReferenceArea> areas,
) {
  final checks = [
    for (final candidate in candidates)
      RouteAreaCandidateCheck(
        candidateId: candidate.id,
        distanceMeters: candidate.distanceMeters,
        crossedAreaIds: List.unmodifiable([
          for (final area in areas)
            if (lineCrossesRing(candidate.geometry.coordinates, area.ring))
              area.id,
        ]),
      ),
  ];
  final RouteAreaComparisonStatus status;
  if (areas.isEmpty) {
    status = RouteAreaComparisonStatus.noReliableArea;
  } else if (checks.every((c) => !c.crossesArea)) {
    status = RouteAreaComparisonStatus.noCandidateCrosses;
  } else if (checks.every((c) => c.crossesArea)) {
    status = RouteAreaComparisonStatus.noAlternativeRoute;
  } else {
    status = RouteAreaComparisonStatus.alternativeAvailable;
  }
  return RouteAreaComparison(
    status: status,
    candidates: List.unmodifiable(checks),
    areas: List.unmodifiable(areas),
  );
}

/// True when the polyline has a vertex inside the ring or a segment that
/// touches a ring edge. Uses a local equirectangular projection, which is
/// adequate at walking scale (a few kilometres).
bool lineCrossesRing(
  List<sw.GeoJsonCoordinate> line,
  List<sw.GeoJsonCoordinate> ring,
) {
  if (line.isEmpty || ring.length < 3) return false;
  final origin = ring.first;
  final cosLat = math.cos(origin.latitude * math.pi / 180);
  _Xy project(sw.GeoJsonCoordinate c) => (
    x: (c.longitude - origin.longitude) * cosLat,
    y: c.latitude - origin.latitude,
  );
  final polygon = ring.map(project).toList(growable: false);
  final path = line.map(project).toList(growable: false);
  if (path.any((p) => _inside(p, polygon))) return true;
  for (var i = 1; i < path.length; i++) {
    for (var j = 0; j < polygon.length; j++) {
      final a = polygon[j];
      final b = polygon[(j + 1) % polygon.length];
      if (_segmentsTouch(path[i - 1], path[i], a, b)) return true;
    }
  }
  return false;
}

typedef _Xy = ({double x, double y});

bool _inside(_Xy p, List<_Xy> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

double _cross(_Xy o, _Xy a, _Xy b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

bool _onSegment(_Xy a, _Xy b, _Xy p) =>
    math.min(a.x, b.x) <= p.x &&
    p.x <= math.max(a.x, b.x) &&
    math.min(a.y, b.y) <= p.y &&
    p.y <= math.max(a.y, b.y);

bool _segmentsTouch(_Xy p1, _Xy p2, _Xy q1, _Xy q2) {
  final d1 = _cross(q1, q2, p1);
  final d2 = _cross(q1, q2, p2);
  final d3 = _cross(p1, p2, q1);
  final d4 = _cross(p1, p2, q2);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  return (d1 == 0 && _onSegment(q1, q2, p1)) ||
      (d2 == 0 && _onSegment(q1, q2, p2)) ||
      (d3 == 0 && _onSegment(p1, p2, q1)) ||
      (d4 == 0 && _onSegment(p1, p2, q2));
}
