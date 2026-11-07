// Pure mapping from 主計處「臺北市暴力犯罪案件按月別」CSV to city-wide monthly
// statistics. No network, clock or storage.
//
// The source has city-wide numbers only. The shared AreaStatistics contract
// accepts district-level history only, so these records use the module-local
// [CityMonthlyCrimeStatistics] type instead of filling a fake district.
// README.md carries the contract proposal for M1.
//
// The same rules were first implemented in the legacy React repository
// (Node); the tests require this file to reproduce its output on the same
// real sample exactly.

import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// data.taipei dataset 臺北市暴力犯罪案件按月別（臺北市政府主計處）.
const violentCrimeDatasetId = '33dc5028-78ef-4892-bec6-0b459f7cb193';
const violentCrimeResourceId = '0af7de97-943d-486c-99e8-4014eeebce6c';
const violentCrimeDatasetPageUrl =
    'https://data.taipei/dataset/detail?id=$violentCrimeDatasetId';
const violentCrimeTitle = '臺北市暴力犯罪案件按月別（臺北市政府主計處）';

/// Module-local format name. Not a shared contract payload.
const cityMonthlyCrimeFormat = 'm4.cityMonthlyCrimeStatistics/0.1';

// Exact source headers this mapping relies on. A missing header means the
// source changed: the whole read fails instead of guessing.
const _periodColumn = '統計期';
const _totalColumn = '發生件數/總計[件]';
const _sexualAssaultColumn = '發生件數/強制性交[件]';
const _robberyColumn = '發生件數/強盜搶奪[件]';
const _otherColumn = '發生件數/其他[件]';
const _rateColumn = '發生率[件/十萬人]';
const _requiredColumns = [
  _periodColumn,
  _totalColumn,
  _sexualAssaultColumn,
  _robberyColumn,
  _otherColumn,
  _rateColumn,
];

/// First header cell of the expected CSV; used to detect HTML error pages.
const violentCrimeCsvHeaderStart = '"$_periodColumn"';

const violentCrimeLimitations = <String>[
  '全市每月彙總，沒有行政區、路段、地點或時段，不能用來判斷某條路、某一區或某個時間是否安全。',
  '件數是警察機關統計的已發生並受理案件；未報案的案件不在內。件數少或為零不代表安全。',
  '「其他」由來源合併計算，本服務不拆分也不推測其組成。',
  '發生率由來源提供（件／十萬人），來源未提供人口分母，本服務不自行換算。',
  '來源為定期統計，數字可能在之後的發布中更新；以 dataUpdatedAt 為準。',
];

/// Retrieval facts supplied by the caller (repository or test).
final class ViolentCrimeSourceInfo {
  const ViolentCrimeSourceInfo({
    required this.retrievedAt,
    required this.resourceLastModified,
    required this.licenseName,
  });

  /// Already formatted with an offset, e.g. `2026-11-07T16:20:00+08:00`.
  final String retrievedAt;

  /// data.taipei value in Asia/Taipei local time, e.g. `2026-10-20 14:03:05`.
  final String? resourceLastModified;

  /// data.taipei value, e.g. `依政府資料開放授權條款-第1版`.
  final String? licenseName;
}

/// One category inside a month, exactly as the source reports it.
final class CrimeCategoryCount {
  const CrimeCategoryCount(this.category, this.caseCount);

  final String category;
  final int caseCount;

  Map<String, Object?> toJson() => {
    'category': category,
    'caseCount': caseCount,
  };
}

/// City-wide monthly violent-crime history. Not a street-level, hourly,
/// district or real-time risk score, and not an `AreaStatistics` payload.
final class CityMonthlyCrimeStatistics {
  CityMonthlyCrimeStatistics({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.caseCount,
    required List<CrimeCategoryCount> breakdown,
    required this.sourceReportedRatePer100k,
    required this.source,
  }) : breakdown = List<CrimeCategoryCount>.unmodifiable(breakdown);

  final String id;

  /// `YYYY-MM-DD`, first day of the month.
  final String periodStart;

  /// `YYYY-MM-DD`, last day of the month.
  final String periodEnd;
  final int caseCount;
  final List<CrimeCategoryCount> breakdown;

  /// The source's own 發生率[件/十萬人]. Its population denominator is not
  /// published, so it is never recomputed and never called `ratePer100k`.
  final double? sourceReportedRatePer100k;
  final sw.SourceMetadata source;

