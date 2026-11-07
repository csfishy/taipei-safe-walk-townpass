import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_warning/crime_warning_parser.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_warning/crime_warning_repository.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_warning/verified_crime_geography.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_warning/reviewed_taipei_crime_geography.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/crime_warning.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const fixtureRoot =
    'test/features/safe_walk/safety_data/crime_warning/fixtures/';
final now = DateTime.utc(2026, 11, 7, 12);
String fixture(String name) => File('$fixtureRoot$name').readAsStringSync();
CrimeWarningSourceInfo source([
  CrimeWarningDataset dataset = CrimeWarningDataset.womenChildren,
  String name = 'women_child',
]) => CrimeWarningSourceInfo.fromMetadata(
  fixture('${name}_metadata.json'),
  dataset: dataset,
  retrievedAt: now,
);
List<CrimeLocationRecord> records() =>
    parseCrimeWarningCsv(fixture('women_child.csv'), source: source()).records;
sw.Coordinates c(double lng, double lat) => sw.Coordinates(lat: lat, lng: lng);
List<sw.Coordinates> square(double x, double y, [double size = .001]) => [
  c(x, y),
  c(x + size, y),
  c(x + size, y + size),
  c(x, y + size),
  c(x, y),
];

// Artificial geometry for unit tests only; not the production park boundary.
VerifiedCrimeGeographicMatch fakeMatch({
  String? text,
  CrimeSpatialPrecision precision = CrimeSpatialPrecision.confirmedPublicPlace,
  CrimeLocationConfidence confidence = CrimeLocationConfidence.verified,
  double? accuracy = 20,
  DateTime? until,
  CrimeWarningGeometry? geometry,
}) => VerifiedCrimeGeographicMatch(
  sourceId: records()[10].sourceId,
  locationText: text ?? records()[10].locationText,
  geometry: geometry ?? CrimeWarningPolygonGeometry(rings: [square(121.5, 25)]),
  spatialPrecision: precision,
  confidence: confidence,
  geoSourceUrl: Uri.parse('https://example.org/artificial-unit-test-boundary'),
  geoSourceLicense: 'test fixture only',
  geoRetrievedAt: now,
  verifiedAt: now,
  validUntil: until ?? now.add(const Duration(days: 90)),
  accuracyMeters: accuracy,
  matchEvidence: 'Artificial test fixture, not real geography',
  limitations: const ['人工測試範圍，禁止作正式地圖資料'],
);

