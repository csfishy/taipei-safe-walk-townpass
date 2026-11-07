/// Module-local models for the reviewed read-only crime reference query
/// (`public.safe_walk_crime_reference_query`, see
/// `supabase/crime_reference/04_app_read_api.sql`).
///
/// These are historical source records, not deduplicated cases, road-risk
/// scores or real-time safety. A reference coordinate is where the official
/// location text was matched, never a precise incident point.
library;

/// The three cities the reviewed snapshot covers.
const crimeReferenceCities = {'臺北市', '新北市', '基隆市'};

/// Server-enforced bounds, mirrored so invalid queries fail before a request.
const crimeReferenceMaxLimit = 200;
const crimeReferenceMaxOffset = 5000;
const crimeReferenceMaxBboxSpanDegrees = 0.5;

/// Limitations every presentation of these records must keep visible.
const crimeReferenceLimitations = [
  '官方公開案件資料的來源紀錄，未跨來源去重，不代表全部犯罪案件。',
  '參考座標只代表原始地點文字的參考位置，不是精確案發點，也不是避讓路段。',
  '無法核對位置者座標留空，不以行政區中心補值。',
  '歷史資料不等於即時道路風險或安全保證。',
];

/// How precisely the official location text could be placed.
enum CrimeSpatialPrecision {
  publicPlaceReference('public_place_reference'),
  roadSegmentReference('road_segment_reference'),
  addressRangeReference('address_range_reference'),
  addressReference('address_reference'),
  districtOnly('district_only'),
  blurredText('blurred_text'),
  unresolved('unresolved');

  const CrimeSpatialPrecision(this.wireValue);

  final String wireValue;

  /// Coarse levels must never carry a coordinate.
  bool get allowsCoordinates =>
      this != districtOnly && this != blurredText && this != unresolved;

  static CrimeSpatialPrecision? fromWire(Object? value) {
    for (final v in values) {
      if (v.wireValue == value) return v;
    }
    return null;
  }
}

/// Confidence of the text-to-reference match, not of the incident itself.
enum CrimeMatchConfidence {
  high('high'),
  medium('medium'),
  unknown('unknown');

  const CrimeMatchConfidence(this.wireValue);

  final String wireValue;

  static CrimeMatchConfidence? fromWire(Object? value) {
    for (final v in values) {
      if (v.wireValue == value) return v;
    }
    return null;
  }
}

enum CrimeCoordinateStatus {
  notProvided('not_provided'),
  referenceGeocoded('reference_geocoded'),
  sourceProvided('source_provided');

  const CrimeCoordinateStatus(this.wireValue);

  final String wireValue;

  static CrimeCoordinateStatus? fromWire(Object? value) {
    for (final v in values) {
      if (v.wireValue == value) return v;
    }
    return null;
  }
}

/// Optional geographic filter. Records without a coordinate never match it.
final class CrimeReferenceBounds {
  const CrimeReferenceBounds({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });

  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;
}

/// One page of a query. Validate with [validate] before sending.
final class CrimeReferenceQuery {
  const CrimeReferenceQuery({
    this.city,
    this.category,
    this.from,
    this.to,
    this.bounds,
    this.limit = 50,
    this.offset = 0,
  });

  final String? city;
  final String? category;