  String get city => '臺北市';
  String get geographicLevel => 'city';
  String get aggregation => 'month';
  String get category => '暴力犯罪';

  /// Always null: the source does not publish it.
  int? get populationDenominator => null;

  Map<String, Object?> toJson() => {
    'format': cityMonthlyCrimeFormat,
    'id': id,
    'city': city,
    'geographicLevel': geographicLevel,
    'periodStart': periodStart,
    'periodEnd': periodEnd,
    'aggregation': aggregation,
    'category': category,
    'caseCount': caseCount,
    'breakdown': [for (final b in breakdown) b.toJson()],
    'sourceReportedRatePer100k': sourceReportedRatePer100k,
    'populationDenominator': populationDenominator,
    'source': source.toJson(),
  };
}

/// A source row that was dropped. Holds the CSV line number only.
final class ViolentCrimeRejectedRow {
  const ViolentCrimeRejectedRow(this.line, this.reason);

  /// 1-based CSV line; the header is line 1.
  final int line;
  final String reason;

  @override
  String toString() => 'line $line: $reason';
}

final class ViolentCrimeNormalized {
  const ViolentCrimeNormalized(this.records, this.rejected);

  final List<CityMonthlyCrimeStatistics> records;
  final List<ViolentCrimeRejectedRow> rejected;
}

/// The CSV no longer has the columns this mapping relies on.
final class ViolentCrimeFormatException implements Exception {
  const ViolentCrimeFormatException(this.message);

  final String message;

  @override
  String toString() => 'Violent-crime CSV format changed: $message';
}

/// Minimal RFC 4180 parser: quoted fields, doubled quotes, CRLF/LF, BOM.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  final s = text.startsWith('﻿') ? text.substring(1) : text;

  void endRow() {
    row.add(field.toString());
    field.clear();
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quoted) {
      if (ch == '"' && i + 1 < s.length && s[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (ch == '"') {
        quoted = false;
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (quoted) {
    throw const ViolentCrimeFormatException('unterminated quoted field');
  }
  endRow();
  return rows;
}

/// `115年 8月` → (year: 2026, month: 8); anything else → null.
({int year, int month})? parseRocMonth(String value) {
  final match = RegExp(r'^(\d{2,3})年\s*(\d{1,2})月$').firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match[1]!) + 1911;
  final month = int.parse(match[2]!);
  return month >= 1 && month <= 12 ? (year: year, month: month) : null;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// First and last day of a month as `YYYY-MM-DD` (handles leap February).
({String periodStart, String periodEnd}) monthBounds(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final prefix = '${year.toString().padLeft(4, '0')}-${_two(month)}';
  return (periodStart: '$prefix-01', periodEnd: '$prefix-${_two(lastDay)}');
}

/// Formats any instant as Taipei local time with an explicit `+08:00`.
String formatTaipeiTime(DateTime instant) {
  final t = instant.toUtc().add(const Duration(hours: 8));
  return '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
      'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}+08:00';
}

/// `2026-10-20 14:03:05` → `2026-10-20T14:03:05+08:00`; anything else → null.
String? platformTimeToIso(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})$',
  ).firstMatch(value.trim());
  return match == null ? null : '${match[1]}T${match[2]}+08:00';
}

/// Only the government open-data licence wording is accepted; else null.
String? normalizeLicense(String? name) {
  final cleaned = (name ?? '').trim();
  if (!cleaned.contains('政府資料開放授權條款')) return null;
  return cleaned.startsWith('依') ? cleaned.substring(1) : cleaned;
}

/// Shared SourceMetadata, validated by the shared schema model.
sw.SourceMetadata buildViolentCrimeSource(ViolentCrimeSourceInfo info) {
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(info.retrievedAt)) {
    throw ArgumentError.value(
      info.retrievedAt,
      'retrievedAt',
      'must include a UTC offset',
    );
  }
  return sw.SourceMetadata.fromJson({
    'datasetId': 'data.taipei:$violentCrimeDatasetId/$violentCrimeResourceId',
    'title': violentCrimeTitle,
    'dataMode': 'live',
    'sourceUrl': violentCrimeDatasetPageUrl,
    'retrievedAt': info.retrievedAt,
    'dataUpdatedAt': platformTimeToIso(info.resourceLastModified),
    'license': normalizeLicense(info.licenseName),
    'coverage': '臺北市全市（不分行政區）；民國106年1月起按月彙總',
    'limitations': List<String>.of(violentCrimeLimitations),
  });
}

