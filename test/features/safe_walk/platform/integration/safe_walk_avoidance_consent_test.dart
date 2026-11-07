import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// All positions, records and recipients below are artificial. No device APIs
// or external transport are used by these regressions.
final class _HomeStore implements HomeLocationStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

final class _Speaker implements SafeWalkRouteSpeaker {
  @override
  bool get available => false;
  @override
  void speak(String text, {void Function()? onDone}) {}
  @override
  void stop() {}
  @override
  void setLifecycleActive(bool active) {}
  @override
  Future<void> stopForEmergency() async {}
  @override
  Future<void> dispose() async {}
}

final class _Platform implements PlatformService {
  final locations = <Completer<sw.LocationResult>>[];
  final cancellations = <SafeWalkCancellation>[];
  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    expectSync(mode, sw.DataMode.live);
    expectSync(userInitiated, isTrue);
    cancellations.add(cancellation!);
    final pending = Completer<sw.LocationResult>();
    locations.add(pending);
    return pending.future;
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async => sw.EmergencyActionResult(
    channel: channel,
    action: sw.EmergencyAction.notConfigured,
    message: '測試未撥號、未通知。',
  );
}

final class _Routes implements RouteService {
  final requests = <sw.RouteRequest>[];
  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    requests.add(request);
    return sw.RouteFailure(
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      status: sw.RouteFailureStatus.noRoute,
      reason: '人工測試不提供路線。',
      warnings: const [],
    );
  }
}

sw.LocationSuccess _position() => sw.LocationSuccess(
  position: sw.Position(
    coordinates: sw.Coordinates(lat: 25, lng: 121.5),
    source: sw.PositionSource.gps,
    accuracyMeters: 10,
    observedAt: DateTime.now().toUtc().toIso8601String(),
  ),
);

CrimeReferenceHttpResponse _answer({bool empty = false}) =>
    CrimeReferenceHttpResponse(
      200,
      jsonEncode({
        'interfaceVersion': 1,
        'snapshot': {
          'snapshotId': '00000000-0000-4000-8000-000000000000',
          'label': 'artificial',
          'asOfDate': '2026-09-30',
          'importedAt': '2026-10-02T00:00:00Z',
          'recordCount': 1,
        },
        'sources': [
          {
            'sourceKey': 'artificial-source',
            'datasetId': 'artificial',
            'resourceId': null,
            'name': '人工測試來源',
            'sourceUrl': 'https://example.test/dataset',
            'resourceUrl': 'https://example.test/resource',
            'license': '人工授權',
            'retrievedAt': '2026-10-01T00:00:00Z',
            'dataUpdatedAt': null,
            'recordCount': 1,
          },
        ],
        'totalMatching': empty ? 0 : 1,
        'records': [
          if (!empty)
            {
              'sourceKey': 'artificial-source',
              'sourceRecordId': 'row-1',
              'eventDate': '2026-05-01',
              'city': '臺北市',
              'district': null,
              'category': '人工類別',
              'locationText': '人工地點',
              'latitude': 25.0005,
              'longitude': 121.5005,
              'spatialPrecision': 'address_reference',
              'confidence': 'high',
              'coordinateStatus': 'reference_geocoded',
            },
        ],
      }),
    );

SafeWalkFlow _flow(WidgetTester tester) =>
    tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
SafeWalkNavigationScope _scope(WidgetTester tester) => tester
    .element(find.byType(SafeWalkFlow))
    .getInheritedWidgetOfExactType<SafeWalkNavigationScope>()!;

