// Pure mapping from data.taipei AED rows to normalized AssistancePoint JSON.
//
// No network, clock or storage. The output still goes through the shared
// `ContractSafetyDataParser`; this file never builds a second model.
// The same rules are implemented by `tool/aed_transform.py`, and the tests
// compare both outputs on the same real sample.

/// data.taipei dataset 臺北市AED自動體外心臟去顫器設置地點（臺北市政府衛生局）.
const aedDatasetId = 'cd050577-115f-4299-b37a-012ff490a632';
const aedResourceId = '438c61ad-24f6-4e54-a1cc-e2cfe0e7051e';
const aedDatasetPageUrl =
    'https://data.taipei/dataset/detail?id=$aedDatasetId';

/// 內政部行政區代碼，已用各區公所／運動中心地址逐區核對 data.taipei 的 區域代碼.
const aedDistricts = <String, String>{
  '63000010': '松山區',
  '63000020': '信義區',
  '63000030': '大安區',
  '63000040': '中山區',
  '63000050': '中正區',
  '63000060': '大同區',
  '63000070': '萬華區',
  '63000080': '文山區',
  '63000090': '南港區',
  '63000100': '內湖區',
  '63000110': '士林區',
  '63000120': '北投區',
};

/// Rough Taipei City bounds; rows outside are rejected, never corrected.
const _minLat = 24.95, _maxLat = 25.22, _minLng = 121.45, _maxLng = 121.67;

const aedLimitations = <String>[
  '只表示衛生局登錄的AED設置地點，不代表AED此刻可取用、場所開放或有人可提供協助。',
  '來源未提供開放時間；許多AED位於建築物內，需依場所開放時間進入。',
  '座標為來源提供，未經實地核對；同一場所可能有多台AED，各自為一筆。',
  'AED設置地點不是警察或官方合作求助據點，不構成安全保證。',
];

/// Retrieval facts supplied by the caller (repository or test).
final class AedSourceInfo {
  const AedSourceInfo({
    required this.retrievedAt,
    required this.resourceLastModified,
    required this.licenseName,
  });

  /// Already formatted with an offset, e.g. `2026-11-07T14:44:57+08:00`.
  final String retrievedAt;

  /// data.taipei value in Asia/Taipei local time, e.g. `2026-09-04 18:15:48`.
  final String? resourceLastModified;

  /// data.taipei value, e.g. `依政府資料開放授權條款-第1版`.
  final String? licenseName;
}

/// A source row that was dropped. Holds the platform row number only, never
/// the row contents.
final class AedRejectedRow {
  const AedRejectedRow(this.rowId, this.reason);

  final int rowId;
  final String reason;

  @override
  String toString() => 'row $rowId: $reason';
}

final class AedNormalized {
  const AedNormalized(this.points, this.rejected);

  /// Normalized AssistancePoint JSON objects, not yet parsed.
  final List<Map<String, Object?>> points;
  final List<AedRejectedRow> rejected;
}

/// Formats any instant as Taipei local time with an explicit `+08:00`.
String formatTaipeiTime(DateTime instant) {
  final t = instant.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}+08:00';
}

/// `2026-09-04 18:15:48` → `2026-09-04T18:15:48+08:00`; anything else → null.
String? platformTimeToIso(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})$',
  ).firstMatch(value.trim());
  return match == null ? null : '${match[1]}T${match[2]}+08:00';
}

/// Only the government open-data licence wording is accepted; else null.
String? normalizeLicense(String? name) {
  final cleaned = _clean(name);
  if (!cleaned.contains('政府資料開放授權條款')) return null;
  return cleaned.startsWith('依') ? cleaned.substring(1) : cleaned;
}

String? makeAddress(String raw, String? district) {
  var address = _clean(raw);
  if (address.isEmpty) return null;
  address = address.replaceFirst(RegExp(r'^台北市'), '臺北市');
  final String full;
  if (address.startsWith('臺北市')) {
    full = address;
  } else if (district != null && address.startsWith(district)) {
    full = '臺北市$address';
  } else {
    full = '臺北市${district ?? ''}$address';
  }
  return _truncate(full, 400);
}

String makeName(String site, String placement) {
  final s = _clean(site), p = _clean(placement);
  final name = p.isNotEmpty && p != s ? '$s（AED：$p）' : s;
  return _truncate(name, 200);
}

