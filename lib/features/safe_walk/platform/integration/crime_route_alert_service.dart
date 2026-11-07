import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_route_geography.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Padding around the route extent for the reference query (degrees, ~200 m).
const crimeRouteQueryPaddingDegrees = 0.002;

enum CrimeRouteReferenceOutcome {
  /// The reviewed query answered (possibly with zero records).
  answered,

  /// Supabase URL / public key not configured; nothing was queried.
  notConfigured,

  /// The configured query failed; see [CrimeRouteAlert.failure].
  failed,

  /// The route extent exceeds the server's bbox limit; nothing was queried.
  routeExtentTooLarge,
}

/// Result of comparing real route candidates with crime reference data.
final class CrimeRouteAlert {
  const CrimeRouteAlert({
    required this.comparison,
    required this.referenceOutcome,
    this.failure,
    this.reference,
    this.geography,
  });

  /// Comparison of the unchanged candidates with reviewed areas only.
  final RouteAreaComparison comparison;
  final CrimeRouteReferenceOutcome referenceOutcome;
  final CrimeReferenceFailure? failure;

  /// Provenance (snapshot, sources) when the query answered.
  final CrimeReferenceResult? reference;
  final CrimeReferenceRouteGeography? geography;
}

/// M1 composition: real OSRM candidates (M2) + reviewed crime reference query
/// (M4, PR #55) -> spatial comparison -> in-app route notice.
///
/// * Only live, walking-network-verified candidates are accepted; a demo route
///   is rejected rather than compared.
/// * Candidate geometry is passed through untouched.
/// * Records from the reviewed query are reference points, never areas, so
///   they are counted and shown with their limits but never compared as a
///   risk area. Only [reviewedAreas] (a source with checked boundaries) is
///   compared. No such source is on main today, so the result is the explicit
///   "no reliable area" state.
final class CrimeRouteAlertService {
  CrimeRouteAlertService({
    required this.repository,
    List<RouteReferenceArea> reviewedAreas = const [],
  }) : reviewedAreas = List.unmodifiable(reviewedAreas);

  final CrimeReferenceRepository repository;
  final List<RouteReferenceArea> reviewedAreas;

  Future<CrimeRouteAlert> assess(
    sw.RouteSuccess route, {
    SafeWalkCancellation? cancellation,
  }) async {
    final candidates = route.routes;
    if (route.mode != sw.DataMode.live ||
        candidates.isEmpty ||
        candidates.any(
          (c) =>
              !c.walkingNetworkVerified ||
              c.provider.toLowerCase().contains('mock'),
        )) {
      throw ArgumentError('only live walking-network routes can be compared');
    }
    final comparison = compareRoutesWithReferenceAreas(
      candidates,
      reviewedAreas,
    );
    final bounds = crimeRouteQueryBounds(candidates);
    if (bounds == null) {
      return CrimeRouteAlert(
        comparison: comparison,
        referenceOutcome: CrimeRouteReferenceOutcome.routeExtentTooLarge,
      );
    }
    try {
      final result = await repository.query(
        mode: sw.DataMode.live,
        query: CrimeReferenceQuery(
          bounds: bounds,
          limit: crimeReferenceMaxLimit,
        ),
        cancellation: cancellation,
      );
      return CrimeRouteAlert(
        comparison: comparison,
        referenceOutcome: CrimeRouteReferenceOutcome.answered,
        reference: result,
        geography: summarizeCrimeReferenceRouteGeography(result),
      );
    } on SafeWalkDataUnavailable {
      return CrimeRouteAlert(
        comparison: comparison,
        referenceOutcome: CrimeRouteReferenceOutcome.notConfigured,
      );
    } on CrimeReferenceQueryException catch (error) {
      return CrimeRouteAlert(
        comparison: comparison,
        referenceOutcome: CrimeRouteReferenceOutcome.failed,
        failure: error.failure,
      );
    }
  }
}

/// Padded extent of all candidate geometry, or null when it exceeds the
/// server's per-side limit.
CrimeReferenceBounds? crimeRouteQueryBounds(List<sw.RouteCandidate> routes) {
  var minLat = double.infinity, minLng = double.infinity;
  var maxLat = -double.infinity, maxLng = -double.infinity;
  for (final route in routes) {
    for (final c in route.geometry.coordinates) {
      minLat = math.min(minLat, c.latitude);
      maxLat = math.max(maxLat, c.latitude);
      minLng = math.min(minLng, c.longitude);
      maxLng = math.max(maxLng, c.longitude);
    }
  }
  if (!minLat.isFinite) return null;
  const pad = crimeRouteQueryPaddingDegrees;
  final bounds = CrimeReferenceBounds(
    minLat: math.max(-90, minLat - pad),
    minLng: math.max(-180, minLng - pad),
    maxLat: math.min(90, maxLat + pad),
    maxLng: math.min(180, maxLng + pad),
  );
  if (bounds.maxLat - bounds.minLat > crimeReferenceMaxBboxSpanDegrees ||
      bounds.maxLng - bounds.minLng > crimeReferenceMaxBboxSpanDegrees) {
    return null;
  }
  return bounds;
}