  /// Inclusive `YYYY-MM-DD` dates.
  final String? from;
  final String? to;
  final CrimeReferenceBounds? bounds;
  final int limit;
  final int offset;

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Throws [ArgumentError] naming the invalid field (never its value).
  void validate() {
    if (city != null && !crimeReferenceCities.contains(city)) {
      throw ArgumentError('city must be 臺北市, 新北市 or 基隆市');
    }
    final c = category;
    if (c != null && (c.trim().isEmpty || c.length > 64)) {
      throw ArgumentError('category must be 1-64 characters');
    }
    for (final (name, value) in [('from', from), ('to', to)]) {
      if (value != null &&
          (!_date.hasMatch(value) || DateTime.tryParse(value) == null)) {
        throw ArgumentError('$name must be YYYY-MM-DD');
      }
    }
    if (from != null && to != null && from!.compareTo(to!) > 0) {
      throw ArgumentError('from must not be after to');
    }
    if (limit < 1 || limit > crimeReferenceMaxLimit) {
      throw ArgumentError('limit must be 1-$crimeReferenceMaxLimit');
    }
    if (offset < 0 || offset > crimeReferenceMaxOffset) {
      throw ArgumentError('offset must be 0-$crimeReferenceMaxOffset');
    }
    final b = bounds;
    if (b != null) {
      final valid =
          [b.minLat, b.minLng, b.maxLat, b.maxLng].every((v) => v.isFinite) &&
          b.minLat >= -90 &&
          b.maxLat <= 90 &&
          b.minLng >= -180 &&
          b.maxLng <= 180 &&
          b.minLat <= b.maxLat &&
          b.minLng <= b.maxLng &&
          b.maxLat - b.minLat <= crimeReferenceMaxBboxSpanDegrees &&
          b.maxLng - b.minLng <= crimeReferenceMaxBboxSpanDegrees;
      if (!valid) {
        throw ArgumentError(
          'bounds must be ordered WGS84 within '
          '$crimeReferenceMaxBboxSpanDegrees degrees',
        );
      }
    }
  }

  /// Named RPC arguments; null filters are sent as null.
  Map<String, Object?> toRpcArguments() => {
    'p_city': city,
    'p_category': category,
    'p_from': from,
    'p_to': to,
    'p_min_lat': bounds?.minLat,
    'p_min_lng': bounds?.minLng,
    'p_max_lat': bounds?.maxLat,
    'p_max_lng': bounds?.maxLng,
    'p_limit': limit,
    'p_offset': offset,
  };
}

/// The pinned reviewed snapshot that answered the query.
final class CrimeReferenceSnapshot {
  const CrimeReferenceSnapshot({
    required this.snapshotId,
    required this.label,
    required this.asOfDate,
    required this.importedAt,
    required this.recordCount,
  });

  final String snapshotId;
  final String label;

  /// Latest event date the snapshot may contain (`YYYY-MM-DD`).
  final String asOfDate;
  final String importedAt;
  final int recordCount;
}

/// Provenance of one official source resource.
final class CrimeReferenceSource {
  const CrimeReferenceSource({
    required this.sourceKey,
    required this.datasetId,
    required this.resourceId,
    required this.name,
    required this.sourceUrl,
    required this.resourceUrl,
    required this.license,
    required this.retrievedAt,
    required this.dataUpdatedAt,
    required this.recordCount,
  });

  final String sourceKey;
  final String datasetId;
  final String? resourceId;
  final String name;
  final Uri sourceUrl;
  final Uri resourceUrl;
  final String license;
  final String retrievedAt;

  /// Null when the publisher did not state an update time.
  final String? dataUpdatedAt;
  final int recordCount;
}

final class CrimeReferenceRecord {
  const CrimeReferenceRecord({
    required this.source,
    required this.sourceRecordId,
    required this.eventDate,
    required this.city,
    required this.district,
    required this.category,
    required this.locationText,
    required this.latitude,
    required this.longitude,
    required this.spatialPrecision,
    required this.confidence,
    required this.coordinateStatus,
  });

  final CrimeReferenceSource source;

  /// Source row identity, not an official case number.
  final String sourceRecordId;
  final String eventDate;
  final String city;
  final String? district;
  final String category;

  /// Official location text, unchanged.
  final String locationText;

  /// Reference coordinate (WGS84) or null. Never a precise incident point.
  final double? latitude;
  final double? longitude;
  final CrimeSpatialPrecision spatialPrecision;
  final CrimeMatchConfidence confidence;
  final CrimeCoordinateStatus coordinateStatus;

  bool get hasReferenceCoordinate => latitude != null;
}

/// One successful page. An empty [records] list is a real "no match" answer.
final class CrimeReferenceResult {
  const CrimeReferenceResult({
    required this.snapshot,
    required this.sources,
    required this.totalMatching,
    required this.records,
    required this.retrievedAt,
  });

  final CrimeReferenceSnapshot snapshot;
  final List<CrimeReferenceSource> sources;

  /// All records matching the filters, across pages.
  final int totalMatching;
  final List<CrimeReferenceRecord> records;

  /// When this App received the answer (UTC ISO-8601).
  final String retrievedAt;

  List<String> get limitations => crimeReferenceLimitations;
}
