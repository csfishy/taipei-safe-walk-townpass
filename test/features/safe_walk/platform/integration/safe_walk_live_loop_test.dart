import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_live_loop_controller.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_live_loop_pages.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial data only: round-number coordinates, no real place or record.
final _now = DateTime.utc(2026, 11, 8, 12);
final _destination = sw.Coordinates(lat: 25.001, lng: 121.501);

sw.Position _fix({
  String source = 'gps',
  double? accuracy = 10,
  DateTime? at,
}) => sw.Position.fromJson({
  'schemaVersion': '1.0.0',
  'coordinates': {'lat': 25.0, 'lng': 121.5},
  'source': source,
  'accuracyMeters': accuracy,
  'observedAt': (at ?? _now).toIso8601String(),
});

sw.LocationResult _ok([sw.Position? p]) =>
    sw.LocationSuccess(position: p ?? _fix());

sw.LocationResult _locFail(String status) =>
    sw.LocationResult.fromJson({'status': status, 'message': '人工失敗'});

final class _Platform implements PlatformService {
  _Platform([this.answer]);
  Future<sw.LocationResult> Function()? answer;
  int calls = 0;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    calls++;
    expect(mode, sw.DataMode.live);
    expect(userInitiated, isTrue);
    return (answer ?? () async => _ok())();
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async => sw.EmergencyActionResult.fromJson({
    'schemaVersion': '1.0.0',
    'channel': channel.wireValue,
    'action': 'not_configured',
    'officialReceipt': null,
    'message': '人工：未聯絡任何人。',
  });
}

sw.RouteCandidate _candidate({
  String id = 'osrm-direct',
  String provider = 'osrm-foot (test)',
  bool verified = true,
}) => sw.RouteCandidate(
  id: id,
  kind: sw.RouteKind.direct,
  geometry: sw.LineString(
    coordinates: [
      (longitude: 121.5, latitude: 25.0),
      (longitude: 121.501, latitude: 25.001),
    ],
  ),
  distanceMeters: 150,
  durationSeconds: 120,
  viaPointIds: const [],
  provider: provider,
  walkingNetworkVerified: verified,
  explanations: const ['依 OpenStreetMap 步行路網計算'],
  warnings: const ['僅反映路網，不保證路段安全'],
);

sw.RouteResult _success(
  sw.RouteRequest r, {
  sw.DataMode? mode,
  sw.RouteCandidate? candidate,
}) => sw.RouteSuccess(
  requestId: r.requestId,
  mode: mode ?? r.mode,
  generatedAt: _now.toIso8601String(),
  routes: [candidate ?? _candidate()],
  warnings: const ['路線僅反映所用路網'],
);

sw.RouteResult _routeFail(sw.RouteRequest r, sw.RouteFailureStatus status) =>
    sw.RouteFailure(
      requestId: r.requestId,
      mode: r.mode,
      generatedAt: _now.toIso8601String(),
      status: status,
      reason: '人工路線失敗',
      warnings: const ['沒有產生路線'],
    );

final class _Routes implements RouteService {
  _Routes([this.answer]);
  Future<sw.RouteResult> Function(sw.RouteRequest r)? answer;
  final requests = <sw.RouteRequest>[];

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    requests.add(request);
    return (answer ?? (r) async => _success(r))(request);
  }
}

