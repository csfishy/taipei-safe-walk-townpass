import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_store_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_models.dart'
    show LatLng;
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  Future<void> mount(
    WidgetTester t,
    RouteService? routes,
    _Gps gps, {
    Stream<sw.Position> Function()? watch,
    Stream<double> Function()? heading,
    NearbyPointFinder? finder,
    bool nearby = false,
    bool hasHome = true,
  }) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: SafeWalkCompositionRoot(
          liveRoutes: true,
          routeService: routes,
          platform: gps,
          watchPosition: watch,
          watchHeading: heading ?? () => const Stream.empty(),
          findStores: finder ?? (origin, {cancellation}) async => [],
          homeLocationStore: _SavedHomeStore()
            .._value = hasHome ? '{"lat":25.0330,"lng":121.5704}' : null,
          speaker: _UnavailableSpeaker(),
          crimeRepository: CrimeReferenceRepository(transport: null),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('點擊開始'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    if (!nearby) {
      // These regressions exercise an explicitly selected saved destination.
      await t.tap(find.text('目的地'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      gps.calls = 0;
    }
  }

  for (final hasHome in [false, true]) {
    testWidgets(
      'main card previews nearest help on every entry (home=$hasHome)',
      (t) async {
        final routes = _Answering();
        final gps = _Gps();
        var queries = 0, watches = 0, headings = 0;
        await mount(
          t,
          routes,
          gps,
          nearby: true,
          hasHome: hasHome,
          finder: (origin, {cancellation}) async {
            queries++;
            return [_helpPoint('far', 121.5684), _helpPoint('near', 121.5664)];
          },
          watch: () {
            watches++;
            return const Stream.empty();
          },
          heading: () {
            headings++;
            return const Stream.empty();
          },
        );
        await t.pumpAndSettle();
        expect(queries, 1);
        expect(gps.calls, 1);
        expect(routes.requests.map((r) => r.destination.lng), [
          121.5664,
          121.5684,
        ]);
        expect(
          t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).targetPointId,
          'near',
        );
        expect(find.text('家在哪裡？'), findsNothing);
        expect(find.text('規劃路線需要你的位置'), findsNothing);
        expect(watches, 0, reason: 'preview only uses a single GPS fix');
        expect(headings, 0);
        expect(
          t
              .widget<SafeWalkMapView>(find.byType(SafeWalkMapView))
              .routeState
              .path,
          isNotEmpty,
        );
        await t.ensureVisible(find.text('開始導覽'));
        await t.tap(find.text('開始導覽'));
        await t.pumpAndSettle();
        expect(watches, 1);
        expect(headings, 1);
        await t.tap(find.text('結束導覽'));
        await t.pumpAndSettle();
        // Changing the visible segment must not become the next entry's default.
        if (hasHome) {
          await t.tap(find.text('目的地'));
          await t.pumpAndSettle();
          await t.tap(find.text('不要'));
          await t.pumpAndSettle();
        }
        t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).onBack();
        await t.pumpAndSettle();
        await t.tap(find.text('點擊開始'));
        await t.pumpAndSettle();
        expect(queries, 2);
        expect(
          t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).targetPointId,
          'near',
        );
        expect(watches, 1, reason: 're-entry returns to preview');
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('switching to destination discards a late nearby lookup', (
    t,
  ) async {
    final lookup = Completer<List<sw.AssistancePoint>>();
    SafeWalkCancellation? token;
    final routes = _Answering();
    await mount(
      t,
      routes,
      _Gps(),
      nearby: true,
      finder: (origin, {cancellation}) {
        token = cancellation;
        return lookup.future;
      },
    );
    await t.tap(find.text('目的地'));
    await t.pumpAndSettle();
    await t.tap(find.text('同意'));
    await t.pumpAndSettle();
    expect(token?.isCancelled, isTrue);
    lookup.complete([_helpPoint('late', 121.5664)]);
    await t.pumpAndSettle();
    expect(routes.requests.single.destination.lng, 121.5704);
    final map = t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView));
    expect(map.targetPointId, isNull);
    expect(map.pointsState.points, isEmpty);
    expect(find.textContaining('→ 家'), findsOneWidget);
  });

  testWidgets(
    'refreshing nearby routes retains the chosen point as results arrive',
    (t) async {
      final routes = _Answering();
      await mount(
        t,
        routes,
        _Gps(),
        nearby: true,
        finder: (origin, {cancellation}) async => [
          _helpPoint('near', 121.5664),
          _helpPoint('far', 121.5684),
        ],
      );
      await t.pumpAndSettle();
      await t.tap(find.text('人工求助地點 far').first);
      await t.pumpAndSettle();
      final map = t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView));
      expect(map.targetPointId, 'far');
      map.pointsState.onRetry!();
      await t.pumpAndSettle();
      final refreshed = t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView));
      expect(refreshed.targetPointId, 'far');
      expect(
        refreshed.routeState.result,
        same(refreshed.pointsState.routes['far']),
      );
      expect(routes.requests, hasLength(4));
      expect(find.text('開始導覽'), findsOneWidget);
    },
  );

  testWidgets(
    'changing the origin queries nearby once and keeps preview mode',
    (t) async {
      final origins = <sw.Coordinates>[];
      final routes = _Answering();
      var watches = 0;
      await mount(
        t,
        routes,
        _Gps(),
        nearby: true,
        finder: (origin, {cancellation}) async {
          origins.add(origin);
          return [_helpPoint('near', 121.5664)];
        },
        watch: () {
          watches++;
          return const Stream.empty();
        },
      );
      await t.pumpAndSettle();
      await t.tap(find.textContaining('→ 求助地點').first);
      await t.pumpAndSettle();
      await t.tap(find.text('在地圖上選起點'));
      await t.pumpAndSettle();
      t.widget<SafeWalkMap>(find.byType(SafeWalkMap)).onPick!(
        const LatLng(25.034, 121.565),
      );
      await t.pumpAndSettle();
      expect(origins, hasLength(2));
      expect(origins.last.lat, 25.034);
      expect(routes.requests, hasLength(2));
      expect(routes.requests.last.origin.source, sw.PositionSource.manual);
      expect(routes.requests.last.destination.lng, 121.5664);
      expect(watches, 0);
      expect(find.textContaining('指定起點 → 求助地點'), findsOneWidget);
    },
  );

  testWidgets(
    'default nearby location failure can retry without a saved home',
    (t) async {
      final gps = _Gps()..denied = true;
      final routes = _Answering();
      await mount(
        t,
        routes,
        gps,
        nearby: true,
        hasHome: false,
        finder: (origin, {cancellation}) async => [
          _helpPoint('near', 121.5664),
        ],
      );
      await t.pumpAndSettle();
      expect(routes.requests, isEmpty);
      expect(find.text('求助地點暫時載入失敗'), findsOneWidget);
      expect(find.text('開始導覽'), findsNothing);
      gps.denied = false;
      await t.tap(find.text('再試一次'));
      await t.pumpAndSettle();
      expect(routes.requests.single.destination.lng, 121.5664);
      expect(find.text('開始導覽'), findsOneWidget);
    },
  );

  testWidgets(
    'opening the map asks consent, then plans a live route from GPS',
    (t) async {
      final routes = _Routes();
      final gps = _Gps();
      await mount(t, routes, gps);
      expect(find.text('規劃路線需要你的位置'), findsOneWidget);
      expect(gps.calls, 0, reason: 'no GPS before consent');

      await t.tap(find.text('同意'));
      await t.pump();
      await t.pump();
      expect(gps.calls, 1);
      expect(routes.requests.single.mode, sw.DataMode.live);
      expect(routes.requests.single.origin.coordinates.lat, 25.0330);
      expect(routes.requests.single.destination.lat, 25.0330);
      expect(
        routes.requests.single.destination.lng,
        121.5704,
        reason:
            'route uses the synthetic saved home, not a default destination',
      );
    },
  );

  testWidgets(
    'follows the route, re-plans when off every option, stops when leaving the map',
    (t) async {
      final routes = _Answering();
      final positions = StreamController<sw.Position>();
      var listening = false;
      var listenCount = 0;
      var cancelCount = 0;
      var watchStarts = 0;
      positions.onListen = () {
        listening = true;
        listenCount++;
      };
      positions.onCancel = () {
        listening = false;
        cancelCount++;
      };
      await mount(
        t,
        routes,
        _Gps(),
        watch: () {
          watchStarts++;
          return positions.stream;
        },
      );
      await t.tap(find.text('同意'));
      await t.pumpAndSettle();
      expect(routes.requests, hasLength(1));
      expect(listening, isFalse, reason: 'preview does not follow GPS');
      await t.ensureVisible(find.text('開始導覽'));
      await t.tap(find.text('開始導覽'));
      await t.pumpAndSettle();
      expect(listening, isTrue);

      positions.add(_at(25.0330, 121.5655)); // on the route
      await t.pump();
      expect(routes.requests, hasLength(1));

      positions.add(
        sw.Position(
          coordinates: sw.Coordinates(lat: 25.05, lng: 121.59),
          source: sw.PositionSource.gps,
          accuracyMeters: 8,
          observedAt: DateTime.now()
              .subtract(const Duration(minutes: 2))
              .toUtc()
              .toIso8601String(),
        ),
      );
      await t.pump();
      expect(routes.requests, hasLength(1));
      expect(
        t
            .widget<SafeWalkFlow>(find.byType(SafeWalkFlow))
            .livePosition!
            .coordinates
            .lat,
        25.0330,
        reason: 'a rejected old fix cannot replace the displayed live location',
      );

      positions.add(_at(25.0400, 121.5655)); // ~780 m north: off route
      await t.pumpAndSettle();
      expect(routes.requests, hasLength(2));
      expect(routes.requests.last.origin.coordinates.lat, 25.0400);
      expect(
        listening,
        isTrue,
        reason: 'automatic replan preserves active GPS',
      );
      expect(
        listenCount,
        1,
        reason: 'one subscription through automatic reroute',
      );
      expect(
        watchStarts,
        1,
        reason: 'no second listener on the same device stream',
      );
      expect(cancelCount, 0, reason: 'replanning is not a navigation exit');

      await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).first);
      await t.pumpAndSettle();
      expect(listening, isFalse, reason: 'leaving the map stops GPS');
      expect(cancelCount, 1);
      await t.runAsync(() => positions.close());
    },
  );

  testWidgets(
    'declining third-party consent still plans a real bundled offline route',
    (t) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (call) async {
          if (call.method == 'create') {
            final id = (call.arguments as Map)['playerId'];
            messenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null,
            );
          }
          return null;
        },
      );
      final gps = _Gps();
      await mount(t, null, gps, watch: () => const Stream.empty());
      await t.tap(find.text('不要'));
      await t.pump();
      for (var i = 0; i < 60; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump();
        final result = t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).route;
        if (result is sw.RouteSuccess) break;
      }
      final flow = t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      expect(gps.calls, 1);
      expect(flow.routingConsent, isFalse);
      final result = flow.route as sw.RouteSuccess;
      expect(
        result.routes.every((r) => r.provider == 'offline-osm-graph'),
        isTrue,
      );
      expect(result.warnings.join(), contains('離線路網資料：2026-11-11'));
      expect(result.warnings.join(), contains('未套用避讓'));
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('ending guidance cancels GPS and late replan; starting resumes', (
    t,
  ) async {
    final routes = _DelayedReplan();
    var listeners = 0;
    var cancellations = 0;
    final positions = StreamController<sw.Position>.broadcast(
      onListen: () => listeners++,
      onCancel: () => cancellations++,
    );
    await mount(t, routes, _Gps(), watch: () => positions.stream);
    await t.tap(find.text('同意'));
    await t.pumpAndSettle();
    final original = t
        .widget<SafeWalkMapView>(find.byType(SafeWalkMapView))
        .routeState
        .result;
    await t.ensureVisible(find.text('開始導覽'));
    await t.tap(find.text('開始導覽'));
    await t.pumpAndSettle();
    expect(listeners, 1);

    positions.add(_at(25.0400, 121.5655));
    await t.pump();
    await t.pump();
    expect(routes.requests, hasLength(2));
    expect(find.text('路線重新規劃中…'), findsOneWidget);
    await t.tap(find.text('結束導覽'));
    await t.pumpAndSettle();
    expect(cancellations, 1);
    expect(routes.tokens.last?.isCancelled, isTrue);
    expect(
      t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).routeState.result,
      same(original),
      reason: 'ending retains the last route as a preview',
    );

    routes.delayed.complete(await _Answering().planRoute(routes.requests.last));
    positions.add(_at(25.05, 121.59));
    await t.pumpAndSettle();
    expect(routes.requests, hasLength(2));
    expect(listeners, 1, reason: 'late work cannot restart GPS');
    expect(
      t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).routeState.result,
      same(original),
    );

    await t.ensureVisible(find.text('開始導覽'));
    await t.tap(find.text('開始導覽'));
    await t.pumpAndSettle();
    expect(listeners, 2, reason: 'an explicit start resumes GPS');
    positions.add(_at(25.0330, 121.5655));
    await t.pumpAndSettle();
    expect(
      t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).livePosition,
      isNotNull,
    );
    await t.pumpWidget(const SizedBox.shrink());
    await t.runAsync(positions.close);
  });
}

