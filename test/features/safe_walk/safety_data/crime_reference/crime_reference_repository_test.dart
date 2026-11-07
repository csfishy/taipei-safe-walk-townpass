import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial payloads only: no real record, address or snapshot content.
Map<String, Object?> source({String key = 'src_a'}) => {
  'sourceKey': key,
  'datasetId': 'artificial-dataset',
  'resourceId': null,
  'name': '人工測試來源',
  'sourceUrl': 'https://example.test/dataset',
  'resourceUrl': 'https://example.test/resource.csv',
  'license': '人工測試授權',
  'retrievedAt': '2026-10-01T00:00:00+00:00',
  'dataUpdatedAt': null,
  'recordCount': 2,
};

Map<String, Object?> record({
  String id = 'row-1',
  String sourceKey = 'src_a',
  String city = '臺北市',
  String date = '2026-05-01',
  Object? lat = 25.0,
  Object? lng = 121.5,
  String precision = 'address_reference',
  String confidence = 'high',
  String status = 'reference_geocoded',
}) => {
  'sourceKey': sourceKey,
  'sourceRecordId': id,
  'eventDate': date,
  'city': city,
  'district': null,
  'category': '人工類別',
  'locationText': '人工測試地點',
  'latitude': lat,
  'longitude': lng,
  'spatialPrecision': precision,
  'confidence': confidence,
  'coordinateStatus': status,
};

Map<String, Object?> response({
  List<Map<String, Object?>>? records,
  List<Map<String, Object?>>? sources,
  int total = 2,
  int version = 1,
}) => {
  'interfaceVersion': version,
  'snapshot': {
    'snapshotId': '00000000-0000-4000-8000-000000000000',
    'label': 'artificial',
    'asOfDate': '2026-09-30',
    'importedAt': '2026-10-02T00:00:00+00:00',
    'recordCount': 10,
  },
  'sources': sources ?? [source()],
  'query': <String, Object?>{},
  'totalMatching': total,
  'records':
      records ??
      [
        record(),
        record(
          id: 'row-2',
          lat: null,
          lng: null,
          precision: 'district_only',
          confidence: 'unknown',
          status: 'not_provided',
        ),
      ],
};

CrimeReferenceRepository repo(
  FutureOr<CrimeReferenceHttpResponse> Function(Map<String, Object?> args)
  answer,
) => CrimeReferenceRepository(
  transport: (args) async => answer(args),
  now: () => DateTime.utc(2026, 11, 8),
);

CrimeReferenceRepository ok(Object body) =>
    repo((_) => CrimeReferenceHttpResponse(200, jsonEncode(body)));

