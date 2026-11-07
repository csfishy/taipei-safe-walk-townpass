import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';

/// Why a crime reference record cannot be used as a route comparison area.
enum CrimeReferenceAreaExclusion {
  /// A single address / MRT-exit / public-place reference coordinate. It marks
  /// where the official location text was matched, has no documented metre
  /// error and is not a boundary, so it is never widened into an area.
  pointReferenceOnly,

  /// No coordinate (district only, blurred text or unresolved).
  noCoordinate,
}

/// Route-comparison view of one reviewed query page.
///
/// The reviewed read-only query (`safe_walk_crime_reference_query`) returns at
/// most a reference point per record and never a reviewed boundary, so no
/// record here qualifies as a route comparison area. [reliableAreaCount] is
/// therefore always zero for this source; callers must show the "no reliable
/// area" state instead of inventing one.
final class CrimeReferenceRouteGeography {
  const CrimeReferenceRouteGeography({
    required this.totalMatching,
    required this.pageRecordCount,
    required this.pointReferenceCount,
    required this.noCoordinateCount,
  });

  /// Server count of records matching the query, across all pages.
  final int totalMatching;

  /// Records actually returned on this page.
  final int pageRecordCount;
  final int pointReferenceCount;
  final int noCoordinateCount;

  int get reliableAreaCount => 0;

  /// Counts by exclusion reason refer to this page only.
  bool get isPartialPage => pageRecordCount < totalMatching;
}

CrimeReferenceAreaExclusion crimeReferenceAreaExclusion(
  CrimeReferenceRecord record,
) => record.hasReferenceCoordinate
    ? CrimeReferenceAreaExclusion.pointReferenceOnly
    : CrimeReferenceAreaExclusion.noCoordinate;

CrimeReferenceRouteGeography summarizeCrimeReferenceRouteGeography(
  CrimeReferenceResult result,
) {
  var points = 0;
  var none = 0;
  for (final record in result.records) {
    switch (crimeReferenceAreaExclusion(record)) {
      case CrimeReferenceAreaExclusion.pointReferenceOnly:
        points++;
      case CrimeReferenceAreaExclusion.noCoordinate:
        none++;
    }
  }
  return CrimeReferenceRouteGeography(
    totalMatching: result.totalMatching,
    pageRecordCount: result.records.length,
    pointReferenceCount: points,
    noCoordinateCount: none,
  );
}
