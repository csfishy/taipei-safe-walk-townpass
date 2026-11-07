import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/aed/aed_normalizer.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const _fixtures = 'lib/features/safe_walk/safety_data/aed/fixtures';

List<Map<String, Object?>> rawRows() =>
    ((jsonDecode(File('$_fixtures/aed_raw_sample.json').readAsStringSync())
                as Map)['rows']
            as List)
        .map((row) => (row as Map).cast<String, Object?>())
        .toList();

/// Same fixed retrieval facts as tool/make_fixtures.py.
const fixedInfo = AedSourceInfo(
  retrievedAt: '2026-11-07T14:44:57+08:00',
  resourceLastModified: '2026-09-04 18:15:48',
  licenseName: '依政府資料開放授權條款-第1版',
);

void main() {
  const parser = ContractSafetyDataParser();

  test('matches the Python tool output on the real sample exactly', () {
    final expected = jsonDecode(
      File('$_fixtures/aed_expected_points.json').readAsStringSync(),
    );
    final actual = normalizeAedRows(rawRows(), fixedInfo);

    expect(actual.rejected, isEmpty);
    expect(actual.points, expected);
  });

  test('every sample row passes the shared contract and semantics', () {
    final points = normalizeAedRows(rawRows(), fixedInfo).points;

    expect(points, hasLength(rawRows().length));
    for (final json in points) {
      final point = parser.parseAssistancePoint(json);
      expect(point.kind, sw.AssistancePointKind.publicFacility);
      expect(point.recognition, isA<sw.UnconfirmedRecognition>());
      expect(point.availability, sw.OpeningStatus.unknown);
      expect(point.availabilityCheckedAt, isNull);
      expect(point.capabilities, [sw.AssistanceCapability.unknown]);
      expect(point.publicPhone, isNull);
      expect(point.source.dataMode, sw.DataMode.live);
      expect(point.source.sourceUrl, aedDatasetPageUrl);
      expect(point.source.dataUpdatedAt, '2026-09-04T18:15:48+08:00');
      expect(point.source.retrievedAt, isNot(point.source.dataUpdatedAt));
    }
  });

  test('ids are unique, readable and independent of input order', () {
    final ids = normalizeAedRows(
      rawRows(),
      fixedInfo,
    ).points.map((p) => p['id']).toList();
    final reversed = normalizeAedRows(
      rawRows().reversed,
      fixedInfo,
    ).points.map((p) => p['id']).toList();

    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, contains('tpe-aed-63000110-25.10235-121.548432-2'));
    expect(reversed, ids);
  });

  test('bad coordinates are rejected with the row number only', () {
    final base = rawRows().first;
    final result = normalizeAedRows([
      {...base, '_id': 9001, '緯度': '', '經度': '121.5'},
      {...base, '_id': 9002, '緯度': '121.528283', '經度': '25.02603'},
      {...base, '_id': 9003, '緯度': '22.6', '經度': '120.3'},
      {...base, '_id': 9004, '緯度': 'NaN', '經度': '121.5'},
      {...base, '_id': 9005, '場所名稱': '  '},
    ], fixedInfo);

    expect(result.points, isEmpty);
    expect(result.rejected.map((r) => r.rowId), [9001, 9002, 9003, 9004, 9005]);
    expect(
      result.rejected.map((r) => r.toString()).join(),
      isNot(contains(base['場所名稱'] as String)),
    );
  });

  test('address rules', () {
    expect(makeAddress('忠孝東路五段六號', '信義區'), '臺北市信義區忠孝東路五段六號');
    expect(makeAddress('台北市松山區健康路227號', '松山區'), '臺北市松山區健康路227號');
    expect(makeAddress('大安區臨江街', '大安區'), '臺北市大安區臨江街');
    expect(makeAddress('   ', '中正區'), isNull);
  });

  test('unknown licence and update time stay null', () {
    final source = buildAedSource(
      const AedSourceInfo(
        retrievedAt: '2026-11-07T14:44:57+08:00',
        resourceLastModified: null,
        licenseName: '依菸酒管理法相關規定',
      ),
    );

    expect(source['license'], isNull);
    expect(source['dataUpdatedAt'], isNull);
    expect(platformTimeToIso('not a time'), isNull);
  });

  test('formats any instant as Taipei time with an offset', () {
    expect(
      formatTaipeiTime(DateTime.utc(2026, 11, 7, 6, 44, 57, 123)),
      '2026-11-07T14:44:57+08:00',
    );
    expect(
      formatTaipeiTime(DateTime.utc(2026, 12, 31, 20, 0, 0)),
      '2027-01-01T04:00:00+08:00',
    );
  });
}
