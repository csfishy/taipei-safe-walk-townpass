import 'dart:convert';

import 'package:town_pass/features/safe_walk/safety_data/violent_crime/violent_crime_normalizer.dart'
    show parseCsv;
import 'package:town_pass/features/safe_walk/shared/models/crime_warning.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final class CrimeWarningDataset {
  const CrimeWarningDataset({
    required this.id,
    required this.resourceId,
    required this.category,
    required this.title,
    required this.encoding,
  });
  final String id;
  final String resourceId;
  final CrimeWarningCategory category;
  final String title;
  final String encoding;
  Uri get sourceUrl => Uri.https('data.taipei', '/dataset/detail', {'id': id});
  Uri get metadataUrl => Uri.https(
    'data.taipei',
    '/api/frontstage/tpeod/dataset.view',
    {'id': id},
  );
  Uri get csvUrl => Uri.https(
    'data.taipei',
    '/api/frontstage/tpeod/dataset/resource.download',
    {'rid': resourceId},
  );
  static const womenChildren = CrimeWarningDataset(
    id: '985743f7-a33e-4ac1-ad2e-7ef5ffea02e2',
    resourceId: 'f87ecf10-7379-49de-8945-cb50017ec838',
    category: CrimeWarningCategory.womenChildrenWarning,
    title: '臺北市婦幼安全警示地點',
    encoding: 'UTF-8',
  );
  static const snatching = CrimeWarningDataset(
    id: '404ca667-bcc4-4f3b-9217-fdcc1da400b2',
    resourceId: '6ecb4c41-fbc9-4b04-b182-a7da6c780f8d',
    category: CrimeWarningCategory.streetSnatching,
    title: '臺北市街頭隨機搶奪案件點位資訊',
    encoding: 'Big5',
  );
  static const robbery = CrimeWarningDataset(
    id: 'ea2819ff-c869-480e-b7a9-2e5f7906a696',
    resourceId: '37b75aab-e504-413a-911d-987651aacbfb',
    category: CrimeWarningCategory.streetRobbery,
    title: '臺北市街頭隨機強盜案件點位資訊',
    encoding: 'Big5',
  );
}

final class CrimeWarningFormatException implements Exception {
  const CrimeWarningFormatException(this.message);
  final String message;
  @override
  String toString() => 'Crime warning format: $message';
}

final class CrimeWarningSourceInfo {
  const CrimeWarningSourceInfo({
    required this.dataset,
    required this.retrievedAt,
    required this.publishedAt,
    required this.dataUpdatedAt,
    required this.license,
    required this.observedPeriod,
    required this.declaredRows,
    this.resourceName,
    this.fileName,
    this.metadataUpdatedAt,
  });
  final CrimeWarningDataset dataset;
  final DateTime retrievedAt;
  final DateTime? publishedAt;
  final DateTime? dataUpdatedAt;
  final String? license;
  final String? observedPeriod;
  final int? declaredRows;
  final String? resourceName;
  final String? fileName;
  final DateTime? metadataUpdatedAt;

  factory CrimeWarningSourceInfo.fromMetadata(
    String body, {
    required CrimeWarningDataset dataset,
    required DateTime retrievedAt,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const CrimeWarningFormatException('metadata is not JSON');
    }
    if (decoded is! Map ||
        decoded['success'] != true ||
        decoded['payload'] is! Map) {
      throw const CrimeWarningFormatException('metadata unavailable');
    }
    final payload = decoded['payload'] as Map;
    if (payload['pid'] != dataset.id || payload['resources'] is! List) {
      throw const CrimeWarningFormatException('metadata dataset mismatch');
    }
    Map? resource;
    for (final value in payload['resources'] as List) {
      if (value is Map && value['rid'] == dataset.resourceId) resource = value;
    }
    if (resource == null) {
      throw const CrimeWarningFormatException('resource missing');
    }
    final license = payload['license_name'];
    final start = _text(payload['coverage_temporal_start']);
    final end = _text(payload['coverage_temporal_end']);
    final count = payload['number_of_data'];
    return CrimeWarningSourceInfo(
      dataset: dataset,
      retrievedAt: retrievedAt,
      publishedAt: parseTaipeiSourceTime(_text(payload['publish_date'])),
      dataUpdatedAt: parseTaipeiSourceTime(_text(resource['last_modified'])),
      license: license is String && license.contains('政府資料開放授權條款')
          ? license
          : null,
      observedPeriod: start != null || end != null
          ? '${start ?? '未知'} 至 ${end ?? '未知'}'
          : null,
      declaredRows: count is int && count >= 0 ? count : null,
      resourceName: _text(resource['name']),
      fileName: _text(resource['file_name']),
      metadataUpdatedAt: parseTaipeiSourceTime(
        _text(payload['metadata_changed']),
      ),
    );
  }
}

final class CrimeWarningRejectedRow {
  const CrimeWarningRejectedRow(this.line, this.reason);
  final int line;
  final String reason;
}

