import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/violent_crime/taipei_violent_crime_repository.dart';
import 'package:town_pass/features/safe_walk/safety_data/violent_crime/violent_crime_normalizer.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

String rawCsv() => File(
  'test/features/safe_walk/safety_data/violent_crime/fixtures/violent_crime_raw_sample.csv',
).readAsStringSync();

/// Serves the real sample through data.taipei / tsis-shaped responses.
/// No network.
final class FakeSource {
  FakeSource({String? csv, this.csvUrl}) : csv = csv ?? rawCsv();

  String csv;
  String? csvUrl;
  bool failMetadata = false;
  bool failCsv = false;
  final List<Uri> requests = [];

  Future<String> call(Uri uri) async {
    requests.add(uri);
    if (uri.path.endsWith('dataset.view')) {
      if (failMetadata) throw const _FakeNetworkError();
      return jsonEncode({
        'payload': {
          'license_name': '依政府資料開放授權條款-第1版',
          'resources': [
            {
              'rid': violentCrimeResourceId,
              'url':
                  csvUrl ??
                  TaipeiViolentCrimeRepository.defaultCsvUri.toString(),
              'last_modified': '2026-10-20 14:03:05',
              'amount': 6,
            },
          ],
        },
      });
    }
    if (failCsv) throw const _FakeNetworkError();
    return csv;
  }

  List<Uri> get csvRequests =>
      requests.where((u) => !u.path.endsWith('dataset.view')).toList();
}

/// Stands in for a socket/TLS failure without touching networking.
final class _FakeNetworkError implements Exception {
  const _FakeNetworkError();
}

final class TestCancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

