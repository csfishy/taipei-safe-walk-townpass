import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Internal integration types. These are not additions to the v1 wire schema.
enum CrimeWarningCategory {
  womenChildrenWarning,
  streetSnatching,
  streetRobbery,
}

enum CrimeSpatialPrecision {
  confirmedPublicPlace,
  confirmedRoadSegment,
  approximateArea,
  textOnly,
}

enum CrimeLocationConfidence { verified, approximate, unlocated }

enum CrimeWarningDataStatus { ready, empty, stale, unavailable }

/// An original official row, including unresolved and privacy-blurred text.
final class CrimeLocationRecord {
  CrimeLocationRecord({
    required this.sourceId,
    required this.datasetId,
    required this.resourceId,
    required this.category,
    required this.locationText,
    required this.observedPeriod,
    required this.publishedAt,
    required this.dataUpdatedAt,
    required this.retrievedAt,
    required this.sourceUrl,
    required this.license,
    required this.mode,
    this.sourceResourceName,
    this.sourceFileName,
    this.metadataUpdatedAt,
    required List<String> sourceLimitations,
    required Map<String, String> sourceFields,
  }) : sourceLimitations = List.unmodifiable(sourceLimitations),
       sourceFields = Map.unmodifiable(sourceFields) {
    if (sourceId.isEmpty ||
        datasetId.isEmpty ||
        resourceId.isEmpty ||
        locationText.trim().isEmpty ||
        sourceUrl.scheme != 'https' ||
        sourceUrl.host.isEmpty) {
      throw ArgumentError(
        'Crime record requires identity, location and HTTPS source',
      );
    }
  }

  final String sourceId;
  final String datasetId;
  final String resourceId;
  final CrimeWarningCategory category;
  final String locationText;

  /// Source wording only. Missing dates are not inferred from publication.
  final String? observedPeriod;
  final DateTime? publishedAt;
  final DateTime? dataUpdatedAt;
  final DateTime retrievedAt;
  final Uri sourceUrl;
  final String? license;
  final sw.DataMode mode;
  final String? sourceResourceName;

  /// Preserved verbatim; a half-year in a filename is not an incident date.
  final String? sourceFileName;
  final DateTime? metadataUpdatedAt;
  final List<String> sourceLimitations;
  final Map<String, String> sourceFields;
}

sealed class CrimeWarningGeometry {
  const CrimeWarningGeometry();

  Map<String, Object?> toGeoJson();

  static CrimeWarningGeometry fromGeoJson(Map<String, Object?> json) {
    final type = json['type'];
    final coordinates = json['coordinates'];
    if (type == 'Polygon') {
      return CrimeWarningPolygonGeometry(rings: _rings(coordinates));
    }
    if (type == 'MultiPolygon' && coordinates is List) {
      return CrimeWarningMultiPolygonGeometry(
        polygons: [
          for (final polygon in coordinates)
            CrimeWarningPolygonGeometry(rings: _rings(polygon)),
        ],
      );
    }
    if (type == 'LineString' && coordinates is List) {
      final width = json['corridorWidthMeters'];
      if (width is! num) throw const FormatException('Missing corridor width');
      return CrimeWarningRoadGeometry(
        points: coordinates.map(_coordinate).toList(),
        corridorWidthMeters: width.toDouble(),
      );
    }
    throw const FormatException('Unsupported warning geometry');
  }

  static List<List<sw.Coordinates>> _rings(Object? value) {
    if (value is! List) throw const FormatException('Expected polygon rings');
    return [
      for (final ring in value)
        if (ring is List)
          ring.map(_coordinate).toList()
        else
          throw const FormatException('Expected polygon ring'),
    ];
  }

  static sw.Coordinates _coordinate(Object? value) {
    if (value is! List ||
        value.length != 2 ||
        value[0] is! num ||
        value[1] is! num) {
      throw const FormatException('Expected GeoJSON [longitude, latitude]');
    }
    return sw.Coordinates(
      lat: (value[1] as num).toDouble(),
      lng: (value[0] as num).toDouble(),
    );
  }
}

final class CrimeWarningPolygonGeometry extends CrimeWarningGeometry {
  CrimeWarningPolygonGeometry({required List<List<sw.Coordinates>> rings})
    : rings = List.unmodifiable([
        for (final ring in rings) List<sw.Coordinates>.unmodifiable(ring),
      ]) {
    if (rings.isEmpty) throw ArgumentError('A polygon needs an outer ring');
    for (final ring in rings) {
      if (ring.length < 4 || !_same(ring.first, ring.last)) {
        throw ArgumentError(
          'Warning rings must be closed and have four positions',
        );
      }
      var area = 0.0;
      for (var i = 1; i < ring.length; i++) {
        _localSegment(ring[i - 1], ring[i]);
        area += ring[i - 1].lng * ring[i].lat - ring[i].lng * ring[i - 1].lat;
      }
      if (area.abs() < 1e-12) throw ArgumentError('Degenerate warning ring');
      for (var i = 0; i < ring.length - 1; i++) {
        for (var j = i + 2; j < ring.length - 1; j++) {
          if (i == 0 && j == ring.length - 2) continue;
          if (_crosses(ring[i], ring[i + 1], ring[j], ring[j + 1])) {
            throw ArgumentError('Self-intersecting warning ring');
          }
        }
      }
    }
    for (var i = 1; i < rings.length; i++) {
      if (!_inside(rings[i].first, rings.first) ||
          _ringsCross(rings[i], rings.first)) {
        throw ArgumentError(
          'Warning hole must lie strictly inside its outer ring',
        );
      }
      for (var j = 1; j < i; j++) {
        if (_ringsCross(rings[i], rings[j]) ||
            _inside(rings[i].first, rings[j]) ||
            _inside(rings[j].first, rings[i])) {
          throw ArgumentError('Warning holes must not overlap');
        }
      }
    }
  }

