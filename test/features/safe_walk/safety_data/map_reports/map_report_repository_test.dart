import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/map_reports/map_report_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial coordinates and descriptions only. No real user report is sent.
const _id = '00000000-0000-4000-8000-000000000001';
const _otherId = '00000000-0000-4000-8000-000000000002';
const _live = sw.DataMode.live;

Map<String, Object?> _record({
  String id = _id,
  String category = 'lighting',
  Object latitude = 25.0,
  Object longitude = 121.5,
  String description = '人工測試',
  String date = '2026-11-08T01:02:03+00:00',
}) => {
  'id': id,
  'category': category,
  'latitude': latitude,
  'longitude': longitude,
  'description': description,
  'reportedAt': date,
};

MapReportRepository _repo(Object? body, {int status = 200}) =>
    MapReportRepository(
      transport: (_, _, {cancellation}) async =>
          MapReportHttpResponse(status, jsonEncode(body)),
    );

Future<MapReportRecord> _submit(
  MapReportRepository repo, {
  String requestId = _id,
  String category = 'lighting',
  double latitude = 25,
  double longitude = 121.5,
  String description = '人工測試',
  SafeWalkCancellation? cancellation,
}) => repo.submit(
  mode: _live,
  requestId: requestId,
  category: category,
  latitude: latitude,
  longitude: longitude,
  description: description,
  cancellation: cancellation,
);

Map<String, Object?> _page({
  List<Map<String, Object?>>? records,
  int total = 1,
  int limit = 200,
  int offset = 0,
}) => {
  'interfaceVersion': 1,
  'records': records ?? [_record()],
  'totalMatching': total,
  'limit': limit,
  'offset': offset,
};

Matcher _fails(MapReportFailure failure) => throwsA(
  isA<MapReportException>().having((e) => e.failure, 'failure', failure),
);

final class _Cancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();
  void cancel() => _cancelled.complete();
  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;
}