// Synthetic public-place fixtures; no real GPS or external services.
sw.AssistancePoint _helpPoint(String id, double lng) =>
    sw.AssistancePoint.fromJson({
      'schemaVersion': '1.0.0',
      'id': id,
      'name': '人工求助地點 $id',
      'kind': 'convenience_store',
      'coordinates': {'lat': 25.0330, 'lng': lng},
      'address': null,
      'publicPhone': null,
      'recognition': {
        'status': 'unconfirmed',
        'evidenceUrl': null,
        'checkedAt': null,
      },
      'availability': 'open',
      'availabilityCheckedAt': DateTime.now().toUtc().toIso8601String(),
      'capabilities': ['unknown'],
      'source': {
        'datasetId': 'test-nearby',
        'title': '人工測試資料',
        'dataMode': 'live',
        'sourceUrl': 'https://example.test/',
        'retrievedAt': DateTime.now().toUtc().toIso8601String(),
        'dataUpdatedAt': null,
        'license': null,
        'coverage': '人工',
        'limitations': ['僅供隔離測試'],
      },
    });

final class _DelayedReplan implements RouteService {
  final requests = <sw.RouteRequest>[];
  final tokens = <SafeWalkCancellation?>[];
  final delayed = Completer<sw.RouteResult>();

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    requests.add(request);
    tokens.add(cancellation);
    return requests.length == 2
        ? delayed.future
        : _Answering().planRoute(request);
  }
}