Map<String, Object?> _body({int total = 1}) => {
  'interfaceVersion': 1,
  'snapshot': {
    'snapshotId': '00000000-0000-4000-8000-000000000000',
    'label': 'artificial',
    'asOfDate': '2026-09-30',
    'importedAt': '2026-10-02T00:00:00+00:00',
    'recordCount': total,
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
      'recordCount': total,
    },
  ],
  'query': <String, Object?>{},
  'totalMatching': total,
  'records': total == 0
      ? const []
      : [
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

final class _Db {
  Future<CrimeReferenceHttpResponse> Function()? answer;
  final calls = <Map<String, Object?>>[];

  CrimeReferenceRepository get repository => CrimeReferenceRepository(
    transport: (args, {cancellation}) {
      calls.add(args);
      return (answer ??
          () async => CrimeReferenceHttpResponse(200, jsonEncode(_body())))();
    },
    now: () => _now,
  );
}

RouteReferenceArea _area() => RouteReferenceArea(
  id: 'area-1',
  label: '人工範圍',
  evidence: '人工測試邊界證據',
  ring: const [
    (longitude: 121.5, latitude: 25.0),
    (longitude: 121.501, latitude: 25.0),
    (longitude: 121.501, latitude: 25.001),
    (longitude: 121.5, latitude: 25.001),
  ],
);

SafeWalkLiveLoopController _loop({
  _Platform? platform,
  _Routes? routes,
  _Db? db,
  DateTime Function()? clock,
  Duration timeout = const Duration(seconds: 5),
}) => SafeWalkLiveLoopController(
  platform: platform ?? _Platform(),
  routeService: routes ?? _Routes(),
  alertService: CrimeRouteAlertService(repository: (db ?? _Db()).repository),
  locationTimeout: timeout,
  routeTimeout: timeout,
  referenceTimeout: timeout,
  clock: clock ?? () => _now,
);

Future<void> _ready(
  SafeWalkLiveLoopController c, {
  bool reference = true,
}) async {
  c
    ..setLocationConsent(true)
    ..setRoutingConsent(true)
    ..setReferenceConsent(reference);
  await c.locate();
  c.setDestination(_destination);
}

void main() {
  group('live loop: consent and the connected flow', () {
    test('no GPS read without location consent', () async {
      final platform = _Platform();
      final c = _loop(platform: platform);
      await c.locate();
      expect(platform.calls, 0);
      expect(c.failure, LiveLoopFailure.locationConsentMissing);
      expect(c.origin, isNull);
    });

    test('location consent alone does not send coordinates to OSRM', () async {
      final routes = _Routes();
      final c = _loop(routes: routes)..setLocationConsent(true);
      await c.locate();
      c.setDestination(_destination);
      expect(c.canPlan, isFalse);
      await c.planRoute();
      expect(routes.requests, isEmpty);
      expect(c.failure, LiveLoopFailure.routingConsentMissing);
    });

    test('consents -> GPS -> destination -> OSRM -> crime reference', () async {
      final routes = _Routes();
      final db = _Db();
      final c = _loop(routes: routes, db: db);
      await _ready(c);
      expect(c.origin!.source, sw.PositionSource.gps);
      await c.planRoute();
      expect(c.stage, LiveLoopStage.ready);
      expect(c.failure, isNull);
      final request = routes.requests.single;
      expect(request.mode, sw.DataMode.live);
      expect(request.destination.lat, _destination.lat);
      // Geometry is kept as returned by the provider.
      expect(
        c.route!.routes.single.geometry.coordinates,
        _candidate().geometry.coordinates,
      );
      expect(c.referenceState, LiveLoopReferenceState.done);
      expect(c.alert!.referenceOutcome, CrimeRouteReferenceOutcome.answered);
      expect(db.calls, hasLength(1));
    });

    test('without reference consent the database is not queried', () async {
      final db = _Db();
      final c = _loop(db: db);
      await _ready(c, reference: false);
      await c.planRoute();
      expect(c.route, isNotNull);
      expect(c.referenceState, LiveLoopReferenceState.notConsented);
      expect(db.calls, isEmpty);
    });
  });

  group('live loop: explicit failures, never Mock', () {
    test('denied permission', () async {
      final c = _loop(platform: _Platform(() async => _locFail('denied')))
        ..setLocationConsent(true);
      await c.locate();
      expect(c.failure, LiveLoopFailure.locationDenied);
      expect(c.origin, isNull);
    });

    test('location timeout from a platform that never answers', () async {
      final c = _loop(
        platform: _Platform(() => Completer<sw.LocationResult>().future),
        timeout: const Duration(milliseconds: 20),
      )..setLocationConsent(true);
      await c.locate();
      expect(c.failure, LiveLoopFailure.locationTimeout);
      expect(c.origin, isNull);
    });

    test('a demo or inaccurate position is never used as the origin', () async {
      for (final p in [_fix(source: 'mock'), _fix(accuracy: 500)]) {
        final c = _loop(platform: _Platform(() async => _ok(p)))
          ..setLocationConsent(true);
        await c.locate();
        expect(c.failure, LiveLoopFailure.locationNotLive);
        expect(c.origin, isNull);
      }
    });

    test('route failures stay failures with no route shown', () async {
      for (final (status, expected) in [
        (sw.RouteFailureStatus.noRoute, LiveLoopFailure.noRoute),
        (
          sw.RouteFailureStatus.providerUnavailable,
          LiveLoopFailure.routeUnavailable,
        ),
      ]) {
        final db = _Db();
        final c = _loop(
          routes: _Routes((r) async => _routeFail(r, status)),
          db: db,
        );
        await _ready(c);
        await c.planRoute();
        expect(c.failure, expected);
        expect(c.route, isNull);
        expect(db.calls, isEmpty);
      }
    });

    test('offline transport error becomes routeUnavailable', () async {
      final c = _loop(
        routes: _Routes((_) => Future.error(const SocketExceptionLike())),
      );
      await _ready(c);
      await c.planRoute();
      expect(c.failure, LiveLoopFailure.routeUnavailable);
      expect(c.route, isNull);
    });

    test('route timeout', () async {
      final c = _loop(
        routes: _Routes((_) => Completer<sw.RouteResult>().future),
        timeout: const Duration(milliseconds: 20),
      );
      c
        ..setLocationConsent(true)
        ..setRoutingConsent(true);
      await c.locate();
      c.setDestination(_destination);
      await c.planRoute();
      expect(c.failure, LiveLoopFailure.routeTimeout);
      expect(c.route, isNull);
    });

    test('a demo route from the provider is rejected, not shown', () async {
      for (final routes in [
        _Routes((r) async => _success(r, mode: sw.DataMode.mock)),
        _Routes(
          (r) async =>
              _success(r, candidate: _candidate(provider: 'mock-demo')),
        ),
        _Routes(
          (r) async => _success(r, candidate: _candidate(verified: false)),
        ),
      ]) {
        final c = _loop(routes: routes);
        await _ready(c);
        await c.planRoute();
        expect(c.failure, LiveLoopFailure.routeNotLive);
        expect(c.route, isNull);
      }
    });

    test('a stale origin needs a new explicit locate', () async {
      var now = _now;
      final platform = _Platform();
      final routes = _Routes();
      final c = _loop(platform: platform, routes: routes, clock: () => now);
      await _ready(c);
      now = now.add(const Duration(minutes: 2));
      await c.planRoute();
      expect(c.failure, LiveLoopFailure.staleOrigin);
      expect(c.origin, isNull);
      expect(routes.requests, isEmpty);
      expect(platform.calls, 1);
    });

    test('crime reference timeout keeps the real route, says so', () async {
      final db = _Db()
        ..answer = () => Completer<CrimeReferenceHttpResponse>().future;
      final c = _loop(db: db, timeout: const Duration(milliseconds: 20));
      await _ready(c);
      await c.planRoute();
      expect(c.route, isNotNull);
      expect(c.referenceState, LiveLoopReferenceState.timeout);
      expect(c.alert, isNull);
    });

    test('unconfigured database is explicit, not demo data', () async {
      final c = SafeWalkLiveLoopController(
        platform: _Platform(),
        routeService: _Routes(),
        alertService: CrimeRouteAlertService(
          repository: CrimeReferenceRepository(transport: null),
        ),
        clock: () => _now,
      );
      await _ready(c);
      await c.planRoute();
      expect(
        c.alert!.referenceOutcome,
        CrimeRouteReferenceOutcome.notConfigured,
      );
      expect(c.alert!.reference, isNull);
    });

    test('empty database answer is a real zero', () async {
      final db = _Db()
        ..answer = () async =>
            CrimeReferenceHttpResponse(200, jsonEncode(_body(total: 0)));
      final c = _loop(db: db);
      await _ready(c);
      await c.planRoute();
      expect(c.alert!.reference!.totalMatching, 0);
      expect(
        c.alert!.comparison.status,
        RouteAreaComparisonStatus.noReliableArea,
      );
    });
  });

  group('live loop: cancel, background, exit and stale results', () {
    test(
      'provider cancellation ends GPS and route work and permits retry',
      () async {
        final platform = _Platform(
          () async => throw const SafeWalkCancelledException(),
        );
        final routes = _Routes(
          (_) async => throw const SafeWalkCancelledException(),
        );
        final c = _loop(platform: platform, routes: routes)
          ..setLocationConsent(true);
        await c.locate();
        expect(c.failure, LiveLoopFailure.cancelled);
        expect(c.busy, isFalse);
        platform.answer = null;
        await _ready(c);
        await c.planRoute();
        expect(c.failure, LiveLoopFailure.cancelled);
        expect(c.canPlan, isTrue);
        routes.answer = null;
        await c.planRoute();
        expect(c.stage, LiveLoopStage.ready);
      },
    );

    test(
      'provider cancellation ends reference assessment and permits retry',
      () async {
        final db = _Db()
          ..answer = () async => throw const SafeWalkCancelledException();
        final c = _loop(db: db);
        await _ready(c);
        await c.planRoute();
        expect(c.failure, LiveLoopFailure.cancelled);
        expect(c.route, isNull);
        expect(c.canPlan, isTrue);
        db.answer = null;
        await c.planRoute();
        expect(c.stage, LiveLoopStage.ready);
      },
    );

    test(
      'revoking consent in a listener prevents the provider from starting',
      () async {
        final platform = _Platform();
        final c = _loop(platform: platform)..setLocationConsent(true);
        c.addListener(() {
          if (c.stage == LiveLoopStage.locating) c.setLocationConsent(false);
        });
        await c.locate();
        expect(platform.calls, 0);
        expect(c.stage, LiveLoopStage.idle);
      },
    );

    test(
      'cancel drops in-flight routing; the late result is ignored',
      () async {
        final pending = Completer<sw.RouteResult>();
        final routes = _Routes((_) => pending.future);
        final c = _loop(routes: routes);
        await _ready(c);
        final plan = c.planRoute();
        expect(c.stage, LiveLoopStage.routing);
        c.cancel();
        expect(c.failure, LiveLoopFailure.cancelled);
        pending.complete(_success(routes.requests.single));
        await plan;
        expect(c.route, isNull);
        expect(c.failure, LiveLoopFailure.cancelled);
      },
    );

    test('a newer request wins over a slower older one', () async {
      final first = Completer<sw.RouteResult>();
      final routes = _Routes();
      var n = 0;
      routes.answer = (r) =>
          n++ == 0 ? first.future : Future.value(_success(r));
      final c = _loop(routes: routes);
      await _ready(c);
      final old = c.planRoute();
      c.setDestination(sw.Coordinates(lat: 25.002, lng: 121.502));
      await c.planRoute();
      final kept = c.route;
      expect(kept!.requestId, routes.requests.last.requestId);
      first.complete(_success(routes.requests.first));
      await old;
      expect(identical(c.route, kept), isTrue);
    });

    test('changing destination clears the old route', () async {
      final c = _loop();
      await _ready(c);
      await c.planRoute();
      expect(c.route, isNotNull);
      c.setDestination(sw.Coordinates(lat: 25.002, lng: 121.502));
      expect(c.route, isNull);
      expect(c.alert, isNull);
    });

    test(
      'late GPS after background is discarded; resume reads nothing',
      () async {
        final pending = Completer<sw.LocationResult>();
        final platform = _Platform(() => pending.future);
        final c = _loop(platform: platform)..setLocationConsent(true);
        final locating = c.locate();
        c.setForeground(false);
        expect(c.failure, LiveLoopFailure.backgrounded);
        pending.complete(_ok());
        await locating;
        expect(c.origin, isNull);
        c.setForeground(true);
        await Future<void>.delayed(Duration.zero);
        expect(platform.calls, 1);
        expect(c.failure, LiveLoopFailure.backgrounded);
      },
    );

    test('background during routing drops the position and route', () async {
      final pending = Completer<sw.RouteResult>();
      final routes = _Routes((_) => pending.future);
      final c = _loop(routes: routes);
      await _ready(c);
      final plan = c.planRoute();
      c.setForeground(false);
      pending.complete(_success(routes.requests.single));
      await plan;
      expect(c.route, isNull);
      expect(c.origin, isNull);
      expect(c.canPlan, isFalse);
    });

    test('revoking routing consent cancels and clears the route', () async {
      final c = _loop();
      await _ready(c);
      await c.planRoute();
      c.setRoutingConsent(false);
      expect(c.route, isNull);
      expect(c.origin, isNotNull);
    });

    test('close resets consents, origin and destination', () async {
      final c = _loop();
      await _ready(c);
      await c.planRoute();
      c.close();
      expect(
        c.locationConsent || c.routingConsent || c.referenceConsent,
        isFalse,
      );
      expect(c.origin, isNull);
      expect(c.destination, isNull);
      expect(c.route, isNull);
    });
  });

  group('report status: database on entry, evidenced areas only', () {
    test(
      'provider cancellation leaves loading and foreground gates retry',
      () async {
        final db = _Db()
          ..answer = () async => throw const SafeWalkCancelledException();
        final c = SafeWalkReportStatusController(repository: db.repository);
        await c.load();
        expect(c.stage, ReportStatusStage.cancelled);
        c.setForeground(false);
        db.answer = null;
        await c.load();
        expect(db.calls, hasLength(1));
        c.setForeground(true);
        expect(db.calls, hasLength(1));
        await c.load();
        expect(c.stage, ReportStatusStage.answered);
      },
    );

    test('answered shows reviewed areas, never reference points', () async {
      final db = _Db();
      final c = SafeWalkReportStatusController(
        repository: db.repository,
        reviewedAreas: [_area()],
      );
      expect(c.evidencedAreas, isEmpty);
      await c.load();
      expect(c.stage, ReportStatusStage.answered);
      expect(c.evidencedAreas.single.id, 'area-1');
      // The status query sends no position.
      expect(db.calls.single['p_min_lat'], isNull);
      expect(db.calls.single['p_limit'], 1);
    });

    test('not configured / failed / timeout / cancelled', () async {
      final none = SafeWalkReportStatusController(
        repository: CrimeReferenceRepository(transport: null),
        reviewedAreas: [_area()],
      );
      await none.load();
      expect(none.stage, ReportStatusStage.notConfigured);
      expect(none.evidencedAreas, isEmpty);

      final db = _Db()
        ..answer = () async => const CrimeReferenceHttpResponse(503, '{}');
      final failed = SafeWalkReportStatusController(repository: db.repository);
      await failed.load();
      expect(failed.stage, ReportStatusStage.failed);

      final slow = _Db()
        ..answer = () => Completer<CrimeReferenceHttpResponse>().future;
      final timeout = SafeWalkReportStatusController(
        repository: slow.repository,
        timeout: const Duration(milliseconds: 20),
      );
      await timeout.load();
      expect(timeout.stage, ReportStatusStage.timeout);

      final pending = Completer<CrimeReferenceHttpResponse>();
      final late = _Db()..answer = () => pending.future;
      final cancelled = SafeWalkReportStatusController(
        repository: late.repository,
      );
      final loading = cancelled.load();
      cancelled.cancel();
      pending.complete(CrimeReferenceHttpResponse(200, jsonEncode(_body())));
      await loading;
      expect(cancelled.stage, ReportStatusStage.cancelled);
      expect(cancelled.result, isNull);
    });

    test('a re-entry supersedes an older, slower query', () async {
      final first = Completer<CrimeReferenceHttpResponse>();
      var n = 0;
      final db = _Db()
        ..answer = () => n++ == 0
            ? first.future
            : Future.value(
                CrimeReferenceHttpResponse(200, jsonEncode(_body(total: 0))),
              );
      final c = SafeWalkReportStatusController(repository: db.repository);
      final old = c.load();
      await c.load();
      expect(c.result!.totalMatching, 0);
      first.complete(CrimeReferenceHttpResponse(200, jsonEncode(_body())));
      await old;
      expect(c.result!.totalMatching, 0);
    });
  });

  group('report status depth: source, status, scope, date, limits', () {
    Future<void> pumpPage(
      WidgetTester t,
      SafeWalkReportStatusController c,
    ) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        MaterialApp(
          home: SafeWalkReportStatusPage(
            controller: c,
            onBack: () {},
            showMap: false,
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Finder status(String text) => find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.key == const Key('report-query-status') &&
          (w.data ?? '').contains(text),
    );

    testWidgets('loading', (t) async {
      final pending = Completer<CrimeReferenceHttpResponse>();
      final db = _Db()..answer = () => pending.future;
      final c = SafeWalkReportStatusController(
        repository: db.repository,
        clock: () => _now,
      );
      await t.pumpWidget(
        MaterialApp(
          home: SafeWalkReportStatusPage(
            controller: c,
            onBack: () {},
            showMap: false,
          ),
        ),
      );
      await t.pump();
      expect(c.queryStatus, ReportQueryStatus.loading);
      expect(status('查詢中'), findsOneWidget);
      pending.complete(CrimeReferenceHttpResponse(200, jsonEncode(_body())));
      await t.pumpAndSettle();
    });

    testWidgets('ok: per-item source, scope, date and limits', (t) async {
      final c = SafeWalkReportStatusController(
        repository: _Db().repository,
        reviewedAreas: [_area()],
        clock: () => _now,
      );
      await pumpPage(t, c);
      expect(c.queryStatus, ReportQueryStatus.ok);
      expect(status('正常'), findsOneWidget);
      expect(find.textContaining('來源：人工測試來源'), findsOneWidget);
      expect(find.textContaining('截至 2026-09-30'), findsWidgets);
      expect(find.textContaining('僅此已核對邊界內（人工範圍）'), findsOneWidget);
      expect(find.textContaining('不是即時資訊'), findsWidgets);
      expect(find.textContaining('行政區統計也不是路段分數'), findsOneWidget);
      expect(find.textContaining('邊界資料更新日期：未提供'), findsOneWidget);
      expect(find.textContaining('不代表這些來源認定此範圍為危險區域'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-area-area-1')), findsOneWidget);
    });

    testWidgets('empty database is not safe', (t) async {
      final db = _Db()
        ..answer = () async =>
            CrimeReferenceHttpResponse(200, jsonEncode(_body(total: 0)));
      final c = SafeWalkReportStatusController(
        repository: db.repository,
        clock: () => _now,
      );
      await pumpPage(t, c);
      expect(c.queryStatus, ReportQueryStatus.empty);
      expect(status('無紀錄'), findsOneWidget);
      expect(find.textContaining('不代表這些地方沒有風險或安全'), findsOneWidget);
    });

    testWidgets('empty snapshot still shows its stale-data warning', (t) async {
      final db = _Db()
        ..answer = () async =>
            CrimeReferenceHttpResponse(200, jsonEncode(_body(total: 0)));
      final c = SafeWalkReportStatusController(
        repository: db.repository,
        staleAfter: const Duration(days: 30),
        clock: () => _now,
      );
      await pumpPage(t, c);
      expect(c.queryStatus, ReportQueryStatus.empty);
      expect(c.snapshotIsStale, isTrue);
      expect(status('無紀錄'), findsOneWidget);
      expect(find.byKey(const Key('report-stale-note')), findsOneWidget);
    });

    testWidgets('no reviewed area says so and is not safe', (t) async {
      final c = SafeWalkReportStatusController(
        repository: _Db().repository,
        clock: () => _now,
      );
      await pumpPage(t, c);
      expect(c.queryStatus, ReportQueryStatus.ok);
      final none = find.byKey(const Key('report-no-areas'));
      expect(none, findsOneWidget);
      expect(find.textContaining('尚無任何經審查的警示區域'), findsOneWidget);
      expect(find.textContaining('不代表這些地方沒有風險或安全'), findsOneWidget);
      expect(find.textContaining('目前很安全'), findsNothing);
    });

    testWidgets('error: failed, timeout and not configured', (t) async {
      final failing = _Db()
        ..answer = () async => const CrimeReferenceHttpResponse(503, '{}');
      final c = SafeWalkReportStatusController(
        repository: failing.repository,
        reviewedAreas: [_area()],
        clock: () => _now,
      );
      await pumpPage(t, c);
      expect(c.queryStatus, ReportQueryStatus.error);
      expect(status('錯誤'), findsOneWidget);
      expect(find.textContaining('查詢失敗'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-area-area-1')), findsNothing);
      expect(find.byKey(const Key('report-retry')), findsOneWidget);

      final none = SafeWalkReportStatusController(
        repository: CrimeReferenceRepository(transport: null),
        clock: () => _now,
      );
      await pumpPage(t, none);
      expect(none.queryStatus, ReportQueryStatus.error);
      expect(status('錯誤'), findsOneWidget);

      final slow = _Db()
        ..answer = () => Completer<CrimeReferenceHttpResponse>().future;
      final timeout = SafeWalkReportStatusController(
        repository: slow.repository,
        timeout: const Duration(milliseconds: 20),
        clock: () => _now,
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        MaterialApp(
          home: SafeWalkReportStatusPage(
            controller: timeout,
            onBack: () {},
            showMap: false,
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 50));
      await t.pump();
      expect(timeout.queryStatus, ReportQueryStatus.error);
      expect(find.textContaining('查詢逾時'), findsOneWidget);
    });

    testWidgets('stale: old snapshot is labelled and still not safe', (
      t,
    ) async {
      final c = SafeWalkReportStatusController(
        repository: _Db().repository,
        reviewedAreas: [_area()],
        staleAfter: const Duration(days: 30),
        // 39 days after the 2026-09-30 snapshot date.
        clock: () => _now,
      );
      await pumpPage(t, c);
      expect(c.queryStatus, ReportQueryStatus.stale);
      expect(status('資料過舊'), findsOneWidget);
      expect(find.byKey(const Key('report-stale-note')), findsOneWidget);
      expect(find.textContaining('未列出的地點不代表安全'), findsWidgets);
    });

    test(
      'freshness uses a UTC date, exact boundary and valid past dates',
      () async {
        Future<ReportQueryStatus> run(
          String asOf,
          Duration after, {
          DateTime? now,
        }) async {
          final body = _body();
          (body['snapshot']! as Map<String, Object?>)['asOfDate'] = asOf;
          // Keep the artificial record before every tested snapshot date.
          ((body['records']! as List).first
                  as Map<String, Object?>)['eventDate'] =
              '2026-01-01';
          final db = _Db()
            ..answer = () async =>
                CrimeReferenceHttpResponse(200, jsonEncode(body));
          final c = SafeWalkReportStatusController(
            repository: db.repository,
            staleAfter: after,
            clock: () => now ?? _now,
          );
          await c.load();
          final status = c.queryStatus;
          c.dispose();
          return status;
        }

        expect(
          await run('2026-11-01', const Duration(days: 30)),
          ReportQueryStatus.ok,
        );
        expect(
          await run('2026-09-30', const Duration(days: 30)),
          ReportQueryStatus.stale,
        );
        expect(
          await run(
            '2026-10-09',
            const Duration(days: 30),
            now: DateTime.parse('2026-11-08T08:00:00+08:00'),
          ),
          ReportQueryStatus.ok,
        );
        expect(
          await run(
            '2026-10-09',
            const Duration(days: 30),
            now: DateTime.utc(2026, 11, 8, 0, 0, 0, 0, 1),
          ),
          ReportQueryStatus.stale,
        );
        expect(
          await run('2026-12-01', const Duration(days: 90)),
          ReportQueryStatus.stale,
        );
        expect(
          await run('2026-02-31', const Duration(days: 365)),
          ReportQueryStatus.stale,
        );
      },
    );
  });

  group('official composition entry', () {
    Future<void> pumpRoot(
      WidgetTester t, {
      required _Platform platform,
      required _Routes routes,
      required _Db db,
      List<RouteReferenceArea> areas = const [],
      bool showMap = false,
      sw.Coordinates? home,
    }) async {
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpWidget(
        MaterialApp(
          home: SafeWalkCompositionRoot(
            liveRoutes: true,
            platform: platform,
            routeService: routes,
            crimeRepository: db.repository,
            reviewedAreas: areas,
            showLiveMap: showMap,
            watchPosition: () => const Stream<sw.Position>.empty(),
            homeLocationStore: _HomeStore(home),
            speaker: _SilentSpeaker(),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Future<void> openMap(WidgetTester t) async {
      await t.tap(find.text('安心行'));
      await t.pumpAndSettle();
      expect(find.byType(SafeWalkMapView), findsOneWidget);
      expect(find.byType(SafeWalkLiveRoutePage), findsNothing);
    }

    Future<void> runLoop(WidgetTester t, {bool referenceConsent = true}) async {
      expect(find.text('規劃路線需要你的位置'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, '同意'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      expect(find.text('犯罪參考資料查詢同意'), findsOneWidget);
      await t.tap(
        find.widgetWithText(TextButton, referenceConsent ? '同意查詢' : '不要查詢'),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      await t.pump();
    }

    SafeWalkMapView map(WidgetTester t) =>
        t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView));

    Future<void> leaveMap(WidgetTester t) async {
      map(t).onBack();
      await t.pumpAndSettle();
      expect(find.byType(SafeWalkMapView), findsNothing);
    }

    testWidgets(
      'M3 runs the full consented route loop; root entry reads nothing',
      (t) async {
        final platform = _livePlatform();
        final routes = _Routes();
        final db = _Db();
        await pumpRoot(
          t,
          platform: platform,
          routes: routes,
          db: db,
          home: _destination,
        );
        expect(platform.calls, 0);
        expect(routes.requests, isEmpty);
        expect(db.calls, isEmpty);
        await openMap(t);
        expect(platform.calls, 0);
        expect(routes.requests, isEmpty);
        expect(db.calls, isEmpty);
        await runLoop(t);
        expect(platform.calls, 1);
        expect(routes.requests, hasLength(1));
        expect(
          routes.requests.single.destination.toJson(),
          _destination.toJson(),
        );
        expect(db.calls, hasLength(1));
        expect(map(t).routeState.best?.id, 'osrm-direct');
        expect(map(t).routeState.allowDemoFallback, isFalse);
        expect(map(t).crimeSpots, hasLength(1));
        // The buffer note opens on tapping a purple dot; the dot itself is labelled.
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.label ?? '').contains('50 公尺避讓緩衝區'),
          ),
          findsWidgets,
        );
        expect(find.textContaining('不保證'), findsWidgets);
        expect(find.text('示範路線／非即時導航'), findsNothing);
        await leaveMap(t);
        expect(t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).route, isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'official entry keeps unconfigured points and SMS unavailable without GPS',
      (t) async {
        final platform = _livePlatform();
        final routes = _Routes();
        final db = _Db();
        await pumpRoot(
          t,
          platform: platform,
          routes: routes,
          db: db,
          home: _destination,
        );
        expect(
          t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).mode,
          sw.DataMode.live,
        );
        expect(find.text('目前為示範資料，未連線真實服務'), findsNothing);
        await t.tap(find.text('附近求助地點'));
        await t.pumpAndSettle();
        expect(find.byType(SafeWalkMapView), findsNothing);
        expect(find.textContaining('附近求助地點查詢尚未接線'), findsOneWidget);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        await t.tap(find.text('緊急求助'));
        await t.pumpAndSettle();
        expect(find.text('簡訊求助尚未配置'), findsOneWidget);
        expect(find.text('傳送簡訊'), findsNothing);
        expect(find.textContaining('示範完成'), findsNothing);
        expect(platform.calls, 0);
        expect(routes.requests, isEmpty);
        expect(db.calls, isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'saved home requires routing consent and does not grant OSM tile consent',
      (t) async {
        final platform = _livePlatform();
        final routes = _Routes();
        final db = _Db();
        await pumpRoot(
          t,
          platform: platform,
          routes: routes,
          db: db,
          showMap: true,
          home: _destination,
        );
        await openMap(t);
        expect(map(t).showMapTiles, isFalse);
        expect(find.byType(TileLayer), findsNothing);
        expect(platform.calls, 0);
        await runLoop(t, referenceConsent: false);
        expect(
          routes.requests.single.destination.toJson(),
          _destination.toJson(),
        );
        expect(platform.calls, 1);
        expect(db.calls, isEmpty);
        expect(map(t).showMapTiles, isFalse);
        expect(find.byType(TileLayer), findsNothing);
        // Map loading is a setting in 資料來源與授權, like the query settings.
        Future<void> tileSetting(String choice) async {
          final link = find.text('資料來源與授權').last;
          await t.ensureVisible(link);
          await t.tap(link);
          await t.pumpAndSettle();
          await t.tap(find.text('地圖載入設定'));
          await t.pumpAndSettle();
          await t.tap(find.text(choice));
          await t.pumpAndSettle();
        }

        await tileSetting('同意載入');
        expect(map(t).showMapTiles, isTrue);
        expect(find.byType(TileLayer), findsOneWidget);
        await tileSetting('不載入');
        expect(find.byType(TileLayer), findsNothing);
        expect(platform.calls, 1);
        expect(routes.requests, hasLength(1));
        expect(db.calls, isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('unset Live home contains no demo coordinates or route', (
      t,
    ) async {
      final platform = _livePlatform();
      final routes = _Routes();
      final db = _Db();
      await pumpRoot(t, platform: platform, routes: routes, db: db);
      await openMap(t);
      expect(map(t).places, hasLength(1));
      expect(map(t).places.single.at, isNull);
      expect(map(t).destinationConfigured, isFalse);
      expect(map(t).routeState.best, isNull);
      expect(map(t).anomalies, isEmpty);
      expect(platform.calls, 0);
      expect(routes.requests, isEmpty);
      expect(db.calls, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('home settings does not automatically read GPS or load tiles', (
      t,
    ) async {
      final platform = _livePlatform();
      final routes = _Routes();
      final db = _Db();
      await pumpRoot(t, platform: platform, routes: routes, db: db);
      await t.tap(find.text('設定「家」'));
      await t.pumpAndSettle();
      expect(find.text('載入地圖'), findsOneWidget);
      expect(find.byType(TileLayer), findsNothing);
      expect(platform.calls, 0);
      expect(routes.requests, isEmpty);
      expect(db.calls, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('route failure remains visible in M3 without a demo route', (
      t,
    ) async {
      final routes = _Routes(
        (r) async => _routeFail(r, sw.RouteFailureStatus.noRoute),
      );
      await pumpRoot(
        t,
        platform: _livePlatform(),
        routes: routes,
        db: _Db(),
        home: _destination,
      );
      await openMap(t);
      await runLoop(t);
      expect(map(t).routeState.failed, isTrue);
      expect(map(t).routeState.best, isNull);
      expect(find.textContaining('人工路線失敗'), findsWidgets);
      expect(find.text('示範路線／非即時導航'), findsNothing);
      expect(find.textContaining('示範據點'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('denied location prevents route and reference requests', (
      t,
    ) async {
      final platform = _Platform(() async => _locFail('denied'));
      final routes = _Routes();
      final db = _Db();
      await pumpRoot(
        t,
        platform: platform,
        routes: routes,
        db: db,
        home: _destination,
      );
      await openMap(t);
      await runLoop(t);
      expect(find.textContaining('檢查定位權限或重新定位'), findsOneWidget);
      expect(map(t).routeState.best, isNull);
      expect(routes.requests, isEmpty);
      expect(db.calls, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'report entry queries only limit 1 metadata without GPS or routing',
      (t) async {
        final platform = _livePlatform();
        final routes = _Routes();
        final db = _Db();
        await pumpRoot(
          t,
          platform: platform,
          routes: routes,
          db: db,
          areas: [_area()],
          home: _destination,
        );
        expect(db.calls, isEmpty);
        await t.tap(find.text('回報狀況'));
        await t.pumpAndSettle();
        expect(find.byType(SafeWalkReportStatusPage), findsOneWidget);
        expect(find.byType(SafeWalkMapView), findsNothing);
        expect(db.calls, hasLength(1));
        expect(db.calls.single['p_limit'], 1);
        expect(
          find.byKey(const ValueKey('report-area-area-1')),
          findsOneWidget,
        );
        expect(find.textContaining('人工測試邊界證據'), findsOneWidget);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        await t.tap(find.text('回報狀況'));
        await t.pumpAndSettle();
        expect(db.calls, hasLength(2));
        expect(platform.calls, 0);
        expect(routes.requests, isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'report status preserves empty database and no reviewed area states',
      (t) async {
        final db = _Db()
          ..answer = () async =>
              CrimeReferenceHttpResponse(200, jsonEncode(_body(total: 0)));
        await pumpRoot(t, platform: _livePlatform(), routes: _Routes(), db: db);
        await t.tap(find.text('回報狀況'));
        await t.pumpAndSettle();
        expect(find.textContaining('空資料'), findsOneWidget);
        expect(find.byKey(const Key('report-no-areas')), findsOneWidget);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'leaving report cancels immediately and ignores a late response',
      (t) async {
        final pending = Completer<CrimeReferenceHttpResponse>();
        final db = _Db()..answer = () => pending.future;
        final platform = _livePlatform();
        final routes = _Routes();
        await pumpRoot(
          t,
          platform: platform,
          routes: routes,
          db: db,
          home: _destination,
        );
        await t.tap(find.text('回報狀況'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 350));
        final controller = t
            .widget<SafeWalkReportStatusPage>(
              find.byType(SafeWalkReportStatusPage),
            )
            .controller;
        expect(db.calls, hasLength(1));
        // Exercise the root's leave callback, before AnimatedSwitcher disposes
        // the outgoing report page on a later frame.
        t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).onLeaveReport!();
        expect(controller.stage, ReportStatusStage.cancelled);
        pending.complete(CrimeReferenceHttpResponse(200, jsonEncode(_body())));
        await t.pump();
        expect(controller.result, isNull);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        expect(platform.calls, 0);
        expect(routes.requests, isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final interrupt in ['leave', 'background']) {
      testWidgets(
        '$interrupt ignores an in-flight route result without restarting',
        (t) async {
          final pending = Completer<sw.RouteResult>();
          final platform = _livePlatform();
          final routes = _Routes((_) => pending.future);
          await pumpRoot(
            t,
            platform: platform,
            routes: routes,
            db: _Db(),
            home: _destination,
          );
          await openMap(t);
          await runLoop(t);
          expect(routes.requests, hasLength(1));
          if (interrupt == 'leave') {
            map(t).onBack();
          } else {
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          }
          await t.pump();
          pending.complete(_success(routes.requests.single));
          await t.pump();
          await t.pump(const Duration(milliseconds: 350));
          expect(
            t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).route,
            isNull,
          );
          if (interrupt == 'background') {
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            await t.pump();
            expect(map(t).routeState.best, isNull);
          } else {
            expect(find.byType(SafeWalkMapView), findsNothing);
          }
          expect(routes.requests, hasLength(1));
          expect(platform.calls, 1);
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  });
}

/// Widget tests run on the real clock, so the fix must be fresh now.
_Platform _livePlatform() =>
    _Platform(() async => _ok(_fix(at: DateTime.now().toUtc())));

final class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}

final class _HomeStore implements HomeLocationStore {
  _HomeStore(this.home);
  final sw.Coordinates? home;
  @override
  Future<String?> read() async =>
      home == null ? null : jsonEncode({'lat': home!.lat, 'lng': home!.lng});
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

final class _SilentSpeaker implements SafeWalkRouteSpeaker {
  @override
  bool get available => false;
  @override
  void speak(String text, {void Function()? onDone}) => onDone?.call();
  @override
  void stop() {}
  @override
  void setLifecycleActive(bool active) {}
  @override
  Future<void> stopForEmergency() async {}
  @override
  Future<void> dispose() async {}
}
