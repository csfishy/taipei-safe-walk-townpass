import 'package:town_pass/features/safe_walk/shared/models/crime_warning.dart';

/// Offline mappings require exact identity AND original wording. A changed row
/// never inherits an older geometry based only on row number or a guessed name.
final class VerifiedCrimeGeographicMatch {
  VerifiedCrimeGeographicMatch({
    required this.sourceId,
    required this.locationText,
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
  }) : limitations = List.unmodifiable(limitations);
  final String sourceId;
  final String locationText;
  final CrimeWarningGeometry geometry;
  final CrimeSpatialPrecision spatialPrecision;
  final CrimeLocationConfidence confidence;
  final Uri geoSourceUrl;
  final String geoSourceLicense;
  final DateTime geoRetrievedAt;
  final DateTime verifiedAt;
  final DateTime validUntil;
  final double? accuracyMeters;
  final String matchEvidence;
  final List<String> limitations;

  CrimeWarningZone? resolve(CrimeLocationRecord record) =>
      record.sourceId != sourceId || record.locationText != locationText
      ? null
      : CrimeWarningZone(
          record: record,
          geometry: geometry,
          spatialPrecision: spatialPrecision,
          confidence: confidence,
          geoSourceUrl: geoSourceUrl,
          geoSourceLicense: geoSourceLicense,
          geoRetrievedAt: geoRetrievedAt,
          verifiedAt: verifiedAt,
          validUntil: validUntil,
          accuracyMeters: accuracyMeters,
          matchEvidence: matchEvidence,
          limitations: limitations,
        );
}

final class VerifiedCrimeGeographicResolver {
  VerifiedCrimeGeographicResolver(
    Iterable<VerifiedCrimeGeographicMatch> matches,
  ) : _matches = List.unmodifiable(matches) {
    if (_matches.map((match) => match.sourceId).toSet().length !=
        _matches.length) {
      throw ArgumentError('Duplicate offline geographic match');
    }
  }
  factory VerifiedCrimeGeographicResolver.fromGeoJsonManifest(
    Map<String, Object?> manifest,
  ) {
    final matches = manifest['matches'];
    if (manifest['version'] != 'crime-warning-geography/1' ||
        matches is! List) {
      throw const FormatException('Unknown warning geography manifest');
    }
    return VerifiedCrimeGeographicResolver([
      for (final value in matches) _match(value),
    ]);
  }
  final List<VerifiedCrimeGeographicMatch> _matches;
  CrimeWarningZone? call(CrimeLocationRecord record) {
    for (final match in _matches) {
      final zone = match.resolve(record);
      if (zone != null) return zone;
    }
    return null;
  }
}

VerifiedCrimeGeographicMatch _match(Object? value) {
  if (value is! Map) throw const FormatException('Expected geographic match');
  String text(String key) {
    final item = value[key];
    if (item is! String || item.trim().isEmpty) {
      throw FormatException('Missing geographic $key');
    }
    return item;
  }

  DateTime date(String key) {
    final item = text(key);
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(item)) {
      throw FormatException('Geographic $key requires an explicit offset');
    }
    final calendar = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(item);
    if (calendar == null) {
      throw FormatException('Geographic $key is not an ISO timestamp');
    }
    final values = [for (var i = 1; i <= 6; i++) int.parse(calendar[i]!)];
    final validated = DateTime.utc(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
      values[5],
    );
    if (validated.year != values[0] ||
        validated.month != values[1] ||
        validated.day != values[2] ||
        validated.hour != values[3] ||
        validated.minute != values[4] ||
        validated.second != values[5]) {
      throw FormatException('Geographic $key is not a valid calendar time');
    }
    return DateTime.parse(item);
  }

  final geometry = value['geometry'];
  final accuracy = value['accuracyMeters'];
  final limitations = value['limitations'];
  if (geometry is! Map ||
      !value.containsKey('accuracyMeters') ||
      (accuracy != null && accuracy is! num) ||
      limitations is! List ||
      limitations.any((item) => item is! String)) {
    throw const FormatException(
      'Missing geographic geometry, accuracy or limitations',
    );
  }
  return VerifiedCrimeGeographicMatch(
    sourceId: text('sourceId'),
    locationText: text('locationText'),
    geometry: CrimeWarningGeometry.fromGeoJson(
      geometry.cast<String, Object?>(),
    ),
    spatialPrecision: CrimeSpatialPrecision.values.byName(
      text('spatialPrecision'),
    ),
    confidence: CrimeLocationConfidence.values.byName(text('confidence')),
    geoSourceUrl: Uri.parse(text('geoSourceUrl')),
    geoSourceLicense: text('geoSourceLicense'),
    geoRetrievedAt: date('geoRetrievedAt'),
    verifiedAt: date('verifiedAt'),
    validUntil: date('validUntil'),
    accuracyMeters: accuracy == null ? null : (accuracy as num).toDouble(),
    matchEvidence: text('matchEvidence'),
    limitations: limitations.cast<String>(),
  );
}