// Artificial saved destination for these routing regressions. This fake never
// reads the device preferences or a real user's home.
final class _SavedHomeStore implements HomeLocationStore {
  String? _value = '{"lat":25.0330,"lng":121.5704}';

  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

final class _UnavailableSpeaker implements SafeWalkRouteSpeaker {
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

final class _Routes implements RouteService {
  final requests = <sw.RouteRequest>[];
  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    requests.add(request);
    return Completer<sw.RouteResult>().future;
  }
}

sw.Position _at(double lat, double lng) => sw.Position(
  coordinates: sw.Coordinates(lat: lat, lng: lng),
  source: sw.PositionSource.gps,
  accuracyMeters: 8,
  observedAt: DateTime.now().toUtc().toIso8601String(),
);

final class _Answering implements RouteService {
  final requests = <sw.RouteRequest>[];
  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    requests.add(request);
    final o = request.origin.coordinates;
    return sw.RouteSuccess(
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      warnings: const ['不保證安全'],
      routes: [
        sw.RouteCandidate(
          id: 'r',
          kind: sw.RouteKind.direct,
          geometry: sw.LineString(
            coordinates: [
              (longitude: o.lng, latitude: o.lat),
              (
                longitude: request.destination.lng,
                latitude: request.destination.lat,
              ),
            ],
          ),
          distanceMeters: 500,
          durationSeconds: 400,
          viaPointIds: const [],
          provider: 'valhalla-pedestrian',
          walkingNetworkVerified: true,
          explanations: const ['最短步行路線'],
          warnings: const ['不保證安全'],
        ),
      ],
    );
  }
}

final class _Gps implements PlatformService {
  int calls = 0;
  bool denied = false;
  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    if (mode == sw.DataMode.mock) {
      return sw.LocationFailure(
        status: sw.LocationFailureStatus.unavailable,
        message: 'mock',
      );
    }
    calls++;
    if (denied) {
      return sw.LocationFailure(
        status: sw.LocationFailureStatus.unavailable,
        message: 'test denied',
      );
    }
    return sw.LocationSuccess(
      position: sw.Position(
        coordinates: sw.Coordinates(lat: 25.0330, lng: 121.5654),
        source: sw.PositionSource.gps,
        accuracyMeters: 10,
        observedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
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
    message: 'test',
  );
}
