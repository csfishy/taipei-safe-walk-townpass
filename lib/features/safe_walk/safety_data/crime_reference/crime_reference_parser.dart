import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';

/// The RPC answer did not match interface version 1. The message names the
/// field only; it never contains record contents.
final class CrimeReferenceFormatException implements Exception {
  const CrimeReferenceFormatException(this.message);

  final String message;

  @override
  String toString() => 'Crime reference response invalid: $message';
}

const crimeReferenceInterfaceVersion = 1;

/// Strictly parses one RPC answer. Any inconsistency rejects the whole page:
/// a partially trusted page could show an invented or mis-sourced location.
CrimeReferenceResult parseCrimeReferenceResponse(
  Object? json, {
  required CrimeReferenceQuery query,
  required String retrievedAt,
}) {
  final root = _map(json, 'response');
  if (root['interfaceVersion'] != crimeReferenceInterfaceVersion) {
    throw const CrimeReferenceFormatException('interfaceVersion');
  }
  final snapshotJson = _map(root['snapshot'], 'snapshot');
  final snapshot = CrimeReferenceSnapshot(
    snapshotId: _string(snapshotJson, 'snapshotId'),
    label: _string(snapshotJson, 'label'),
    asOfDate: _date(snapshotJson, 'asOfDate'),
    importedAt: _string(snapshotJson, 'importedAt'),
    recordCount: _count(snapshotJson, 'recordCount'),
  );

  final sources = <String, CrimeReferenceSource>{};
  for (final item in _list(root['sources'], 'sources')) {
    final s = _map(item, 'source');
    final source = CrimeReferenceSource(
      sourceKey: _string(s, 'sourceKey'),
      datasetId: _string(s, 'datasetId'),
      resourceId: _optionalString(s, 'resourceId'),
      name: _string(s, 'name'),
      sourceUrl: _https(s, 'sourceUrl'),
      resourceUrl: _https(s, 'resourceUrl'),
      license: _string(s, 'license'),
      retrievedAt: _string(s, 'retrievedAt'),
      dataUpdatedAt: _optionalString(s, 'dataUpdatedAt'),
      recordCount: _count(s, 'recordCount'),
    );
    if (sources.containsKey(source.sourceKey)) {
      throw const CrimeReferenceFormatException('duplicate sourceKey');
    }
    sources[source.sourceKey] = source;
  }
  if (sources.isEmpty) {
    throw const CrimeReferenceFormatException('sources empty');
  }

  final total = _count(root, 'totalMatching');
  if (total > snapshot.recordCount) {
    throw const CrimeReferenceFormatException('totalMatching');
  }
  final rawRecords = _list(root['records'], 'records');
  if (rawRecords.length > query.limit ||
      rawRecords.length > total - query.offset.clamp(0, total)) {
    throw const CrimeReferenceFormatException('records length');
  }
  final records = [
    for (final item in rawRecords)
      _record(_map(item, 'record'), sources, snapshot, query),
  ];

  return CrimeReferenceResult(
    snapshot: snapshot,
    sources: List.unmodifiable(sources.values),
    totalMatching: total,
    records: List.unmodifiable(records),
    retrievedAt: retrievedAt,
  );
}