Matcher fails(CrimeReferenceFailure failure) => throwsA(
  isA<CrimeReferenceQueryException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

final class _Cancel implements SafeWalkCancellation {
  bool cancelled = false;
  @override
  bool get isCancelled => cancelled;
  @override
  Future<void> get whenCancelled => Completer<void>().future;
}

void main() {
  const live = sw.DataMode.live;

  group('configuration and mode', () {
    test('unconfigured live is explicitly unavailable, never mock', () {
      final r = CrimeReferenceRepository(transport: null);
      expect(r.isConfigured, isFalse);
      expect(r.query(mode: live), throwsA(isA<SafeWalkDataUnavailable>()));
    });

    test('mock mode has no dataset and does not call the transport', () async {
      var calls = 0;
      final r = repo((_) {
        calls++;
        return CrimeReferenceHttpResponse(200, jsonEncode(response()));
      });
      await expectLater(
        r.query(mode: sw.DataMode.mock),
        throwsA(isA<SafeWalkDataUnavailable>()),
      );
      expect(calls, 0);
    });

    test('invalid query fails before any request', () async {
      var calls = 0;
      final r = repo((_) {
        calls++;
        return const CrimeReferenceHttpResponse(200, '{}');
      });
      for (final q in [
        const CrimeReferenceQuery(city: '臺中市'),
        const CrimeReferenceQuery(limit: 0),
        const CrimeReferenceQuery(limit: 201),
        const CrimeReferenceQuery(offset: 5001),
        const CrimeReferenceQuery(from: '2026-05-02', to: '2026-05-01'),
        const CrimeReferenceQuery(from: '2026/05/01'),
        const CrimeReferenceQuery(category: ' '),
        const CrimeReferenceQuery(
          bounds: CrimeReferenceBounds(
            minLat: 25,
            minLng: 121,
            maxLat: 26,
            maxLng: 121.2,
          ),
        ),
      ]) {
        await expectLater(r.query(mode: live, query: q), throwsArgumentError);
      }
      expect(calls, 0);
    });
  });

  group('successful answers', () {
    test('keeps provenance, dates and precision; sends named args', () async {
      Map<String, Object?>? sent;
      final r = repo((args) {
        sent = args;
        return CrimeReferenceHttpResponse(200, jsonEncode(response()));
      });
      final result = await r.query(
        mode: live,
        query: const CrimeReferenceQuery(city: '臺北市', limit: 20),
      );
      expect(sent!['p_city'], '臺北市');
      expect(sent!['p_limit'], 20);
      expect(sent!['p_min_lat'], isNull);
      expect(result.snapshot.asOfDate, '2026-09-30');
      expect(result.sources.single.sourceUrl.host, 'example.test');
      expect(result.sources.single.dataUpdatedAt, isNull);
      expect(result.totalMatching, 2);
      expect(result.retrievedAt, '2026-11-08T00:00:00.000Z');
      final [first, second] = result.records;
      expect(first.spatialPrecision, CrimeSpatialPrecision.addressReference);
      expect(first.hasReferenceCoordinate, isTrue);
      expect(first.source.sourceKey, 'src_a');
      expect(second.latitude, isNull);
      expect(second.coordinateStatus, CrimeCoordinateStatus.notProvided);
      expect(result.limitations, isNotEmpty);
    });

    test('an empty page is a real answer, not an error', () async {
      final result = await ok(response(records: [], total: 0))
          .query(mode: live);
      expect(result.records, isEmpty);
      expect(result.totalMatching, 0);
    });
  });

  group('rejects answers that could invent or misplace a location', () {
    final bad = <String, Map<String, Object?>>{
      'unknown interface version': response(version: 2),
      'coarse precision with coordinate': response(
        records: [record(precision: 'district_only')],
      ),
      'unpaired coordinate': response(records: [record(lng: null)]),
      'coordinate without status': response(
        records: [record(status: 'not_provided')],
      ),
      'status without coordinate': response(
        records: [record(lat: null, lng: null)],
      ),
      'unknown confidence with geocoded point': response(
        records: [record(confidence: 'unknown')],
      ),
      'unknown source key': response(records: [record(sourceKey: 'other')]),
      'unknown precision label': response(
        records: [record(precision: 'exact_point')],
      ),
      'event after snapshot date': response(
        records: [record(date: '2026-10-01')],
      ),
      'city outside coverage': response(records: [record(city: '臺中市')]),
      'non-https source': response(
        sources: [
          {...source(), 'sourceUrl': 'http://example.test/x'},
        ],
      ),
      'no sources': response(sources: [], records: []),
      'more records than total': response(total: 1),
    };
    bad.forEach((name, body) {
      test(name, () {
        expect(
          ok(body).query(mode: live),
          fails(CrimeReferenceFailure.invalidResponse),
        );
      });
    });

    test('record outside the requested city or bounds', () {
      expect(
        ok(response()).query(
          mode: live,
          query: const CrimeReferenceQuery(city: '新北市'),
        ),
        fails(CrimeReferenceFailure.invalidResponse),
      );
      expect(
        ok(response(records: [record()], total: 1)).query(
          mode: live,
          query: const CrimeReferenceQuery(
            bounds: CrimeReferenceBounds(
              minLat: 24.0,
              minLng: 121.0,
              maxLat: 24.1,
              maxLng: 121.1,
            ),
          ),
        ),
        fails(CrimeReferenceFailure.invalidResponse),
      );
    });

    test('non-JSON body', () {
      expect(
        repo((_) => const CrimeReferenceHttpResponse(200, '<html>'))
            .query(mode: live),
        fails(CrimeReferenceFailure.invalidResponse),
      );
    });
  });

  group('error mapping hides bodies', () {
    final cases = <(int, Object?), CrimeReferenceFailure>{
      (404, {'code': 'PGRST202', 'message': 'not found'}):
          CrimeReferenceFailure.interfaceMissing,
      (400, {'code': '22023', 'message': 'crime_reference_invalid_argument'}):
          CrimeReferenceFailure.invalidArgument,
      (
        400,
        {'code': 'P0001', 'message': 'crime_reference_snapshot_unavailable'},
      ): CrimeReferenceFailure.snapshotUnavailable,
      (401, {'message': 'Invalid API key'}): CrimeReferenceFailure.unauthorized,
      (403, {'code': '42501', 'message': 'permission denied'}):
          CrimeReferenceFailure.unauthorized,
      (429, null): CrimeReferenceFailure.serverUnavailable,
      (503, 'down'): CrimeReferenceFailure.serverUnavailable,
      (400, {'code': 'XX000', 'message': 'other'}):
          CrimeReferenceFailure.invalidResponse,
    };
    cases.forEach((input, failure) {
      final (status, body) = input;
      test('HTTP $status → ${failure.name}', () async {
        final r = repo(
          (_) => CrimeReferenceHttpResponse(status, jsonEncode(body)),
        );
        try {
          await r.query(mode: live);
          fail('expected failure');
        } on CrimeReferenceQueryException catch (e) {
          expect(e.failure, failure);
          expect(e.statusCode, status);
          expect(e.toString(), isNot(contains('message')));
        }
      });
    });

    test('timeout and network are distinct', () {
      expect(
        repo((_) => throw TimeoutException('t')).query(mode: live),
        fails(CrimeReferenceFailure.timeout),
      );
      expect(
        repo((_) => throw StateError('socket')).query(mode: live),
        fails(CrimeReferenceFailure.network),
      );
    });
  });

  test('transport cancellation keeps cancellation semantics without a caller token', () async {
    await expectLater(
      repo((_) => throw const SafeWalkCancelledException()).query(mode: live),
      throwsA(isA<SafeWalkCancelledException>()),
    );
  });

  test('cancellation before or during the call delivers nothing', () async {
    final cancel = _Cancel()..cancelled = true;
    await expectLater(
      ok(response()).query(mode: live, cancellation: cancel),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    final during = _Cancel();
    final r = repo((_) {
      during.cancelled = true;
      return CrimeReferenceHttpResponse(200, jsonEncode(response()));
    });
    await expectLater(
      r.query(mode: live, cancellation: during),
      throwsA(isA<SafeWalkCancelledException>()),
    );
  });
}