void main() {
  final fixedNow = DateTime.utc(2026, 11, 7, 8, 20);

  TaipeiViolentCrimeRepository repo(
    FakeSource source, {
    DateTime Function()? now,
  }) => TaipeiViolentCrimeRepository(
    fetchText: source.call,
    now: now ?? () => fixedNow,
  );

  test('returns live monthly records oldest first with a report', () async {
    final source = FakeSource();
    final repository = repo(source);
    final records = await repository.getMonthlyStatistics(
      mode: sw.DataMode.live,
    );

    expect(records, hasLength(6));
    expect(records.first.id, 'tpe-violent-crime-month-2017-01');
    expect(records.last.id, 'tpe-violent-crime-month-2026-08');
    expect(records.first.source.retrievedAt, '2026-11-07T16:20:00+08:00');
    expect(records.first.source.license, '政府資料開放授權條款-第1版');
    final report = repository.lastReport!;
    expect(report.sourceRows, 6);
    expect(report.declaredRows, 6);
    expect(report.converted, 6);
    expect(report.rejected, isEmpty);
    expect(report.csvUri.host, 'tsis.dbas.gov.taipei');
  });

  test('filters by inclusive YYYY-MM range', () async {
    final records = await repo(FakeSource()).getMonthlyStatistics(
      mode: sw.DataMode.live,
      from: '2024-01',
      to: '2026-07',
    );

    expect(records.map((r) => r.id), [
      'tpe-violent-crime-month-2024-02',
      'tpe-violent-crime-month-2026-07',
    ]);
    expect(records.clear, throwsUnsupportedError);
  });

  test('rejects malformed filters', () async {
    final repository = repo(FakeSource());
    for (final (from, to) in <(String?, String?)>[
      ('2026-13', null),
      (null, '2026-1'),
      ('2026-08', '2026-01'),
    ]) {
      await expectLater(
        repository.getMonthlyStatistics(
          mode: sw.DataMode.live,
          from: from,
          to: to,
        ),
        throwsArgumentError,
      );
    }
  });

  test('mock mode is not configured and never returns demo data', () async {
    final source = FakeSource();

    await expectLater(
      repo(source).getMonthlyStatistics(mode: sw.DataMode.mock),
      throwsA(isA<SafeWalkDataUnavailable>()),
    );
    expect(source.requests, isEmpty);
  });

  test('a failed CSV read is reported, not replaced', () async {
    final source = FakeSource()..failCsv = true;

    await expectLater(
      repo(source).getMonthlyStatistics(mode: sw.DataMode.live),
      throwsA(isA<ViolentCrimeSourceUnavailable>()),
    );
  });

  test('an HTML error page is reported as unavailable', () async {
    final source = FakeSource(csv: '<!doctype html><title>Error</title>');

    await expectLater(
      repo(source).getMonthlyStatistics(mode: sw.DataMode.live),
      throwsA(isA<ViolentCrimeSourceUnavailable>()),
    );
  });

  test('a changed column set is reported as unavailable', () async {
    final source = FakeSource(
      csv: rawCsv().replaceFirst('發生件數/其他[件]', '其他'),
    );

    await expectLater(
      repo(source).getMonthlyStatistics(mode: sw.DataMode.live),
      throwsA(isA<ViolentCrimeSourceUnavailable>()),
    );
  });

  test(
    'truncated CSV is unavailable, not cached, and can be retried',
    () async {
      final header = rawCsv()
          .replaceFirst('\uFEFF', '')
          .split('\n')
          .first
          .trim();
      final source = FakeSource(csv: '$header\n"115年 8月",2,1,0,1,"0.08');
      final repository = repo(source);

      await expectLater(
        repository.getMonthlyStatistics(mode: sw.DataMode.live),
        throwsA(isA<ViolentCrimeSourceUnavailable>()),
      );
      expect(repository.lastReport, isNull);

      source.csv = rawCsv();
      final records = await repository.getMonthlyStatistics(
        mode: sw.DataMode.live,
      );
      expect(records, hasLength(6));
      expect(source.csvRequests, hasLength(2));
      expect(repository.lastReport!.converted, 6);
    },
  );

  test('metadata failure falls back to the known CSV link with unknown '
      'licence and update time', () async {
    final source = FakeSource()..failMetadata = true;
    final repository = repo(source);
    final records = await repository.getMonthlyStatistics(
      mode: sw.DataMode.live,
    );

    expect(records, hasLength(6));
    expect(records.first.source.license, isNull);
    expect(records.first.source.dataUpdatedAt, isNull);
    expect(repository.lastReport!.declaredRows, isNull);
    expect(source.csvRequests.single, TaipeiViolentCrimeRepository.defaultCsvUri);
  });

  test('a metadata link outside the statistics host is ignored', () async {
    final source = FakeSource(csvUrl: 'https://example.org/evil.csv');
    await repo(source).getMonthlyStatistics(mode: sw.DataMode.live);

    expect(source.csvRequests.single.host, 'tsis.dbas.gov.taipei');
  });

  test('caches within the TTL and reloads after it', () async {
    final source = FakeSource();
    var now = fixedNow;
    final repository = repo(source, now: () => now);

    await repository.getMonthlyStatistics(mode: sw.DataMode.live);
    await repository.getMonthlyStatistics(mode: sw.DataMode.live);
    expect(source.csvRequests, hasLength(1));

    now = fixedNow.add(const Duration(hours: 7));
    await repository.getMonthlyStatistics(mode: sw.DataMode.live);
    expect(source.csvRequests, hasLength(2));
  });

  test('concurrent callers share one load', () async {
    final source = FakeSource();
    final repository = repo(source);

    await Future.wait([
      repository.getMonthlyStatistics(mode: sw.DataMode.live),
      repository.getMonthlyStatistics(mode: sw.DataMode.live),
    ]);
    expect(source.csvRequests, hasLength(1));
  });

  test('a cancelled caller receives nothing', () async {
    final source = FakeSource();
    final cancelled = TestCancellation()..cancel();

    await expectLater(
      repo(source).getMonthlyStatistics(
        mode: sw.DataMode.live,
        cancellation: cancelled,
      ),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    expect(source.requests, isEmpty);
  });
}