CrimeReferenceRecord _record(
  Map<String, Object?> r,
  Map<String, CrimeReferenceSource> sources,
  CrimeReferenceSnapshot snapshot,
  CrimeReferenceQuery query,
) {
  final source = sources[_string(r, 'sourceKey')];
  if (source == null) {
    throw const CrimeReferenceFormatException('record sourceKey');
  }
  final eventDate = _date(r, 'eventDate');
  if (eventDate.compareTo(snapshot.asOfDate) > 0) {
    throw const CrimeReferenceFormatException('eventDate after asOfDate');
  }
  final city = _string(r, 'city');
  if (!crimeReferenceCities.contains(city)) {
    throw const CrimeReferenceFormatException('city');
  }
  final precision = CrimeSpatialPrecision.fromWire(r['spatialPrecision']);
  final confidence = CrimeMatchConfidence.fromWire(r['confidence']);
  final status = CrimeCoordinateStatus.fromWire(r['coordinateStatus']);
  if (precision == null) {
    throw const CrimeReferenceFormatException('spatialPrecision');
  }
  if (confidence == null) {
    throw const CrimeReferenceFormatException('confidence');
  }
  if (status == null) {
    throw const CrimeReferenceFormatException('coordinateStatus');
  }
  final lat = _optionalDouble(r, 'latitude');
  final lng = _optionalDouble(r, 'longitude');
  if ((lat == null) != (lng == null)) {
    throw const CrimeReferenceFormatException('unpaired coordinate');
  }
  if (lat != null && (lat < -90 || lat > 90 || lng! < -180 || lng > 180)) {
    throw const CrimeReferenceFormatException('coordinate range');
  }
  // The same invariants the database enforces; checked again so a changed
  // server can never make the App show an invented precise point.
  final hasPoint = lat != null;
  if (hasPoint && !precision.allowsCoordinates) {
    throw const CrimeReferenceFormatException('coarse precision coordinate');
  }
  if (hasPoint == (status == CrimeCoordinateStatus.notProvided)) {
    throw const CrimeReferenceFormatException('coordinateStatus mismatch');
  }
  if (hasPoint &&
      confidence == CrimeMatchConfidence.unknown &&
      status != CrimeCoordinateStatus.sourceProvided) {
    throw const CrimeReferenceFormatException('unknown confidence coordinate');
  }
  // The answer must respect the filters that were asked for.
  if ((query.city != null && city != query.city) ||
      (query.from != null && eventDate.compareTo(query.from!) < 0) ||
      (query.to != null && eventDate.compareTo(query.to!) > 0)) {
    throw const CrimeReferenceFormatException('record outside query');
  }
  final category = _string(r, 'category');
  if (query.category != null && category != query.category) {
    throw const CrimeReferenceFormatException('record outside query');
  }
  final b = query.bounds;
  if (b != null &&
      (lat == null ||
          lat < b.minLat ||
          lat > b.maxLat ||
          lng! < b.minLng ||
          lng > b.maxLng)) {
    throw const CrimeReferenceFormatException('record outside bounds');
  }
  return CrimeReferenceRecord(
    source: source,
    sourceRecordId: _string(r, 'sourceRecordId'),
    eventDate: eventDate,
    city: city,
    district: _optionalString(r, 'district'),
    category: category,
    locationText: _string(r, 'locationText'),
    latitude: lat,
    longitude: lng,
    spatialPrecision: precision,
    confidence: confidence,
    coordinateStatus: status,
  );
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is! Map) throw CrimeReferenceFormatException(name);
  return {
    for (final e in value.entries)
      if (e.key is String) e.key as String: e.value,
  };
}

List<Object?> _list(Object? value, String name) {
  if (value is! List) throw CrimeReferenceFormatException(name);
  return value;
}

String _string(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! String || v.trim().isEmpty) {
    throw CrimeReferenceFormatException(key);
  }
  return v;
}

String? _optionalString(Map<String, Object?> m, String key) {
  if (!m.containsKey(key)) throw CrimeReferenceFormatException(key);
  final v = m[key];
  if (v == null) return null;
  if (v is! String) throw CrimeReferenceFormatException(key);
  return v.trim().isEmpty ? null : v;
}

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _date(Map<String, Object?> m, String key) {
  final v = _string(m, key);
  if (!_datePattern.hasMatch(v) || DateTime.tryParse(v) == null) {
    throw CrimeReferenceFormatException(key);
  }
  return v;
}

int _count(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! int || v < 0) throw CrimeReferenceFormatException(key);
  return v;
}

double? _optionalDouble(Map<String, Object?> m, String key) {
  if (!m.containsKey(key)) throw CrimeReferenceFormatException(key);
  final v = m[key];
  if (v == null) return null;
  if (v is! num || !v.isFinite) throw CrimeReferenceFormatException(key);
  return v.toDouble();
}

Uri _https(Map<String, Object?> m, String key) {
  final uri = Uri.tryParse(_string(m, key));
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw CrimeReferenceFormatException(key);
  }
  return uri;
}