void main() {
  test(
    'unconfigured and mock do not pretend to persist or call transport',
    () async {
      final unavailable = MapReportRepository(transport: null);
      expect(unavailable.isConfigured, isFalse);
      await expectLater(
        _submit(unavailable),
        throwsA(isA<SafeWalkDataUnavailable>()),
      );
      await expectLater(
        unavailable.query(mode: _live),
        throwsA(isA<SafeWalkDataUnavailable>()),
      );
      var calls = 0;
      final repo = MapReportRepository(
        transport: (_, _, {cancellation}) async {
          calls++;
          return const MapReportHttpResponse(200, '{}');
        },
      );
      await expectLater(
        repo.submit(
          mode: sw.DataMode.mock,
          requestId: _id,
          category: 'other',
          latitude: 0,
          longitude: 0,
        ),
        throwsA(isA<SafeWalkDataUnavailable>()),
      );
      await expectLater(
        repo.query(mode: sw.DataMode.mock),
        throwsA(isA<SafeWalkDataUnavailable>()),
      );
      expect(calls, 0);
    },
  );

  test('submit sends selected data and requires matching persisted acknowledgement', () async {
    final token = _Cancellation();
    final repo = MapReportRepository(
      transport: (function, args, {cancellation}) async {
        expect(function, mapReportSubmitRpcFunction);
        expect(args, {
          'p_request_id': _id,
          'p_category': 'lighting',
          'p_latitude': 25.0,
          'p_longitude': 121.5,
          'p_description': '人工測試',
        });
        expect(cancellation, same(token));
        return MapReportHttpResponse(
          200,
          jsonEncode({'interfaceVersion': 1, 'report': _record()}),
        );
      },
    );
    final record = await _submit(
      repo,
      description: '  人工測試  ',
      cancellation: token,
    );
    expect(record.id, _id);
    expect(record.reportedAt, DateTime.utc(2026, 11, 8, 1, 2, 3));
    expect(record.latitude, 25);
  });

  test('invalid report fields never start a request', () async {
    var calls = 0;
    final repo = MapReportRepository(
      transport: (_, _, {cancellation}) async {
        calls++;
        return const MapReportHttpResponse(200, '{}');
      },
    );
    for (final action in <Future<MapReportRecord> Function()>[
      () => _submit(repo, requestId: 'local_timestamp'),
      () => _submit(repo, category: 'unknown'),
      () => _submit(repo, latitude: double.nan),
      () => _submit(repo, longitude: double.infinity),
      () => _submit(repo, latitude: -91),
      () => _submit(repo, longitude: 181),
      () => _submit(repo, description: 'x' * 501),
      () => _submit(repo, description: 'has\u0000null'),
    ]) {
      await expectLater(action(), throwsArgumentError);
    }
    expect(calls, 0);
  });

  test(
    'precise map coordinates survive submit, retry and reload exactly',
    () async {
      const latitude = 0.012345678901234567;
      const longitude = 0.0567890123456789123;
      final persisted = _record(latitude: latitude, longitude: longitude);
      final functions = <String>[];
      final repo = MapReportRepository(
        transport: (function, args, {cancellation}) async {
          functions.add(function);
          if (function == mapReportSubmitRpcFunction) {
            expect(args['p_latitude'], latitude);
            expect(args['p_longitude'], longitude);
            return MapReportHttpResponse(
              200,
              jsonEncode({'interfaceVersion': 1, 'report': persisted}),
            );
          }
          return MapReportHttpResponse(
            200,
            jsonEncode(_page(records: [persisted])),
          );
        },
      );
      final first = await _submit(
        repo,
        latitude: latitude,
        longitude: longitude,
      );
      final retry = await _submit(
        repo,
        latitude: latitude,
        longitude: longitude,
      );
      final reloaded = (await repo.query(mode: _live)).records.single;
      for (final record in [first, retry, reloaded]) {
        expect(record.latitude, latitude);
        expect(record.longitude, longitude);
        expect(record.id, _id);
      }
      expect(functions, [
        mapReportSubmitRpcFunction,
        mapReportSubmitRpcFunction,
        mapReportQueryRpcFunction,
      ]);
    },
  );

  test('a rounded coordinate in HTTP 200 is not a confirmed exact write', () async {
    const latitude = 0.012345678901234567;
    const longitude = 0.0567890123456789123;
    // PostgreSQL extra_float_digits=0 formerly emitted only 15 significant
    // digits, even though the stored float8 retained the precise chosen point.
    final roundedLatitude = double.parse(latitude.toStringAsPrecision(15));
    final roundedLongitude = double.parse(longitude.toStringAsPrecision(15));
    expect(roundedLatitude, isNot(latitude));
    expect(roundedLongitude, isNot(longitude));
    final repo = _repo({
      'interfaceVersion': 1,
      'report': _record(latitude: roundedLatitude, longitude: roundedLongitude),
    });
    await expectLater(
      _submit(repo, latitude: latitude, longitude: longitude),
      _fails(MapReportFailure.invalidResponse),
    );
  });

  test(
    'wrong id or persisted field in 200 reply is not a successful write',
    () async {
      for (final record in [
        _record(id: _otherId),
        _record(category: 'fight'),
        _record(latitude: 25.01),
        _record(longitude: 121.51),
        _record(description: 'changed'),
      ]) {
        await expectLater(
          _submit(_repo({'interfaceVersion': 1, 'report': record})),
          _fails(MapReportFailure.invalidResponse),
        );
      }
    },
  );

  test(
    'query sends bounds, preserves real empty data, and parses a bounded page',
    () async {
      final repo = MapReportRepository(
        transport: (function, args, {cancellation}) async {
          expect(function, mapReportQueryRpcFunction);
          expect(args, {
            'p_min_lat': 25.0,
            'p_min_lng': 121.4,
            'p_max_lat': 25.2,
            'p_max_lng': 121.6,
            'p_limit': 1,
            'p_offset': 0,
          });
          return MapReportHttpResponse(
            200,
            jsonEncode(_page(total: 2, limit: 1)),
          );
        },
      );
      final page = await repo.query(
        mode: _live,
        bounds: const MapReportBounds(
          minLat: 25,
          minLng: 121.4,
          maxLat: 25.2,
          maxLng: 121.6,
        ),
        limit: 1,
      );
      expect(page.records.single.id, _id);
      expect(page.totalMatching, 2);
      expect(page.hasMore, isTrue);
      expect(() => page.records.clear(), throwsUnsupportedError);
      final empty = await _repo(_page(records: [], total: 0))
          .query(mode: _live);
      expect(empty.records, isEmpty);
      expect(empty.hasMore, isFalse);
    },
  );

  test('bounds and page limits reject invalid input before network', () async {
    var calls = 0;
    final repo = MapReportRepository(
      transport: (_, _, {cancellation}) async {
        calls++;
        return const MapReportHttpResponse(200, '{}');
      },
    );
    for (final bounds in [
      const MapReportBounds(minLat: 26, minLng: 121, maxLat: 25, maxLng: 121),
      const MapReportBounds(minLat: 25, minLng: 122, maxLat: 25, maxLng: 121),
      const MapReportBounds(minLat: 25, minLng: 121, maxLat: 26, maxLng: 121),
      const MapReportBounds(
        minLat: double.nan,
        minLng: 121,
        maxLat: 25,
        maxLng: 121,
      ),
      const MapReportBounds(minLat: 25, minLng: 181, maxLat: 25, maxLng: 181),
    ]) {
      await expectLater(
        repo.query(mode: _live, bounds: bounds),
        throwsArgumentError,
      );
    }
    for (final limit in [0, 201]) {
      await expectLater(
        repo.query(mode: _live, limit: limit),
        throwsArgumentError,
      );
    }
    for (final offset in [-1, 5001]) {
      await expectLater(
        repo.query(mode: _live, offset: offset),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test(
    'malformed records/pages are explicit failures and cannot hide data loss',
    () async {
      for (final payload in [
        <Object?>[], <String, Object?>{},
        {..._page(), 'interfaceVersion': 2},
        _page(records: [_record(id: 'bad')]),
        _page(records: [_record(latitude: '25')]),
        _page(records: [_record(category: 'bad')]),
        _page(records: [_record(date: '2026-11-08T01:00:00')]),
        _page(records: [_record(), _record()], total: 2),
        _page(total: 0),
        _page(total: 300), // truncated rows must fill the requested page.
        _page(offset: 1),
        _page(limit: 201),
      ]) {
        await expectLater(
          _repo(payload).query(mode: _live),
          _fails(MapReportFailure.invalidResponse),
        );
      }
    },
  );

  test('records outside the requested bounds are rejected', () async {
    await expectLater(
      _repo(_page()).query(
        mode: _live,
        bounds: const MapReportBounds(
          minLat: 24,
          minLng: 121,
          maxLat: 24.1,
          maxLng: 121.1,
        ),
      ),
      _fails(MapReportFailure.invalidResponse),
    );
  });

  test('Unicode description length matches Postgres character count', () async {
    final description = '🙂' * 500;
    final repo = _repo({
      'interfaceVersion': 1,
      'report': _record(description: description),
    });
    expect(
      (await _submit(repo, description: description)).description,
      description,
    );
    await expectLater(
      _submit(repo, description: '$description🙂'),
      throwsArgumentError,
    );
  });

  test(
    'HTTP and SQL errors preserve meaningful failure without body leakage',
    () async {
      for (final (status, code, expected) in [
        (401, '', MapReportFailure.unauthorized),
        (403, '42501', MapReportFailure.unauthorized),
        (404, 'PGRST202', MapReportFailure.interfaceMissing),
        (400, '22023', MapReportFailure.invalidArgument),
        (400, '22P02', MapReportFailure.invalidArgument),
        (409, '23505', MapReportFailure.conflict),
        (429, 'PT429', MapReportFailure.rateLimited),
        (503, '', MapReportFailure.serverUnavailable),
        (418, '', MapReportFailure.invalidResponse),
      ]) {
        final repo = _repo({
          'code': code,
          'message': 'sensitive response content',
        }, status: status);
        await expectLater(_submit(repo), _fails(expected));
        await expectLater(repo.query(mode: _live), _fails(expected));
      }
      expect(
        const MapReportException(MapReportFailure.network).toString(),
        isNot(contains('sensitive')),
      );
    },
  );

  test(
    'network, timeout and non-JSON success do not become empty reports',
    () async {
      for (final (error, expected) in [
        (TimeoutException('artificial'), MapReportFailure.timeout),
        (StateError('artificial'), MapReportFailure.network),
      ]) {
        final repo = MapReportRepository(
          transport: (_, _, {cancellation}) async => throw error,
        );
        await expectLater(_submit(repo), _fails(expected));
      }
      final repo = MapReportRepository(
        transport: (_, _, {cancellation}) async =>
            const MapReportHttpResponse(200, '<html>not json</html>'),
      );
      await expectLater(
        repo.query(mode: _live),
        _fails(MapReportFailure.invalidResponse),
      );
    },
  );

  test('pre-cancelled request never reaches transport', () async {
    final token = _Cancellation()..cancel();
    var calls = 0;
    final repo = MapReportRepository(
      transport: (_, _, {cancellation}) async {
        calls++;
        return const MapReportHttpResponse(200, '{}');
      },
    );
    await expectLater(
      _submit(repo, cancellation: token),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    expect(calls, 0);
  });

  test(
    'cancellation discards late answer even when transport ignores token',
    () async {
      final token = _Cancellation();
      final answer = Completer<MapReportHttpResponse>();
      final repo = MapReportRepository(
        transport: (_, _, {cancellation}) => answer.future,
      );
      final pending = _submit(repo, cancellation: token);
      token.cancel();
      await expectLater(pending, throwsA(isA<SafeWalkCancelledException>()));
      answer.complete(
        MapReportHttpResponse(
          200,
          jsonEncode({'interfaceVersion': 1, 'report': _record()}),
        ),
      );
    },
  );
}
