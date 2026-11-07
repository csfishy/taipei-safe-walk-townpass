import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_live_check_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_route_geography.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial data only: round-number coordinates, no real record or address.
Map<String, Object?> body({int total = 1}) => {
  'interfaceVersion': 1,
  'snapshot': {
    'snapshotId': '00000000-0000-4000-8000-000000000000',
    'label': 'artificial',
    'asOfDate': '2026-09-30',
    'importedAt': '2026-10-02T00:00:00+00:00',
    'recordCount': 10,
  },
  'sources': [
    {
      'sourceKey': 'src_a',
      'datasetId': 'artificial-dataset',
      'resourceId': null,
      'name': '人工測試來源',
      'sourceUrl': 'https://example.test/dataset',
      'resourceUrl': 'https://example.test/resource.csv',
      'license': '人工測試授權',
      'retrievedAt': '2026-10-01T00:00:00+00:00',
      'dataUpdatedAt': null,
      'recordCount': 1,
    },
  ],
  'query': <String, Object?>{},
  'totalMatching': total,
  'records': [
    {
      'sourceKey': 'src_a',
      'sourceRecordId': 'row-1',
      'eventDate': '2026-05-01',
      'city': '臺北市',
      'district': null,
      'category': '人工類別',
      'locationText': '人工測試地點',
      'latitude': 25.0005,
      'longitude': 121.5005,
      'spatialPrecision': 'address_reference',
      'confidence': 'high',
      'coordinateStatus': 'reference_geocoded',
    },
  ],
};

sw.RouteCandidate candidate(
  String id,
  List<List<double>> lngLat, {
  bool verified = true,
  String provider = 'osrm-foot (test)',
}) => sw.RouteCandidate(
  id: id,
  kind: sw.RouteKind.direct,
  geometry: sw.LineString(
    coordinates: [for (final p in lngLat) (longitude: p[0], latitude: p[1])],
  ),
  distanceMeters: 300,
  durationSeconds: 240,
  viaPointIds: const [],
  provider: provider,
  walkingNetworkVerified: verified,
  explanations: const ['依 OpenStreetMap 步行路網計算'],
  warnings: const ['僅反映路網，不保證路段安全'],
);

final through = candidate('osrm-direct', [
  [121.4990, 25.0005],
  [121.5020, 25.0005],
]);
final around = candidate('osrm-alt-1', [
  [121.4990, 24.9990],
  [121.5020, 24.9990],
]);

sw.RouteSuccess success(
  List<sw.RouteCandidate> routes, {
  sw.DataMode mode = sw.DataMode.live,
}) => sw.RouteSuccess(
  requestId: 'r1',
  mode: mode,
  generatedAt: '2026-11-08T00:00:00Z',
  routes: routes,
  warnings: const ['人工測試路線'],
);

RouteReferenceArea area() => RouteReferenceArea(
  id: 'area-1',
  label: '人工範圍',
  evidence: '人工測試邊界',
  ring: const [
    (longitude: 121.5, latitude: 25.0),
    (longitude: 121.501, latitude: 25.0),
    (longitude: 121.501, latitude: 25.001),
    (longitude: 121.5, latitude: 25.001),
  ],
);

CrimeReferenceRepository repo(
  FutureOr<CrimeReferenceHttpResponse> Function(Map<String, Object?>) answer,
) => CrimeReferenceRepository(
  transport: (args) async => answer(args),
  now: () => DateTime.utc(2026, 11, 8),
);

CrimeReferenceRepository okRepo([List<Map<String, Object?>>? seen]) =>
    repo((args) {
      seen?.add(args);
      return CrimeReferenceHttpResponse(200, jsonEncode(body()));
    });