final class CrimeWarningParsed {
  CrimeWarningParsed({
    required List<CrimeLocationRecord> records,
    required List<CrimeWarningRejectedRow> rejected,
    required this.sourceRows,
  }) : records = List.unmodifiable(records),
       rejected = List.unmodifiable(rejected);
  final List<CrimeLocationRecord> records;
  final List<CrimeWarningRejectedRow> rejected;
  final int sourceRows;
}

CrimeWarningParsed parseCrimeWarningCsv(
  String csv, {
  required CrimeWarningSourceInfo source,
  sw.DataMode mode = sw.DataMode.live,
}) {
  if (csv.length > 2000000) {
    throw const CrimeWarningFormatException('CSV exceeds limit');
  }
  final List<List<String>> rows;
  try {
    rows = parseCsv(csv);
  } on Exception {
    throw const CrimeWarningFormatException('CSV malformed');
  }
  final women =
      source.dataset.category == CrimeWarningCategory.womenChildrenWarning;
  final required = women
      ? const ['編號', '縣市別代碼', '地點位置', '管轄分局', '郵遞區號', '備註']
      : const ['編號', '案類', '發生日期', '發生時段', '發生地點', '備註'];
  final header = rows.isEmpty
      ? <String>[]
      : rows.first.map((value) => value.trim()).toList();
  if (header.toSet().length != header.length ||
      !required.every(header.contains)) {
    throw const CrimeWarningFormatException(
      'official columns missing, duplicate or incorrectly decoded',
    );
  }
  final records = <CrimeLocationRecord>[];
  final rejected = <CrimeWarningRejectedRow>[];
  final seen = <String>{};
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length != header.length) {
      rejected.add(CrimeWarningRejectedRow(i + 1, 'column count mismatch'));
      continue;
    }
    final fields = <String, String>{
      for (var j = 0; j < header.length; j++) header[j]: row[j].trim(),
    };
    final id = fields['編號']!;
    final location = fields[women ? '地點位置' : '發生地點']!;
    if (!RegExp(r'^\d+$').hasMatch(id) ||
        location.isEmpty ||
        !seen.add(id) ||
        (women && fields['縣市別代碼'] != '63000')) {
      rejected.add(
        CrimeWarningRejectedRow(
          i + 1,
          'invalid identity, location, city or duplicate',
        ),
      );
      continue;
    }
    if (!women && !_validRocDate(fields['發生日期']!)) {
      rejected.add(CrimeWarningRejectedRow(i + 1, 'invalid occurrence date'));
      continue;
    }
    final categoryText = fields['案類'];
    if (!women &&
        categoryText !=
            (source.dataset.category == CrimeWarningCategory.streetSnatching
                ? '搶奪'
                : '強盜')) {
      rejected.add(CrimeWarningRejectedRow(i + 1, 'crime category mismatch'));
      continue;
    }
    records.add(
      CrimeLocationRecord(
        sourceId: '${source.dataset.id}:$id',
        datasetId: source.dataset.id,
        resourceId: source.dataset.resourceId,
        category: source.dataset.category,
        locationText: location,
        observedPeriod: women
            ? source.observedPeriod
            : '民國${fields['發生日期']} ${fields['發生時段']}',
        publishedAt: source.publishedAt,
        dataUpdatedAt: source.dataUpdatedAt,
        retrievedAt: source.retrievedAt,
        sourceUrl: source.dataset.sourceUrl,
        license: source.license,
        sourceResourceName: source.resourceName,
        sourceFileName: source.fileName,
        metadataUpdatedAt: source.metadataUpdatedAt,
        mode: mode,
        sourceFields: fields,
        sourceLimitations: women
            ? const [
                '官方婦幼安全提醒，並非即時犯罪通報或安全保證。',
                'CSV 只有文字位置，沒有座標；未核對幾何者僅供文字參考。',
                '資料描述提及近三年事件，但未提供逐列發生日期或精確適用起訖。',
              ]
            : const [
                '歷史案件地址已由來源模糊化，不得還原成精確犯罪發生點。',
                '不以歷史案件直接封鎖道路或計算即時人身安全分數。',
                '來源時間／資源名稱／描述可能不同步，逐列原日期保留。',
              ],
      ),
    );
  }
  return CrimeWarningParsed(
    records: records,
    rejected: rejected,
    sourceRows: rows.length - 1,
  );
}

DateTime? parseTaipeiSourceTime(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?$',
  ).firstMatch(value);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i] ?? '0')];
  final local = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (local.year != parts[0] ||
      local.month != parts[1] ||
      local.day != parts[2] ||
      local.hour != parts[3] ||
      local.minute != parts[4] ||
      local.second != parts[5]) {
    return null;
  }
  return local.subtract(const Duration(hours: 8));
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
bool _validRocDate(String value) {
  if (!RegExp(r'^\d{7}$').hasMatch(value)) return false;
  final year = int.parse(value.substring(0, 3)) + 1911;
  final month = int.parse(value.substring(3, 5));
  final day = int.parse(value.substring(5, 7));
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}