void main() {
  group('actual official samples', () {
    test('primary UTF-8 fields preserve all 22 text rows and no invented coordinates', () {
      final parsed = parseCrimeWarningCsv(
        fixture('women_child.csv'),
        source: source(),
      );
      expect(parsed.sourceRows, 22);
      expect(parsed.records, hasLength(22));
      expect(parsed.rejected, isEmpty);
      final park = parsed.records[10];
      expect(park.locationText, '中正區二二八和平公園');
      expect(park.sourceFields['管轄分局'], '中正第一分局');
      expect(park.sourceId, '${CrimeWarningDataset.womenChildren.id}:11');
      expect(park.category, CrimeWarningCategory.womenChildrenWarning);
      expect(park.observedPeriod, isNull);
      expect(park.sourceFileName, contains('115上半年'));
      expect(park.sourceResourceName, '臺北市婦幼安全警示地點統計');
      expect(park.dataUpdatedAt, DateTime.utc(2026, 7, 27, 2, 40, 10));
      expect(park.publishedAt, DateTime.utc(2022, 1, 20, 16));
      expect(park.license, contains('政府資料開放授權條款'));
      expect(park.sourceLimitations.join(), contains('沒有座標'));
      expect(() => park.sourceFields['x'] = '1', throwsUnsupportedError);
    });

    test('Big5 secondary sources use documented exact UTF-8 transcodes and preserve blurred places', () {
      final snatching = parseCrimeWarningCsv(
        fixture('snatching.csv'),
        source: source(CrimeWarningDataset.snatching, 'snatching'),
      );
      final robbery = parseCrimeWarningCsv(
        fixture('robbery.csv'),
        source: source(CrimeWarningDataset.robbery, 'robbery'),
      );
      expect(snatching.records, hasLength(54));
      expect(robbery.records, hasLength(26));
      expect(snatching.rejected, isEmpty);
      expect(robbery.rejected, isEmpty);
      expect(robbery.records.first.locationText, contains('31~60號'));
      expect(robbery.records.first.observedPeriod, '民國1070130 16~18');
      expect(robbery.records.first.sourceLimitations.join(), contains('模糊化'));
      final manifests = jsonDecode(fixture('source_manifest.json')) as List;
      expect(manifests.map((item) => item['rowCount']), [22, 54, 26]);
      expect(
        manifests.skip(1).every((item) => item['rawEncoding'] == 'cp950'),
        isTrue,
      );
      expect(File('${fixtureRoot}snatching.raw.big5').existsSync(), isTrue);
    });

    test('missing or duplicate official header fails whole import', () {
      expect(
        () => parseCrimeWarningCsv('編號,地點位置\n1,公園', source: source()),
        throwsA(isA<CrimeWarningFormatException>()),
      );
      expect(
        () => parseCrimeWarningCsv(
          fixture('women_child.csv').replaceFirst('備註', '編號'),
          source: source(),
        ),
        throwsA(isA<CrimeWarningFormatException>()),
      );
    });

    test('malformed quoted CSV rejected instead of repaired', () {
      expect(
        () => parseCrimeWarningCsv(
          '${fixture('women_child.csv')}"unterminated',
          source: source(),
        ),
        throwsA(isA<CrimeWarningFormatException>()),
      );
    });

    test('empty place, duplicate identity and wrong city are reported as rejected rows', () {
      final header = fixture('women_child.csv').split('\n').first;
      final parsed = parseCrimeWarningCsv(
        '$header\n1,63000,公園,分局,100,續列\n1,63000,公園,分局,100,續列\n2,63000,,分局,100,續列\n3,65000,公園,分局,100,續列',
        source: source(),
      );
      expect(parsed.records, hasLength(1));
      expect(parsed.rejected, hasLength(3));
    });

    test('header-only source is distinct from malformed source', () {
      final parsed = parseCrimeWarningCsv(
        fixture('women_child.csv').split('\n').first,
        source: source(),
      );
      expect(parsed.records, isEmpty);
      expect(parsed.sourceRows, 0);
    });

    test('metadata identity and resource must match official source', () {
      final metadata = fixture('women_child_metadata.json');
      expect(
        () => CrimeWarningSourceInfo.fromMetadata(
          metadata.replaceAll(CrimeWarningDataset.womenChildren.id, 'other'),
          dataset: CrimeWarningDataset.womenChildren,
          retrievedAt: now,
        ),
        throwsA(isA<CrimeWarningFormatException>()),
      );
      expect(
        () => CrimeWarningSourceInfo.fromMetadata(
          metadata.replaceAll(
            CrimeWarningDataset.womenChildren.resourceId,
            'other',
          ),
          dataset: CrimeWarningDataset.womenChildren,
          retrievedAt: now,
        ),
        throwsA(isA<CrimeWarningFormatException>()),
      );
    });

    test('source dates are strict and unknown license is not invented', () {
      expect(parseTaipeiSourceTime('2026-02-30 10:00:00'), isNull);
      expect(parseTaipeiSourceTime('2026-13-01'), isNull);
      expect(parseTaipeiSourceTime('not a date'), isNull);
      final metadata = fixture('women_child_metadata.json')
          .replaceAll('依政府資料開放授權條款-第1版', '未說明');
      expect(
        CrimeWarningSourceInfo.fromMetadata(
          metadata,
          dataset: CrimeWarningDataset.womenChildren,
          retrievedAt: now,
        ).license,
        isNull,
      );
    });
  });

  group('geographic evidence and model', () {
    test('reviewed official catalogue resolves only 228 park with unknown numeric accuracy', () async {
      final clock = DateTime.utc(2026, 11, 7, 16);
      final all = records();
      final resolver = createVerifiedTaipeiCrimeGeography();
      final zones = [
        for (final record in all)
          if (resolver.call(record) case final CrimeWarningZone zone) zone,
      ];
      expect(zones, hasLength(1));
      expect(
        zones.single.sourceId,
        '${CrimeWarningDataset.womenChildren.id}:11',
      );
      expect(zones.single.geometry, isA<CrimeWarningMultiPolygonGeometry>());
      expect(zones.single.accuracyMeters, isNull);
      expect(zones.single.geoSourceUrl.host, 'data.taipei');
      expect(
        zones.single.isEligibleForRouting(now: clock, mode: sw.DataMode.live),
        isTrue,
      );
      expect(
        zones.single.isEligibleForRouting(
          now: zones.single.validUntil,
          mode: sw.DataMode.live,
        ),
        isFalse,
      );
      final repository = OfficialCrimeWarningRepository(
        fetchText: (uri) async => fixture(
          uri.path.endsWith('dataset.view')
              ? 'women_child_metadata.json'
              : 'women_child.csv',
        ),
        now: () => clock,
        resolveGeometry: resolver.call,
      );
      final snapshot = await repository.getWarnings(mode: sw.DataMode.live);
      expect(snapshot.unlocatedRecordCount, 21);
      expect(snapshot.eligibleZones(now: clock), hasLength(1));
      final changed = parseCrimeWarningCsv(
        fixture('women_child.csv').replaceFirst('中正區二二八和平公園', '中正區二二八和平公園附近'),
        source: source(),
      ).records[10];
      expect(resolver.call(changed), isNull);
    });

    test('reviewed catalogue preserves original projected evidence and does not confuse CRS order', () {
      final manifest = reviewedTaipeiCrimeGeographyManifest();
      final provenance = manifest['provenance'] as Map;
      final original =
          jsonDecode(fixture('park_228_geographic_evidence.json')) as Map;
      expect(provenance['sourceCrs'], 'EPSG:3826');
      expect(provenance['geometryDataUpdatedAt'], isNull);
      expect(provenance['originalFeatureId'], 'L0101-5.123');
      expect(
        ((original['originalFeature'] as Map)['properties'] as Map)['id'],
        provenance['originalFeatureId'],
      );
      final zone = createVerifiedTaipeiCrimeGeography().call(records()[10])!;
      final polygon =
          (zone.geometry as CrimeWarningMultiPolygonGeometry).polygons.first;
      expect(polygon.rings.first.first.lng, inInclusiveRange(121.5, 121.6));
      expect(polygon.rings.first.first.lat, inInclusiveRange(25.0, 25.1));
      // Returned evidence is detached from the production catalogue.
      (manifest['matches'] as List).clear();
      expect(
        createVerifiedTaipeiCrimeGeography().call(records()[10]),
        isNotNull,
      );
    });

    test('GeoJSON [lng,lat] order is retained and polygon immutable', () {
      final polygon = CrimeWarningGeometry.fromGeoJson({
        'type': 'Polygon',
        'coordinates': [
          [
            [121.5, 25.0],
            [121.51, 25.0],
            [121.51, 25.01],
            [121.5, 25.0],
          ],
        ],
      }) as CrimeWarningPolygonGeometry;
      expect(polygon.rings.first.first.lng, 121.5);
      expect(polygon.rings.first.first.lat, 25);
      expect((polygon.toGeoJson()['coordinates'] as List).first.first, [
        121.5,
        25.0,
      ]);
      expect(() => polygon.rings.first.clear(), throwsUnsupportedError);
    });

    test('open, self-intersecting or zero-area geometry rejected', () {
      expect(
        () => CrimeWarningPolygonGeometry(
          rings: [
            [c(121, 25), c(121.1, 25), c(121, 25.1)],
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => CrimeWarningPolygonGeometry(
          rings: [
            [c(121, 25), c(121.1, 25), c(121.2, 25), c(121, 25)],
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => CrimeWarningPolygonGeometry(
          rings: [
            [
              c(121, 25),
              c(121.1, 25.1),
              c(121, 25.1),
              c(121.1, 25),
              c(121, 25),
            ],
          ],
        ),
        throwsArgumentError,
      );
    });

    test('holes outside outer ring, touching or overlapping are rejected', () {
      expect(
        () => CrimeWarningPolygonGeometry(
          rings: [square(121, 25, .01), square(122, 25)],
        ),
        throwsArgumentError,
      );
      expect(
        () => CrimeWarningPolygonGeometry(
          rings: [square(121, 25, .01), square(121, 25, .001)],
        ),
        throwsArgumentError,
      );
      expect(
        () => CrimeWarningPolygonGeometry(
          rings: [
            square(121, 25, .01),
            square(121.002, 25.002, .003),
            square(121.003, 25.003, .003),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        CrimeWarningPolygonGeometry(
          rings: [square(121, 25, .01), square(121.002, 25.002)],
        ).rings,
        hasLength(2),
      );
    });

    test('multipolygon and measured full-width road preserve geometry', () {
      final polygon = CrimeWarningPolygonGeometry(rings: [square(121, 25)]);
      final multi = CrimeWarningMultiPolygonGeometry(polygons: [polygon]);
      expect(
        CrimeWarningGeometry.fromGeoJson(multi.toGeoJson()),
        isA<CrimeWarningMultiPolygonGeometry>(),
      );
      final road = CrimeWarningRoadGeometry(
        points: [c(121, 25), c(121.001, 25)],
        corridorWidthMeters: 10,
      );
      expect(
        (CrimeWarningGeometry.fromGeoJson(
          road.toGeoJson(),
        ) as CrimeWarningRoadGeometry).corridorWidthMeters,
        10,
      );
      expect(
        () => CrimeWarningRoadGeometry(
          points: [c(121, 25)],
          corridorWidthMeters: 10,
        ),
        throwsArgumentError,
      );
    });

    test('exact source row and wording match, never fuzzy geocoding', () {
      final all = records();
      final resolver = VerifiedCrimeGeographicResolver([fakeMatch()]);
      expect(resolver.call(all[10]), isNotNull);
      expect(resolver.call(all[9]), isNull);
      expect(
        VerifiedCrimeGeographicResolver([fakeMatch(text: '近似公園')])
            .call(all[10]),
        isNull,
      );
    });

    test('unknown official park accuracy remains null while verified boundary is comparable', () {
      final zone = fakeMatch(accuracy: null).resolve(records()[10])!;
      expect(zone.accuracyMeters, isNull);
      expect(
        zone.isEligibleForRouting(now: now, mode: sw.DataMode.live),
        isTrue,
      );
    });

    test('approximate or uncertain records cannot enter exact routing', () {
      final row = records()[10];
      expect(
        fakeMatch(precision: CrimeSpatialPrecision.approximateArea)
            .resolve(row)!
            .isEligibleForRouting(now: now, mode: sw.DataMode.live),
        isFalse,
      );
      expect(
        fakeMatch(confidence: CrimeLocationConfidence.approximate)
            .resolve(row)!
            .isEligibleForRouting(now: now, mode: sw.DataMode.live),
        isFalse,
      );
      expect(
        fakeMatch(accuracy: 200)
            .resolve(row)!
            .isEligibleForRouting(now: now, mode: sw.DataMode.live),
        isFalse,
      );
      expect(
        fakeMatch()
            .resolve(row)!
            .isEligibleForRouting(now: now, mode: sw.DataMode.mock),
        isFalse,
      );
    });

    test('expired review or source excludes routing', () {
      final row = records()[10];
      final zone = fakeMatch().resolve(row)!;
      expect(
        zone.isEligibleForRouting(
          now: now.add(const Duration(days: 200)),
          mode: sw.DataMode.live,
        ),
        isFalse,
      );
      expect(
        fakeMatch(until: now.add(const Duration(hours: 1)))
            .resolve(row)!
            .isEligibleForRouting(
              now: now.add(const Duration(hours: 2)),
              mode: sw.DataMode.live,
            ),
        isFalse,
      );
    });

    test('historical blurred snatching cannot become precise avoidance even with a supplied shape', () {
      final historic = parseCrimeWarningCsv(
        fixture('snatching.csv'),
        source: source(CrimeWarningDataset.snatching, 'snatching'),
      ).records.first;
      final match = fakeMatch();
      final zone = CrimeWarningZone(
        record: historic,
        geometry: match.geometry,
        spatialPrecision: match.spatialPrecision,
        confidence: match.confidence,
        geoSourceUrl: match.geoSourceUrl,
        geoSourceLicense: match.geoSourceLicense,
        geoRetrievedAt: now,
        verifiedAt: now,
        validUntil: now.add(const Duration(days: 1)),
        accuracyMeters: 10,
        matchEvidence: 'Artificial test, not real geography',
        limitations: const [],
      );
      expect(
        zone.isEligibleForRouting(now: now, mode: sw.DataMode.live),
        isFalse,
      );
      expect(
        zone.routingExclusionReasons(now: now, mode: sw.DataMode.live).join(),
        contains('模糊化'),
      );
    });

    test('unresolved rows do not make a complete source equivalent to zero warnings', () {
      final all = records();
      final zone = fakeMatch().resolve(all[10])!;
      final snapshot = CrimeWarningSnapshot(
        records: all,
        zones: [zone],
        mode: sw.DataMode.live,
        retrievedAt: now,
        status: CrimeWarningDataStatus.ready,
        isComplete: true,
        warnings: const [],
      );
      expect(snapshot.unlocatedRecordCount, 21);
      expect(snapshot.eligibleZones(now: now), hasLength(1));
      expect(snapshot.isComplete, isTrue);
    });

    test('snapshot rejects foreign record objects and mixed source modes', () {
      final all = records();
      final zoneFromAnotherRead = fakeMatch().resolve(records()[10])!;
      expect(
        () => CrimeWarningSnapshot(
          records: all,
          zones: [zoneFromAnotherRead],
          mode: sw.DataMode.live,
          retrievedAt: now,
          status: CrimeWarningDataStatus.ready,
          isComplete: true,
          warnings: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => CrimeWarningSnapshot(
          records: all,
          zones: [],
          mode: sw.DataMode.mock,
          retrievedAt: now,
          status: CrimeWarningDataStatus.ready,
          isComplete: true,
          warnings: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('repository failure, cancellation and completeness', () {
    Future<String> fetch(Uri uri) async => fixture(
      uri.path.endsWith('dataset.view')
          ? 'women_child_metadata.json'
          : 'women_child.csv',
    );
    test('real sample parse gives 22 unlocated live warnings, no fallback geometry', () async {
      final repository = OfficialCrimeWarningRepository(
        fetchText: fetch,
        now: () => now,
      );
      final snapshot = await repository.getWarnings(mode: sw.DataMode.live);
      expect(snapshot.status, CrimeWarningDataStatus.ready);
      expect(snapshot.records, hasLength(22));
      expect(snapshot.zones, isEmpty);
      expect(snapshot.unlocatedRecordCount, 22);
      expect(snapshot.isComplete, isTrue);
    });

    test('resolver receives original rows and leaves unresolved source records visible', () async {
      final repository = OfficialCrimeWarningRepository(
        fetchText: fetch,
        now: () => now,
        resolveGeometry: VerifiedCrimeGeographicResolver([fakeMatch()]).call,
      );
      final snapshot = await repository.getWarnings(mode: sw.DataMode.live);
      expect(snapshot.zones, hasLength(1));
      expect(snapshot.unlocatedRecordCount, 21);
      expect(snapshot.warnings.join(), contains('21'));
    });

    test('Mock never reads the network', () async {
      var calls = 0;
      final repository = OfficialCrimeWarningRepository(
        fetchText: (uri) async {
          calls++;
          return '';
        },
      );
      await expectLater(
        repository.getWarnings(mode: sw.DataMode.mock),
        throwsA(isA<CrimeWarningDataUnavailable>()),
      );
      expect(calls, 0);
    });

    test(
      'metadata failure does not pretend empty data or reuse fixtures',
      () async {
        final repository = OfficialCrimeWarningRepository(
          fetchText: (uri) async => '<html>Error</html>',
        );
        await expectLater(
          repository.getWarnings(mode: sw.DataMode.live),
          throwsA(isA<CrimeWarningDataUnavailable>()),
        );
      },
    );

    test(
      'network failure is explicit and does not include rejected payload',
      () async {
        final repository = OfficialCrimeWarningRepository(
          fetchText: (uri) async => throw StateError('sensitive rejected body'),
        );
        try {
          await repository.getWarnings(mode: sw.DataMode.live);
          fail('must fail');
        } on CrimeWarningDataUnavailable catch (error) {
          expect(error.toString(), isNot(contains('sensitive')));
        }
      },
    );

    test('timeout is explicit, never fake success', () async {
      final repository = OfficialCrimeWarningRepository(
        fetchText: (uri) => Completer<String>().future,
        requestTimeout: const Duration(milliseconds: 5),
      );
      await expectLater(
        repository.getWarnings(mode: sw.DataMode.live),
        throwsA(isA<CrimeWarningDataUnavailable>()),
      );
    });

    test(
      'stale source retains text but cannot participate in routing',
      () async {
        final repository = OfficialCrimeWarningRepository(
          fetchText: fetch,
          now: () => DateTime.utc(2028),
        );
        expect(
          (await repository.getWarnings(mode: sw.DataMode.live)).status,
          CrimeWarningDataStatus.stale,
        );
      },
    );

    test('cache freshness is re-evaluated even before cache TTL', () async {
      var clock = DateTime.utc(2026, 7, 28, 1, 40, 10);
      var calls = 0;
      final repository = OfficialCrimeWarningRepository(
        fetchText: (uri) {
          calls++;
          return fetch(uri);
        },
        now: () => clock,
        maxSourceAge: const Duration(days: 1),
      );
      expect(
        (await repository.getWarnings(mode: sw.DataMode.live)).status,
        CrimeWarningDataStatus.ready,
      );
      clock = clock.add(const Duration(hours: 2));
      expect(
        (await repository.getWarnings(mode: sw.DataMode.live)).status,
        CrimeWarningDataStatus.stale,
      );
      expect(calls, 2);
    });

    test(
      'declared row mismatch and rejected rows mark partial source',
      () async {
        final repository = OfficialCrimeWarningRepository(
          fetchText: (uri) async => uri.path.endsWith('dataset.view')
              ? fixture('women_child_metadata.json')
              : fixture('women_child.csv').replaceFirst('1,63000,', '1,65000,'),
          now: () => now,
        );
        final snapshot = await repository.getWarnings(mode: sw.DataMode.live);
        expect(snapshot.records, hasLength(21));
        expect(snapshot.isComplete, isFalse);
      },
    );

    test('successful empty CSV is distinct from source failure and incomplete declared data', () async {
      final metadata = fixture('women_child_metadata.json')
          .replaceFirst('"number_of_data": 22', '"number_of_data": 0');
      final repository = OfficialCrimeWarningRepository(
        fetchText: (uri) async => uri.path.endsWith('dataset.view')
            ? metadata
            : fixture('women_child.csv').split('\n').first,
        now: () => now,
      );
      final snapshot = await repository.getWarnings(mode: sw.DataMode.live);
      expect(snapshot.status, CrimeWarningDataStatus.empty);
      expect(snapshot.isComplete, isTrue);
    });

    test('cancellation before request performs no network', () async {
      var calls = 0;
      final cancellation = _Cancellation()..cancel();
      final repository = OfficialCrimeWarningRepository(
        fetchText: (uri) async {
          calls++;
          return '';
        },
      );
      await expectLater(
        repository.getWarnings(
          mode: sw.DataMode.live,
          cancellation: cancellation,
        ),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(calls, 0);
    });

    test('cancellation while waiting ignores late source result and does not fill cache', () async {
      final waiting = Completer<String>();
      var calls = 0;
      final repository = OfficialCrimeWarningRepository(
        fetchText: (uri) {
          calls++;
          return calls == 1 ? waiting.future : fetch(uri);
        },
        now: () => now,
      );
      final cancellation = _Cancellation();
      final request = repository.getWarnings(
        mode: sw.DataMode.live,
        cancellation: cancellation,
      );
      cancellation.cancel();
      await expectLater(request, throwsA(isA<SafeWalkCancelledException>()));
      waiting.complete(fixture('women_child_metadata.json'));
      final snapshot = await repository.getWarnings(mode: sw.DataMode.live);
      expect(snapshot.records, hasLength(22));
      expect(calls, 3);
    });
  });
}

final class _Cancellation implements SafeWalkCancellation {
  final _done = Completer<void>();
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  bool get isCancelled => _done.isCompleted;
  @override
  Future<void> get whenCancelled => _done.future;
}