void main() {
  group('CrimeRouteAlertService', () {
    test('reference points are counted, never compared as areas', () async {
      final seen = <Map<String, Object?>>[];
      final alert = await CrimeRouteAlertService(repository: okRepo(seen))
          .assess(success([through]));
      expect(alert.referenceOutcome, CrimeRouteReferenceOutcome.answered);
      expect(alert.comparison.status, RouteAreaComparisonStatus.noReliableArea);
      expect(alert.geography!.pointReferenceCount, 1);
      expect(alert.geography!.reliableAreaCount, 0);
      final args = seen.single;
      expect(args['p_min_lat'], closeTo(25.0005 - 0.002, 1e-9));
      expect(args['p_max_lng'], closeTo(121.502 + 0.002, 1e-9));
      expect(args['p_limit'], crimeReferenceMaxLimit);
    });

    test('reviewed areas are compared on unchanged candidates', () async {
      final route = success([through, around]);
      final before = route.toJson().toString();
      final alert = await CrimeRouteAlertService(
        repository: okRepo(),
        reviewedAreas: [area()],
      ).assess(route);
      expect(
        alert.comparison.status,
        RouteAreaComparisonStatus.alternativeAvailable,
      );
      expect(route.toJson().toString(), before);
    });

    test('mock or unverified routes are rejected, not compared', () async {
      final service = CrimeRouteAlertService(repository: okRepo());
      expect(
        () => service.assess(success([through], mode: sw.DataMode.mock)),
        throwsArgumentError,
      );
      expect(
        () => service.assess(
          success([
            candidate('x', [
              [121.5, 25.0],
              [121.501, 25.0],
            ], verified: false),
          ]),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.assess(
          success([
            candidate('x', [
              [121.5, 25.0],
              [121.501, 25.0],
            ], provider: 'mock-demo'),
          ]),
        ),
        throwsArgumentError,
      );
    });

    test('unconfigured and failed queries are explicit states', () async {
      final unconfigured = await CrimeRouteAlertService(
        repository: CrimeReferenceRepository(transport: null),
      ).assess(success([through]));
      expect(
        unconfigured.referenceOutcome,
        CrimeRouteReferenceOutcome.notConfigured,
      );
      expect(unconfigured.reference, isNull);

      final failed = await CrimeRouteAlertService(
        repository: repo(
          (_) => CrimeReferenceHttpResponse(404, '{"code":"PGRST202"}'),
        ),
      ).assess(success([through]));
      expect(failed.referenceOutcome, CrimeRouteReferenceOutcome.failed);
      expect(failed.failure, CrimeReferenceFailure.interfaceMissing);
    });

    test('route extent beyond the server limit is not queried', () async {
      final seen = <Map<String, Object?>>[];
      final alert = await CrimeRouteAlertService(repository: okRepo(seen))
          .assess(
            success([
              candidate('long', [
                [121.0, 25.0],
                [121.6, 25.0],
              ]),
            ]),
          );
      expect(
        alert.referenceOutcome,
        CrimeRouteReferenceOutcome.routeExtentTooLarge,
      );
      expect(seen, isEmpty);
    });

    test('notice text never claims safety and keeps limits', () async {
      for (final areas in [
        const <RouteReferenceArea>[],
        [area()],
      ]) {
        for (final routes in [
          [through],
          [around],
          [through, around],
        ]) {
          final alert = await CrimeRouteAlertService(
            repository: okRepo(),
            reviewedAreas: areas,
          ).assess(success(routes));
          final text = crimeRouteAlertLines(alert).join('\n');
          // "安全" may only appear negated ("不代表…安全", "…安全保證").
          final unsafeClaims = text
              .replaceAll('不代表路線安全', '')
              .replaceAll('不代表安全', '')
              .replaceAll('或安全保證', '');
          expect(unsafeClaims, isNot(contains('安全')));
          expect(text, isNot(contains('避開危險')));
          expect(text, contains('不是精確案發點'));
          for (final limit in crimeReferenceLimitations) {
            expect(text, contains(limit));
          }
        }
      }
    });
  });

  test('M4 geography summary: points and missing coordinates', () {
    final result = CrimeReferenceResult(
      snapshot: const CrimeReferenceSnapshot(
        snapshotId: 's',
        label: 'l',
        asOfDate: '2026-09-30',
        importedAt: '2026-10-02T00:00:00Z',
        recordCount: 3,
      ),
      sources: const [],
      totalMatching: 3,
      records: const [],
      retrievedAt: '2026-11-08T00:00:00Z',
    );
    final summary = summarizeCrimeReferenceRouteGeography(result);
    expect(summary.reliableAreaCount, 0);
    expect(summary.isPartialPage, isTrue);
  });

  group('CrimeRouteAlertLiveCheckPage', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      required _FakeRoutes routes,
      CrimeRouteAlertService? alerts,
      sw.LocationResult? location,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CrimeRouteAlertLiveCheckPage(
            platform: _FakePlatform(location ?? _gps()),
            createRouteService: (hasConsent) => routes..hasConsent = hasConsent,
            alertService:
                alerts ?? CrimeRouteAlertService(repository: okRepo()),
            showMap: false,
            clock: () => DateTime.utc(2026, 11, 8),
          ),
        ),
      );
    }

    Future<void> fillAndPlan(
      WidgetTester tester, {
      bool referenceConsent = true,
    }) async {
      await tester.tap(find.byKey(const Key('crime-route-locate')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crime-route-dest-lat')),
        '25.001',
      );
      await tester.enterText(
        find.byKey(const Key('crime-route-dest-lng')),
        '121.502',
      );
      await tester.tap(find.byKey(const Key('crime-route-routing-consent')));
      if (referenceConsent) {
        await tester.tap(
          find.byKey(const Key('crime-route-reference-consent')),
        );
      }
      await tester.pump();
      await tester.tap(find.byKey(const Key('crime-route-plan')));
      await tester.pumpAndSettle();
    }

    testWidgets('real route -> query -> explicit no-reliable-area notice', (
      tester,
    ) async {
      final routes = _FakeRoutes(success([through]));
      await pumpPage(tester, routes: routes);
      await fillAndPlan(tester);
      expect(routes.consentAtCall, isTrue);
      expect(routes.lastRequest!.mode, sw.DataMode.live);
      expect(find.textContaining('沒有經核對的可靠地理範圍'), findsOneWidget);
      expect(find.textContaining('路線維持 OSRM 原樣'), findsOneWidget);
      expect(find.textContaining('1 筆犯罪參考紀錄'), findsOneWidget);
      expect(find.textContaining('資料截至 2026-09-30'), findsOneWidget);
      expect(find.textContaining('更新 來源未提供'), findsOneWidget);
    });

    testWidgets('plan stays disabled without routing consent', (tester) async {
      final routes = _FakeRoutes(success([through]));
      await pumpPage(tester, routes: routes);
      await tester.tap(find.byKey(const Key('crime-route-locate')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crime-route-dest-lat')),
        '25.001',
      );
      await tester.enterText(
        find.byKey(const Key('crime-route-dest-lng')),
        '121.502',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('crime-route-plan')));
      await tester.pumpAndSettle();
      expect(routes.lastRequest, isNull);
    });

    testWidgets('without reference consent the route shows, no comparison', (
      tester,
    ) async {
      final seen = <Map<String, Object?>>[];
      final routes = _FakeRoutes(success([through]));
      await pumpPage(
        tester,
        routes: routes,
        alerts: CrimeRouteAlertService(repository: okRepo(seen)),
      );
      await fillAndPlan(tester, referenceConsent: false);
      expect(find.textContaining('osrm-direct'), findsOneWidget);
      expect(find.textContaining('本次未比對'), findsOneWidget);
      expect(seen, isEmpty);
    });

    testWidgets('route failure is shown, nothing is substituted', (
      tester,
    ) async {
      final routes = _FakeRoutes(
        sw.RouteFailure(
          requestId: 'x',
          mode: sw.DataMode.live,
          generatedAt: '2026-11-08T00:00:00Z',
          status: sw.RouteFailureStatus.providerUnavailable,
          reason: '路線服務暫時無法使用',
          warnings: const ['沒有產生路線'],
        ),
      );
      await pumpPage(tester, routes: routes);
      await fillAndPlan(tester);
      expect(find.text('路線服務暫時無法使用'), findsOneWidget);
      expect(find.textContaining('犯罪參考紀錄'), findsNothing);
    });

    testWidgets('location failure leaves no origin', (tester) async {
      final routes = _FakeRoutes(success([through]));
      await pumpPage(
        tester,
        routes: routes,
        location: sw.LocationFailure(
          status: sw.LocationFailureStatus.denied,
          message: '定位權限未允許',
        ),
      );
      await tester.tap(find.byKey(const Key('crime-route-locate')));
      await tester.pumpAndSettle();
      expect(find.text('定位權限未允許'), findsOneWidget);
      expect(find.text('尚未取得起點。'), findsOneWidget);
    });
  });
}

sw.LocationResult _gps() => sw.LocationSuccess(
  position: sw.Position.fromJson({
    'schemaVersion': '1.0.0',
    'coordinates': {'lat': 25.0005, 'lng': 121.499},
    'source': 'gps',
    'accuracyMeters': 10.0,
    'observedAt': '2026-11-08T00:00:00Z',
  }),
);

final class _FakePlatform implements PlatformService {
  _FakePlatform(this.result);

  final sw.LocationResult result;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    expect(mode, sw.DataMode.live);
    expect(userInitiated, isTrue);
    return result;
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) => throw UnimplementedError();
}

final class _FakeRoutes implements RouteService {
  _FakeRoutes(this.result);

  final sw.RouteResult result;
  bool Function()? hasConsent;
  bool? consentAtCall;
  sw.RouteRequest? lastRequest;

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    lastRequest = request;
    consentAtCall = hasConsent?.call();
    return result;
  }
}
