import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/aed/aed_normalizer.dart';
import 'package:town_pass/features/safe_walk/safety_data/aed/data_taipei_aed_repository.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

List<Map<String, Object?>> rawRows() =>
    ((jsonDecode(
                  File(
                    'lib/features/safe_walk/safety_data/aed/fixtures/aed_raw_sample.json',
                  ).readAsStringSync(),
                )
                as Map)['rows']
            as List)
        .map((row) => (row as Map).cast<String, Object?>())
        .toList();

/// Serves the real sample through data.taipei-shaped responses. No network.
final class FakeDataTaipei {
  FakeDataTaipei(this.rows, {this.reportedCount, this.failRows = false});

  final List<Map<String, Object?>> rows;
  final int? reportedCount;
  final bool failRows;
  bool failMetadata = false;
  final List<Uri> requests = [];

  Future<Object?> call(Uri uri) async {
    requests.add(uri);
    if (uri.path.endsWith('dataset.view')) {
      if (failMetadata) throw const _FakeNetworkError();
      return {
        'payload': {
          'license_name': '依政府資料開放授權條款-第1版',
          'resources': [
            {'rid': aedResourceId, 'last_modified': '2026-09-04 18:15:48'},
          ],
        },
      };
    }
    if (failRows) throw const _FakeNetworkError();
    final offset = int.parse(uri.queryParameters['offset']!);
    final limit = int.parse(uri.queryParameters['limit']!);
    final page = rows.skip(offset).take(limit).toList();
    return {
      'result': {
        'limit': limit,
        'offset': offset,
        'count': reportedCount ?? rows.length,
        'results': page,
      },
    };
  }

  int get rowRequests =>
      requests.where((u) => u.path.contains('/api/v1/dataset/')).length;
}

/// Stands in for a socket/TLS failure without touching dart:io networking.
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
  final fixedNow = DateTime.utc(2026, 11, 7, 6, 44, 57);

  DataTaipeiAedRepository repo(
    FakeDataTaipei source, {
    DateTime Function()? now,
  }) => DataTaipeiAedRepository(
    fetchJson: source.call,
    now: now ?? () => fixedNow,
    pageSize: 4,
  );

  test('reads every page and returns contract-valid live points', () async {
    final source = FakeDataTaipei(rawRows());
    final repository = repo(source);

    final points = await repository.getAssistancePoints(mode: sw.DataMode.live);

    expect(points, hasLength(rawRows().length));
    expect(source.rowRequests, 4); // 15 rows at 4 per page
    expect(points.first.source.retrievedAt, '2026-11-07T14:44:57+08:00');
    expect(points.first.source.dataUpdatedAt, '2026-09-04T18:15:48+08:00');
    expect(points.first.source.license, '政府資料開放授權條款-第1版');
    expect(repository.lastReport!.converted, rawRows().length);
    expect(repository.lastReport!.rejected, isEmpty);
    expect(() => points.add(points.first), throwsUnsupportedError);
  });

  test('builds the documented data.taipei URLs', () {
    final uri = DataTaipeiAedRepository.rowsUri(1000, 1000);

    expect(uri.scheme, 'https');
    expect(uri.host, 'data.taipei');
    expect(uri.path, '/api/v1/dataset/$aedResourceId');
    expect(uri.queryParameters, {
      'scope': 'resourceAquire',
      'limit': '1000',
      'offset': '1000',
    });
  });

  test('mock mode is not served from the live source', () async {
    final source = FakeDataTaipei(rawRows());

    await expectLater(
      repo(source).getAssistancePoints(mode: sw.DataMode.mock),
      throwsA(isA<SafeWalkDataUnavailable>()),
    );
    expect(source.requests, isEmpty);
  });

  test('statistics are not configured for this source', () async {
    await expectLater(
      repo(FakeDataTaipei(rawRows())).getAreaStatistics(mode: sw.DataMode.live),
      throwsA(isA<SafeWalkDataUnavailable>()),
    );
  });

  test('a network failure is an explicit error, not an empty list', () async {
    await expectLater(
      repo(
        FakeDataTaipei(rawRows(), failRows: true),
      ).getAssistancePoints(mode: sw.DataMode.live),
      throwsA(isA<AedSourceUnavailable>()),
    );
  });

  test('an incomplete read is rejected', () async {
    await expectLater(
      repo(
        FakeDataTaipei(rawRows(), reportedCount: 99),
      ).getAssistancePoints(mode: sw.DataMode.live),
      throwsA(
        isA<AedSourceUnavailable>().having(
          (e) => e.message,
          'message',
          contains('incomplete'),
        ),
      ),
    );
  });

  test('an empty configured source returns an empty list', () async {
    final points = await repo(
      FakeDataTaipei([]),
    ).getAssistancePoints(mode: sw.DataMode.live);

    expect(points, isEmpty);
  });

  test('metadata failure leaves update time and licence unknown', () async {
    final source = FakeDataTaipei(rawRows())..failMetadata = true;

    final points = await repo(
      source,
    ).getAssistancePoints(mode: sw.DataMode.live);

    expect(points.first.source.dataUpdatedAt, isNull);
    expect(points.first.source.license, isNull);
  });

  test('caches within the TTL and reloads after it', () async {
    var now = fixedNow;
    final source = FakeDataTaipei(rawRows());
    final repository = repo(source, now: () => now);

    await repository.getAssistancePoints(mode: sw.DataMode.live);
    now = now.add(const Duration(minutes: 59));
    await repository.getAssistancePoints(mode: sw.DataMode.live);
    expect(source.rowRequests, 4);

    now = now.add(const Duration(minutes: 2));
    final reloaded = await repository.getAssistancePoints(
      mode: sw.DataMode.live,
    );
    expect(source.rowRequests, 8);
    expect(reloaded.first.source.retrievedAt, '2026-11-07T15:45:57+08:00');
  });

  test('concurrent callers share one load', () async {
    final source = FakeDataTaipei(rawRows());
    final repository = repo(source);

    await Future.wait([
      repository.getAssistancePoints(mode: sw.DataMode.live),
      repository.getAssistancePoints(mode: sw.DataMode.live),
    ]);

    expect(source.rowRequests, 4);
  });

  test('a cancelled request does not fetch or deliver data', () async {
    final source = FakeDataTaipei(rawRows());
    final cancellation = TestCancellation()..cancel();

    await expectLater(
      repo(source).getAssistancePoints(
        mode: sw.DataMode.live,
        cancellation: cancellation,
      ),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    expect(source.requests, isEmpty);
  });

  test('cancellation during the load withholds the result', () async {
    final source = FakeDataTaipei(rawRows());
    final repository = repo(source);
    final cancellation = TestCancellation();

    final pending = repository.getAssistancePoints(
      mode: sw.DataMode.live,
      cancellation: cancellation,
    );
    cancellation.cancel();

    await expectLater(pending, throwsA(isA<SafeWalkCancelledException>()));
  });

  test('rejects an invalid page size', () {
    expect(
      () => DataTaipeiAedRepository(fetchJson: (_) async => null, pageSize: 0),
      throwsArgumentError,
    );
  });
}