Map<String, Object?> buildAedSource(AedSourceInfo info) => {
  'datasetId': 'data.taipei:$aedDatasetId/$aedResourceId',
  'title': '臺北市AED自動體外心臟去顫器設置地點（臺北市政府衛生局）',
  'dataMode': 'live',
  'sourceUrl': aedDatasetPageUrl,
  'retrievedAt': info.retrievedAt,
  'dataUpdatedAt': platformTimeToIso(info.resourceLastModified),
  'license': normalizeLicense(info.licenseName),
  'coverage': '臺北市12行政區；臺北市政府衛生局登錄之AED設置場所',
  'limitations': List<String>.of(aedLimitations),
};

/// Converts raw rows. Rows with a missing name or unusable coordinates are
/// rejected with a reason; nothing is guessed.
///
/// Ids are `tpe-aed-<區域代碼>-<緯度>-<經度>-<n>`, using the source strings,
/// where n orders the AEDs sharing one coordinate by their content. They do
/// not depend on the platform `_id`, which changes when the city re-imports.
AedNormalized normalizeAedRows(
  Iterable<Map<String, Object?>> rows,
  AedSourceInfo info,
) {
  final source = buildAedSource(info);
  final rejected = <AedRejectedRow>[];
  final accepted = <_Row>[];
  for (final row in rows) {
    final rowId = _rowId(row);
    final site = _clean(row['場所名稱']);
    if (site.isEmpty) {
      rejected.add(AedRejectedRow(rowId, 'missing 場所名稱'));
      continue;
    }
    final lat = _clean(row['緯度']), lng = _clean(row['經度']);
    final latValue = double.tryParse(lat), lngValue = double.tryParse(lng);
    if (latValue == null ||
        lngValue == null ||
        !(latValue >= _minLat && latValue <= _maxLat) ||
        !(lngValue >= _minLng && lngValue <= _maxLng)) {
      rejected.add(
        AedRejectedRow(rowId, 'unparsable or out-of-Taipei coordinates'),
      );
      continue;
    }
    accepted.add(_Row(rowId, row, site, lat, lng, latValue, lngValue));
  }

  accepted.sort(_Row.compare);
  final ordinals = <String, int>{};
  final points = <Map<String, Object?>>[];
  for (final r in accepted) {
    final code = _clean(r.row['區域代碼']);
    final base = 'tpe-aed-${code.isEmpty ? 'unknown' : code}-${r.lat}-${r.lng}';
    final n = ordinals[base] = (ordinals[base] ?? 0) + 1;
    final district = aedDistricts[code];
    points.add({
      'schemaVersion': '1.0.0',
      'id': _truncate('$base-$n', 120),
      'name': makeName(r.site, _clean(r.row['aed放置地點'])),
      'kind': 'public_facility',
      'coordinates': {'lat': r.latValue, 'lng': r.lngValue},
      'address': makeAddress(_clean(r.row['場所地址']), district),
      'publicPhone': null,
      'recognition': {
        'status': 'not_applicable',
        'evidenceUrl': null,
        'checkedAt': null,
      },
      'availability': 'unknown',
      'availabilityCheckedAt': null,
      'capabilities': ['unknown'],
      'source': source,
    });
  }
  rejected.sort((a, b) => a.rowId.compareTo(b.rowId));
  return AedNormalized(points, rejected);
}

final class _Row {
  _Row(
    this.rowId,
    this.row,
    this.site,
    this.lat,
    this.lng,
    this.latValue,
    this.lngValue,
  );

  final int rowId;
  final Map<String, Object?> row;
  final String site, lat, lng;
  final double latValue, lngValue;

  List<String> get _key => [
    _clean(row['區域代碼']),
    lat,
    lng,
    site,
    _clean(row['場所地址']),
    _clean(row['aed放置地點']),
    _clean(row['aed地點描述']),
  ];

  static int compare(_Row a, _Row b) {
    final ka = a._key, kb = b._key;
    for (var i = 0; i < ka.length; i++) {
      final c = ka[i].compareTo(kb[i]);
      if (c != 0) return c;
    }
    return a.rowId.compareTo(b.rowId);
  }
}

int _rowId(Map<String, Object?> row) {
  final value = row['_id'];
  if (value is int) return value;
  return int.tryParse(_clean(value)) ?? 0;
}

String _clean(Object? value) =>
    (value ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();

String _truncate(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);
