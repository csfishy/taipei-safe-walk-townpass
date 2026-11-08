import 'dart:convert';

import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/opening_hours.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Convenience stores and police stations around Taipei from a bundled
/// OpenStreetMap snapshot (`assets/safe_walk/osm_help_points_taipei.json`).
///
/// The public Overpass servers took 20–40 s or timed out, too slow to ask
/// while walking, so the lookup reads this snapshot and sends nothing. Opening
/// hours are evaluated at lookup time from the `opening_hours` tag: open now
/// and for [stayOpenMargin] → open; readable but not open → closed; missing
/// or unreadable → unknown.
final class OsmHelpPointSnapshot {
  OsmHelpPointSnapshot._(this._rows, this.retrievedAt, this.license);

  /// Parses the asset JSON written by the snapshot script.
  factory OsmHelpPointSnapshot.parse(String json) {
    final data = jsonDecode(json) as Map<String, Object?>;
    final rows = <_Row>[];
    for (final r in data['rows'] as List) {
      if (r is! List || r.length < 6) continue;
      final lat = r[2], lng = r[3];
      if (lat is! num || lng is! num) continue;
      if (!isValidLatLng(lat.toDouble(), lng.toDouble())) continue;
      rows.add(
        _Row(
          police: r[0] == 'p',
          osmId: '${r[1]}',
          at: sw.Coordinates(lat: lat.toDouble(), lng: lng.toDouble()),
          name: r[4] is String ? (r[4] as String).trim() : '',
          hours: r[5] is String ? r[5] as String : null,
        ),
      );
    }
    return OsmHelpPointSnapshot._(
      rows,
      data['retrievedAt'] as String,
      data['license'] as String,
    );
  }

  static const Duration stayOpenMargin = Duration(minutes: 30);

  final List<_Row> _rows;

  /// When the snapshot was taken from OpenStreetMap (ISO-8601).
  final String retrievedAt;
  final String license;

  int get length => _rows.length;

  /// Points within [radiusMeters] of [origin], with opening status at [now].
  List<sw.AssistancePoint> near(
    sw.Coordinates origin, {
    double radiusMeters = 2000,
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).toUtc();
    final checkedAt = at.toIso8601String();
    return [
      for (final r in _rows)
        if (distanceMeters(origin, r.at) <= radiusMeters)
          _point(r, at, checkedAt),
    ];
  }

  sw.AssistancePoint _point(_Row r, DateTime at, String checkedAt) {
    final open = r.hours == null
        ? null
        : openingHoursOpenFor(r.hours!, taipeiTimeOf(at), stayOpenMargin);
    final status = switch (open) {
      true => sw.OpeningStatus.open,
      false => sw.OpeningStatus.closed,
      null => sw.OpeningStatus.unknown,
    };
    final fallback = r.police ? '派出所（無名稱）' : '便利商店（無名稱）';
    final name = r.name.isEmpty ? fallback : r.name;
    return sw.AssistancePoint(
      id: 'osm-${r.osmId.replaceAll('/', '-')}',
      name: name.length > 100 ? name.substring(0, 100) : name,
      kind: r.police
          ? sw.AssistancePointKind.police
          : sw.AssistancePointKind.convenienceStore,
      coordinates: r.at,
      address: null,
      publicPhone: null,
      recognition: sw.UnconfirmedRecognition(
        status: sw.UnconfirmedRecognitionStatus.unconfirmed,
        checkedAt: null,
      ),
      availability: status,
      availabilityCheckedAt: status == sw.OpeningStatus.unknown
          ? null
          : checkedAt,
      capabilities: const [sw.AssistanceCapability.unknown],
      source: sw.SourceMetadata(
        datasetId: 'osm-help-points-taipei-snapshot',
        title: 'OpenStreetMap 便利商店與派出所（快照，社群資料）',
        dataMode: sw.DataMode.live,
        sourceUrl: 'https://www.openstreetmap.org/${r.osmId}',
        retrievedAt: retrievedAt,
        dataUpdatedAt: null,
        license: license,
        coverage: '臺北市及周邊 OSM 標示 shop=convenience 或 amenity=police 的地點',
        limitations: const [
          '社群編輯資料的快照，非官方清單，也不是警方認可的求助據點',
          '營業時間依 opening_hours 標籤在查詢當下判斷，未經店家確認',
          '沒有標示或無法判讀營業時間的地點標為「營業時間不確定」',
        ],
      ),
    );
  }
}

final class _Row {
  const _Row({
    required this.police,
    required this.osmId,
    required this.at,
    required this.name,
    required this.hours,
  });
  final bool police;
  final String osmId;
  final sw.Coordinates at;
  final String name;
  final String? hours;
}