  final List<List<sw.Coordinates>> rings;

  @override
  Map<String, Object?> toGeoJson() => {
    'type': 'Polygon',
    'coordinates': [for (final ring in rings) _wire(ring)],
  };
}

final class CrimeWarningMultiPolygonGeometry extends CrimeWarningGeometry {
  CrimeWarningMultiPolygonGeometry({
    required List<CrimeWarningPolygonGeometry> polygons,
  }) : polygons = List.unmodifiable(polygons) {
    if (polygons.isEmpty) throw ArgumentError('Empty warning multipolygon');
  }

  final List<CrimeWarningPolygonGeometry> polygons;

  @override
  Map<String, Object?> toGeoJson() => {
    'type': 'MultiPolygon',
    'coordinates': [
      for (final polygon in polygons) polygon.toGeoJson()['coordinates'],
    ],
  };
}

final class CrimeWarningRoadGeometry extends CrimeWarningGeometry {
  CrimeWarningRoadGeometry({
    required List<sw.Coordinates> points,
    required this.corridorWidthMeters,
  }) : points = List.unmodifiable(points) {
    if (points.length < 2 ||
        !corridorWidthMeters.isFinite ||
        corridorWidthMeters <= 0 ||
        corridorWidthMeters > 1000 ||
        points.every((point) => _same(point, points.first))) {
      throw ArgumentError(
        'Road needs a real line and an explicit full corridor width',
      );
    }
    for (var i = 1; i < points.length; i++) {
      _localSegment(points[i - 1], points[i]);
    }
  }

  final List<sw.Coordinates> points;

  /// Full width, not radius. Its provenance must be explained by the resolver.
  final double corridorWidthMeters;

  @override
  Map<String, Object?> toGeoJson() => {
    'type': 'LineString',
    'coordinates': _wire(points),
    'corridorWidthMeters': corridorWidthMeters,
  };
}

/// A bounded geographic interpretation with independently reviewable evidence.
final class CrimeWarningZone {
  CrimeWarningZone({
    required this.record,
    required this.geometry,
    required this.spatialPrecision,
    required this.confidence,
    required this.geoSourceUrl,
    required this.geoSourceLicense,
    required this.geoRetrievedAt,
    required this.verifiedAt,
    required this.validUntil,
    required this.accuracyMeters,
    required this.matchEvidence,
    required List<String> limitations,
  }) : limitations = List.unmodifiable(limitations) {
    if ((accuracyMeters != null &&
            (!accuracyMeters!.isFinite || accuracyMeters! < 0)) ||
        matchEvidence.trim().isEmpty ||
        geoSourceUrl.scheme != 'https' ||
        geoSourceUrl.host.isEmpty ||
        !validUntil.isAfter(verifiedAt)) {
      throw ArgumentError('Invalid warning geographic evidence');
    }
  }

  final CrimeLocationRecord record;
  final CrimeWarningGeometry geometry;
  final CrimeSpatialPrecision spatialPrecision;
  final CrimeLocationConfidence confidence;
  final Uri geoSourceUrl;
  final String geoSourceLicense;
  final DateTime geoRetrievedAt;
  final DateTime verifiedAt;
  final DateTime validUntil;

  /// Published positional accuracy, if known. Null must not be rendered as 0 m.
  final double? accuracyMeters;
  final String matchEvidence;
  final List<String> limitations;
  String get sourceId => record.sourceId;