int? _count(String value) {
  final v = value.trim();
  return RegExp(r'^\d+$').hasMatch(v) ? int.parse(v) : null;
}

double? _rate(String value) {
  final v = value.trim();
  return RegExp(r'^\d+(\.\d+)?$').hasMatch(v) ? double.parse(v) : null;
}

/// Converts the CSV. Rows that do not parse, do not add up, or repeat a
/// period are dropped and reported, never repaired. Output is ordered by
/// period, oldest first.
///
/// Throws [ViolentCrimeFormatException] when a required column is missing.
ViolentCrimeNormalized normalizeViolentCrimeCsv(
  String csv,
  ViolentCrimeSourceInfo info,
) {
  final rows = parseCsv(csv);
  final header = rows.isEmpty ? const <String>[] : rows.first;
  final index = <String, int>{};
  for (final name in _requiredColumns) {
    final at = header.indexWhere((h) => h.trim() == name);
    if (at < 0) throw ViolentCrimeFormatException('missing column $name');
    index[name] = at;
  }
  String cell(List<String> cells, String name) {
    final at = index[name]!;
    return at < cells.length ? cells[at] : '';
  }

  final source = buildViolentCrimeSource(info);
  final records = <CityMonthlyCrimeStatistics>[];
  final rejected = <ViolentCrimeRejectedRow>[];
  final seen = <String>{};
  for (var i = 1; i < rows.length; i++) {
    final cells = rows[i];
    final line = i + 1;
    final month = parseRocMonth(cell(cells, _periodColumn));
    if (month == null) {
      rejected.add(ViolentCrimeRejectedRow(line, 'unparsable 統計期'));
      continue;
    }
    final total = _count(cell(cells, _totalColumn));
    final sexualAssault = _count(cell(cells, _sexualAssaultColumn));
    final robbery = _count(cell(cells, _robberyColumn));
    final other = _count(cell(cells, _otherColumn));
    if (total == null ||
        sexualAssault == null ||
        robbery == null ||
        other == null) {
      rejected.add(ViolentCrimeRejectedRow(line, 'non-integer case count'));
      continue;
    }
    if (total != sexualAssault + robbery + other) {
      rejected.add(
        ViolentCrimeRejectedRow(
          line,
          '總計 does not equal the sum of its categories',
        ),
      );
      continue;
    }
    final rate = _rate(cell(cells, _rateColumn));
    if (rate != null && !rate.isFinite) {
      rejected.add(
        ViolentCrimeRejectedRow(line, 'non-finite source-reported rate'),
      );
      continue;
    }
    final key = '${month.year}-${_two(month.month)}';
    if (!seen.add(key)) {
      rejected.add(ViolentCrimeRejectedRow(line, 'duplicate period'));
      continue;
    }
    final bounds = monthBounds(month.year, month.month);
    records.add(
      CityMonthlyCrimeStatistics(
        id: 'tpe-violent-crime-month-$key',
        periodStart: bounds.periodStart,
        periodEnd: bounds.periodEnd,
        caseCount: total,
        breakdown: [
          CrimeCategoryCount('強盜搶奪', robbery),
          CrimeCategoryCount('強制性交', sexualAssault),
          CrimeCategoryCount('其他', other),
        ],
        sourceReportedRatePer100k: rate,
        source: source,
      ),
    );
  }
  records.sort((a, b) => a.periodStart.compareTo(b.periodStart));
  return ViolentCrimeNormalized(
    List<CityMonthlyCrimeStatistics>.unmodifiable(records),
    List<ViolentCrimeRejectedRow>.unmodifiable(rejected),
  );
}

/// Semantic checks: the shared source rule plus this format's own rules.
List<String> cityCrimeProblems(CityMonthlyCrimeStatistics r) {
  final errors = [...sourceProblems(r.source)];
  final rate = r.sourceReportedRatePer100k;
  if (rate != null && !rate.isFinite) {
    errors.add('Source-reported rate must be finite');
  }
  if (r.periodStart.compareTo(r.periodEnd) > 0) {
    errors.add('Reversed statistics period');
  }
  final sum = r.breakdown.fold<int>(0, (n, b) => n + b.caseCount);
  if (sum != r.caseCount) errors.add('Breakdown does not add up');
  return errors;
}
