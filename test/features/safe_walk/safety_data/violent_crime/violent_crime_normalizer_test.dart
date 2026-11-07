import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/violent_crime/get_connect_text_fetcher.dart';
import 'package:town_pass/features/safe_walk/safety_data/violent_crime/violent_crime_normalizer.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const _fixtures = 'lib/features/safe_walk/safety_data/violent_crime/fixtures';

String rawCsv() =>
    File('$_fixtures/violent_crime_raw_sample.csv').readAsStringSync();

String header() => rawCsv().replaceFirst('﻿', '').split('\n').first.trim();

/// Same fixed retrieval facts as the legacy Node make-sample-output.mjs.
const fixedInfo = ViolentCrimeSourceInfo(
  retrievedAt: '2026-11-07T16:20:00+08:00',
  resourceLastModified: '2026-10-20 14:03:05',
  licenseName: '依政府資料開放授權條款-第1版',
);

void main() {
  test('matches the legacy Node output on the real sample exactly', () {
    final expected = jsonDecode(
      File('$_fixtures/violent_crime_expected.json').readAsStringSync(),
    );
    final actual = normalizeViolentCrimeCsv(rawCsv(), fixedInfo);

    expect(actual.rejected, isEmpty);
    expect([for (final r in actual.records) r.toJson()], expected);
  });

  test('every sample record passes the shared source and local checks', () {
    final records = normalizeViolentCrimeCsv(rawCsv(), fixedInfo).records;

    expect(records, hasLength(6));
    for (final r in records) {
      expect(cityCrimeProblems(r), isEmpty);
      expect(r.source.dataMode, sw.DataMode.live);
      expect(r.source.sourceUrl, violentCrimeDatasetPageUrl);
      expect(r.source.dataUpdatedAt, '2026-10-20T14:03:05+08:00');
      expect(r.source.retrievedAt, isNot(r.source.dataUpdatedAt));
    }
  });

  test('city-wide data is never labelled as a district or given a rate', () {
    for (final r in normalizeViolentCrimeCsv(rawCsv(), fixedInfo).records) {
      final json = r.toJson();
      expect(r.geographicLevel, 'city');
      expect(json.containsKey('district'), isFalse);
      expect(json.containsKey('ratePer100k'), isFalse);
      expect(r.populationDenominator, isNull);
    }
  });

  test('ROC months convert to Gregorian bounds, including leap February', () {
    expect(parseRocMonth('115年 8月'), (year: 2026, month: 8));
    expect(parseRocMonth('115年13月'), isNull);
    expect(parseRocMonth('115年'), isNull);
    expect(monthBounds(2024, 2), (
      periodStart: '2024-02-01',
      periodEnd: '2024-02-29',
    ));
    expect(monthBounds(2026, 12).periodEnd, '2026-12-31');
  });

  test('bad rows are rejected with their line number, never repaired', () {
    final csv = [
      header(),
      '"115年 9月",5,1,1,1,0.2,0,0,0,0,0,0,0',
      '"115年10月",-,0,0,0,0,0,0,0,0,0,0,0',
      '"合計",1,1,0,0,0,0,0,0,0,0,0,0',
      '"115年 8月",2,1,0,1,0.08,2,0.08,2,2,0,0,100',
      '"115年 8月",2,1,0,1,0.08,2,0.08,2,2,0,0,100',
    ].join('\r\n');
    final result = normalizeViolentCrimeCsv(csv, fixedInfo);

    expect(result.records, hasLength(1));
    expect(result.rejected.map((r) => r.line), [2, 3, 4, 6]);
  });

  test('a missing source column fails the whole read', () {
    final csv = '${header().replaceFirst('發生件數/其他[件]', 'X')}\n"115年 8月",2';

    expect(
      () => normalizeViolentCrimeCsv(csv, fixedInfo),
      throwsA(isA<ViolentCrimeFormatException>()),
    );
  });

  test('unknown licence and update time stay null; offset is required', () {
    final source = buildViolentCrimeSource(
      const ViolentCrimeSourceInfo(
        retrievedAt: '2026-11-07T16:20:00+08:00',
        resourceLastModified: null,
        licenseName: '其他條款',
      ),
    );

    expect(source.license, isNull);
    expect(source.dataUpdatedAt, isNull);
    expect(normalizeLicense('依政府資料開放授權條款-第1版'), '政府資料開放授權條款-第1版');
    expect(platformTimeToIso('not a time'), isNull);
    expect(
      () => buildViolentCrimeSource(
        const ViolentCrimeSourceInfo(
          retrievedAt: '2026-11-07T16:20:00',
          resourceLastModified: null,
          licenseName: null,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('CSV parser handles BOM, quotes and CRLF', () {
    expect(parseCsv('﻿"a","b ""c"""\r\n1,2\r\n'), [
      ['a', 'b "c"'],
      ['1', '2'],
    ]);
  });

  test('an unterminated quoted field rejects the whole CSV import', () {
    final csv =
        '${rawCsv().trimRight()}\r\n'
        '"115年 9月",3,1,1,1,"0.12';

    expect(
      () => normalizeViolentCrimeCsv(csv, fixedInfo),
      throwsA(isA<ViolentCrimeFormatException>()),
    );
  });

  test('an overflowing rate rejects its row and keeps valid JSON records', () {
    final overflow = List.filled(400, '9').join();
    final csv =
        '${rawCsv().trimRight()}\r\n'
        '"115年 9月",3,1,1,1,$overflow';
    final result = normalizeViolentCrimeCsv(csv, fixedInfo);

    expect(result.records, hasLength(6));
    expect(result.rejected, hasLength(1));
    expect(result.rejected.single.line, 8);
    expect(result.rejected.single.reason, contains('non-finite'));
    expect(
      () => jsonEncode([for (final record in result.records) record.toJson()]),
      returnsNormally,
    );
  });

  test(
    'local semantic checks reject manually constructed non-finite rates',
    () {
      final valid = normalizeViolentCrimeCsv(rawCsv(), fixedInfo).records.first;
      for (final rate in [
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        final invalid = CityMonthlyCrimeStatistics(
          id: valid.id,
          periodStart: valid.periodStart,
          periodEnd: valid.periodEnd,
          caseCount: valid.caseCount,
          breakdown: valid.breakdown,
          sourceReportedRatePer100k: rate,
          source: valid.source,
        );

        expect(
          cityCrimeProblems(invalid),
          contains('Source-reported rate must be finite'),
        );
      }
    },
  );

  test('formats any instant as Taipei time with an offset', () {
    expect(
      formatTaipeiTime(DateTime.utc(2026, 12, 31, 20, 0, 0)),
      '2027-01-01T04:00:00+08:00',
    );
  });

  test('UTF-8 text mis-decoded as Latin-1 is restored; good text is kept', () {
    const original = '"統計期","發生件數/總計[件]"';
    final misDecoded = latin1.decode(utf8.encode(original));

    expect(redecodeLatin1AsUtf8(misDecoded), original);
    expect(redecodeLatin1AsUtf8(original), original);
    expect(redecodeLatin1AsUtf8('plain ascii'), 'plain ascii');
  });
}