  List<String> routingExclusionReasons({
    required DateTime now,
    required sw.DataMode mode,
  }) {
    final reasons = <String>[];
    if (record.mode != mode) reasons.add('資料模式不符');
    if (record.category != CrimeWarningCategory.womenChildrenWarning) {
      reasons.add('歷史案件地址已模糊化，未核准作精確路段避讓');
    }
    if (confidence != CrimeLocationConfidence.verified ||
        (spatialPrecision != CrimeSpatialPrecision.confirmedPublicPlace &&
            spatialPrecision != CrimeSpatialPrecision.confirmedRoadSegment)) {
      reasons.add('地理精度或可信度不足');
    }
    final accuracy = accuracyMeters;
    if (accuracy != null && accuracy > 100) reasons.add('地理誤差超過適用範圍');
    if (accuracy == null &&
        spatialPrecision != CrimeSpatialPrecision.confirmedPublicPlace) {
      reasons.add('路段或近似區域缺少可用精度資訊');
    }
    if (record.license == null ||
        record.license!.trim().isEmpty ||
        geoSourceLicense.trim().isEmpty) {
      reasons.add('來源授權未確認');
    }
    final updated = record.dataUpdatedAt;
    if (updated == null ||
        updated.isAfter(now.add(const Duration(days: 1))) ||
        now.difference(updated) > const Duration(days: 190)) {
      reasons.add('警示資料更新時間未知或過期');
    }
    if (!validUntil.isAfter(now) ||
        verifiedAt.isAfter(now) ||
        geoRetrievedAt.isAfter(now)) {
      reasons.add('地理核對已過期或時間不合法');
    }
    if (spatialPrecision == CrimeSpatialPrecision.confirmedRoadSegment &&
        geometry is! CrimeWarningRoadGeometry) {
      reasons.add('路段精度與幾何型別不符');
    }
    if (spatialPrecision == CrimeSpatialPrecision.confirmedPublicPlace &&
        geometry is CrimeWarningRoadGeometry) {
      reasons.add('公共場所需範圍幾何');
    }
    return List.unmodifiable(reasons);
  }

  bool isEligibleForRouting({
    required DateTime now,
    required sw.DataMode mode,
  }) => routingExclusionReasons(now: now, mode: mode).isEmpty;
}

final class CrimeWarningSnapshot {
  CrimeWarningSnapshot({
    required List<CrimeLocationRecord> records,
    required List<CrimeWarningZone> zones,
    required this.mode,
    required this.retrievedAt,
    required this.status,
    required this.isComplete,
    required List<String> warnings,
  }) : records = List.unmodifiable(records),
       zones = List.unmodifiable(zones),
       warnings = List.unmodifiable(warnings) {
    final ids = records.map((record) => record.sourceId).toSet();
    if (ids.length != records.length ||
        records.any((record) => record.mode != mode) ||
        zones.any(
          (zone) =>
              zone.record.mode != mode ||
              !records.any((record) => identical(record, zone.record)),
        ) ||
        zones.map((zone) => zone.sourceId).toSet().length != zones.length) {
      throw ArgumentError(
        'Warning snapshot contains duplicate, foreign or mixed-mode data',
      );
    }
  }

  final List<CrimeLocationRecord> records;
  final List<CrimeWarningZone> zones;
  final sw.DataMode mode;
  final DateTime retrievedAt;
  final CrimeWarningDataStatus status;

  /// Full source retrieved/parsed; this does not mean all rows are locatable.
  final bool isComplete;
  final List<String> warnings;
  int get unlocatedRecordCount => records.length - zones.length;
  List<CrimeWarningZone> eligibleZones({required DateTime now}) =>
      List.unmodifiable(
        zones.where((zone) => zone.isEligibleForRouting(now: now, mode: mode)),
      );
}

List<List<double>> _wire(List<sw.Coordinates> points) => [
  for (final point in points) [point.lng, point.lat],
];
bool _same(sw.Coordinates a, sw.Coordinates b) =>
    a.lat == b.lat && a.lng == b.lng;
void _localSegment(sw.Coordinates a, sw.Coordinates b) {
  if ((a.lng - b.lng).abs() >= 180) {
    throw ArgumentError('Warning geometry must not cross the antimeridian');
  }
}

double _turn(sw.Coordinates a, sw.Coordinates b, sw.Coordinates c) =>
    (b.lng - a.lng) * (c.lat - a.lat) - (b.lat - a.lat) * (c.lng - a.lng);
bool _on(sw.Coordinates point, sw.Coordinates a, sw.Coordinates b) =>
    _turn(a, b, point).abs() < 1e-12 &&
    point.lng >= (a.lng < b.lng ? a.lng : b.lng) &&
    point.lng <= (a.lng > b.lng ? a.lng : b.lng) &&
    point.lat >= (a.lat < b.lat ? a.lat : b.lat) &&
    point.lat <= (a.lat > b.lat ? a.lat : b.lat);
bool _crosses(
  sw.Coordinates a,
  sw.Coordinates b,
  sw.Coordinates c,
  sw.Coordinates d,
) =>
    (_turn(a, b, c) * _turn(a, b, d) < 0 &&
        _turn(c, d, a) * _turn(c, d, b) < 0) ||
    _on(c, a, b) ||
    _on(d, a, b) ||
    _on(a, c, d) ||
    _on(b, c, d);
bool _ringsCross(List<sw.Coordinates> a, List<sw.Coordinates> b) {
  for (var i = 1; i < a.length; i++) {
    for (var j = 1; j < b.length; j++) {
      if (_crosses(a[i - 1], a[i], b[j - 1], b[j])) return true;
    }
  }
  return false;
}

bool _inside(sw.Coordinates point, List<sw.Coordinates> ring) {
  var inside = false;
  for (var i = 1; i < ring.length; i++) {
    final a = ring[i - 1], b = ring[i];
    if (_on(point, a, b)) return false;
    if ((a.lat > point.lat) != (b.lat > point.lat) &&
        point.lng <
            (b.lng - a.lng) * (point.lat - a.lat) / (b.lat - a.lat) + a.lng) {
      inside = !inside;
    }
  }
  return inside;
}