Future<void> _mount(
  WidgetTester tester,
  _Platform platform,
  _Routes routes,
  CrimeReferenceRepository crime,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SafeWalkCompositionRoot(
        liveRoutes: true,
        platform: platform,
        routeService: routes,
        crimeRepository: crime,
        crimeServiceHost: 'reference.example.test',
        homeLocationStore: _HomeStore(),
        speaker: _Speaker(),
        watchPosition: () => const Stream.empty(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester, {bool crime = true}) async {
  _flow(tester).onPlanRoute!(sw.Coordinates(lat: 25.001, lng: 121.501));
  await tester.pumpAndSettle();
  expect(find.text('規劃路線需要你的位置'), findsOneWidget);
  await tester.tap(find.text('同意'));
  await tester.pumpAndSettle();
  if (find.text('犯罪參考資料查詢同意').evaluate().isNotEmpty) {
    expect(find.textContaining('reference.example.test'), findsOneWidget);
    await tester.tap(find.text(crime ? '同意查詢' : '不要查詢'));
    await tester.pumpAndSettle();
  }
}

void _interrupt(WidgetTester tester, String reason) {
  switch (reason) {
    case 'leave':
      _flow(tester).onLeaveMap!();
    case 'background':
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    case 'SOS':
      _scope(tester).onEmergencyOpened();
    case 'destination':
      _scope(tester).onDestinationChanged();
    case 'routing consent':
      _flow(tester).onRevokeRoutingConsent!();
  }
}

void main() {
  testWidgets('late routing consent after leaving cannot start GPS', (
    tester,
  ) async {
    final platform = _Platform();
    final routes = _Routes();
    await _mount(
      tester,
      platform,
      routes,
      CrimeReferenceRepository(transport: null),
    );
    _flow(tester).onPlanRoute!(sw.Coordinates(lat: 25.001, lng: 121.501));
    await tester.pumpAndSettle();
    _flow(tester).onLeaveMap!();
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(_scope(tester).hasRoutingConsent, isFalse);
    expect(platform.locations, isEmpty);
    expect(routes.requests, isEmpty);
  });

  testWidgets(
    'late optional crime consent after leaving cannot persist acceptance',
    (tester) async {
      var queries = 0;
      final platform = _Platform();
      final routes = _Routes();
      await _mount(
        tester,
        platform,
        routes,
        CrimeReferenceRepository(
          transport: (_) async {
            queries++;
            return _answer();
          },
        ),
      );
      await _start(tester, crime: false);
      _flow(tester).onManageCrimeConsent!();
      await tester.pumpAndSettle();
      _flow(tester).onLeaveMap!();
      await tester.tap(find.text('同意查詢'));
      await tester.pumpAndSettle();
      _flow(tester).onPlanRoute!(sw.Coordinates(lat: 25.002, lng: 121.502));
      await tester.pumpAndSettle();
      platform.locations.first.complete(_position());
      platform.locations.last.complete(_position());
      await tester.pumpAndSettle();
      expect(queries, 0);
      expect(routes.requests, hasLength(1));
      expect(_flow(tester).crimeQueryStatus, contains('未同意'));
    },
  );

  testWidgets('routing consent does not imply crime query consent', (
    tester,
  ) async {
    var queries = 0;
    final platform = _Platform();
    final routes = _Routes();
    await _mount(
      tester,
      platform,
      routes,
      CrimeReferenceRepository(
        transport: (_) async {
          queries++;
          return _answer();
        },
      ),
    );
    await _start(tester, crime: false);
    platform.locations.single.complete(_position());
    await tester.pumpAndSettle();
    expect(queries, 0);
    expect(routes.requests, hasLength(1));
    expect(_flow(tester).crimeSpots, isEmpty);
    expect(_flow(tester).crimeQueryStatus, contains('未同意'));
  });

  for (final reason in [
    'leave',
    'background',
    'SOS',
    'destination',
    'routing consent',
  ]) {
    testWidgets('late GPS after $reason cannot query or route', (tester) async {
      var queries = 0;
      final platform = _Platform();
      final routes = _Routes();
      await _mount(
        tester,
        platform,
        routes,
        CrimeReferenceRepository(
          transport: (_) async {
            queries++;
            return _answer();
          },
        ),
      );
      await _start(tester);
      _interrupt(tester, reason);
      expect(platform.cancellations.single.isCancelled, isTrue);
      platform.locations.single.complete(_position());
      await tester.pumpAndSettle();
      expect(queries, 0);
      expect(routes.requests, isEmpty);
      if (reason == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
    });

    testWidgets(
      'late reference query after $reason cannot restore buffers or route',
      (tester) async {
        final pending = Completer<CrimeReferenceHttpResponse>();
        final platform = _Platform();
        final routes = _Routes();
        var queries = 0;
        await _mount(
          tester,
          platform,
          routes,
          CrimeReferenceRepository(
            transport: (_) {
              queries++;
              return pending.future;
            },
          ),
        );
        await _start(tester);
        platform.locations.single.complete(_position());
        await tester.pumpAndSettle();
        expect(queries, 1);
        _interrupt(tester, reason);
        pending.complete(_answer());
        await tester.pumpAndSettle();
        expect(routes.requests, isEmpty);
        expect(_flow(tester).crimeSpots, isEmpty);
        if (reason == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      },
    );
  }

  testWidgets(
    'new destination rejects previous GPS and uses only latest destination',
    (tester) async {
      var queries = 0;
      final platform = _Platform();
      final routes = _Routes();
      await _mount(
        tester,
        platform,
        routes,
        CrimeReferenceRepository(
          transport: (_) async {
            queries++;
            return _answer();
          },
        ),
      );
      await _start(tester);
      _flow(tester).onPlanRoute!(sw.Coordinates(lat: 25.002, lng: 121.502));
      await tester.pumpAndSettle();
      expect(platform.locations, hasLength(2));
      platform.locations.first.complete(_position());
      await tester.pumpAndSettle();
      expect(queries, 0);
      platform.locations.last.complete(_position());
      await tester.pumpAndSettle();
      expect(queries, 1);
      expect(routes.requests.single.destination.lat, 25.002);
      expect(_flow(tester).crimeSpots.single.label, contains('門牌參考位置'));
      expect(_flow(tester).crimeSpots.single.label, contains('人工測試來源'));
      expect(_flow(tester).crimeQueryStatus, contains('50 公尺'));
    },
  );

  testWidgets(
    'crime consent is independently revocable during its pending query',
    (tester) async {
      final pending = Completer<CrimeReferenceHttpResponse>();
      final platform = _Platform();
      final routes = _Routes();
      await _mount(
        tester,
        platform,
        routes,
        CrimeReferenceRepository(transport: (_) => pending.future),
      );
      await _start(tester);
      platform.locations.single.complete(_position());
      await tester.pumpAndSettle();
      _flow(tester).onManageCrimeConsent!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤回同意'));
      await tester.pumpAndSettle();
      pending.complete(_answer());
      await tester.pumpAndSettle();
      expect(_scope(tester).hasRoutingConsent, isTrue);
      expect(_flow(tester).crimeSpots, isEmpty);
      expect(_flow(tester).crimeQueryStatus, contains('未同意'));
      expect(routes.requests, isEmpty);
    },
  );

  for (final outcome in ['unconfigured', 'failure', 'empty']) {
    testWidgets('crime query $outcome remains visible without mock fallback', (
      tester,
    ) async {
      final platform = _Platform();
      final routes = _Routes();
      final crime = CrimeReferenceRepository(
        transport: outcome == 'unconfigured'
            ? null
            : (_) async {
                if (outcome == 'failure') {
                  throw StateError('artificial network failure');
                }
                return _answer(empty: true);
              },
      );
      await _mount(tester, platform, routes, crime);
      await _start(tester);
      platform.locations.single.complete(_position());
      await tester.pumpAndSettle();
      expect(routes.requests, hasLength(1));
      expect(_flow(tester).crimeSpots, isEmpty);
      expect(
        _flow(tester).crimeQueryStatus,
        contains(switch (outcome) {
          'unconfigured' => '尚未配置',
          'failure' => '查詢失敗',
          _ => '沒有可定位',
        }),
      );
    });
  }
}
