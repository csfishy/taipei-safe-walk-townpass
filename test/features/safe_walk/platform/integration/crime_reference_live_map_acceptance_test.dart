import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Opt-in only: SAFE_WALK_CRIME_LIVE_CONFIG is an ignored JSON file containing
// SUPABASE_URL and a public client key. Normal tests neither read it nor connect.
// This verifies real read-only RPC -> production parser/composition -> Flutter
// map markers. Route planning, GPS, TTS and storage are isolated boundaries;
// it is NOT iPhone/device GPS or real route-provider acceptance.
// Public records and coordinates stay in memory and are never logged/saved.
final _configPath = Platform.environment['SAFE_WALK_CRIME_LIVE_CONFIG']?.trim();

final class _RealHttpClients extends HttpOverrides {
  int created = 0;

  HttpClient create() {
    created++;
    // Bypass only flutter_test's default fake HTTP client, preserving normal
    // TLS verification. Production SupabaseRpcClient owns/closes each client.
    return super.createHttpClient(null);
  }
}

final class _MemoryHome implements HomeLocationStore {
  _MemoryHome(sw.Coordinates at)
    : value = jsonEncode({'lat': at.lat, 'lng': at.lng});

  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

final class _NoDevicePlatform implements PlatformService {
  int gpsCalls = 0;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    gpsCalls++;
    throw StateError(
      'This acceptance check requires an artificial manual start',
    );
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async => throw StateError('No emergency actions in this acceptance check');
}

final class _SilentSpeaker implements SafeWalkRouteSpeaker {
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

final class _IsolatedRouteService implements RouteService {
  bool called = false;

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    called = true;
    // Only a synthetic line for a stable viewport; never a real road claim.
    return sw.RouteSuccess(
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      warnings: const ['人工路線僅供地圖驗收，不代表真實步行路線。'],
      routes: [
        sw.RouteCandidate(
          id: 'isolated-acceptance-line',
          kind: sw.RouteKind.direct,
          geometry: sw.LineString(
            coordinates: [
              (
                latitude: request.origin.coordinates.lat,
                longitude: request.origin.coordinates.lng,
              ),
              (
                latitude: request.destination.lat,
                longitude: request.destination.lng,
              ),
            ],
          ),
          distanceMeters: 200,
          durationSeconds: null,
          viaPointIds: const [],
          provider: 'isolated-acceptance-only',
          walkingNetworkVerified: false,
          explanations: const [],
          warnings: const [],
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'live crime RPC renders source-labelled markers and 50m product buffers',
    (tester) async {
      final Map<String, String> environment;
      try {
        environment = Map<String, String>.from(
          jsonDecode(File(_configPath!).readAsStringSync()) as Map,
        );
      } catch (_) {
        fail('Could not read the explicit live public-client configuration');
      }
      final http = _RealHttpClients();
      final wiring = CrimeReferenceWiring.fromEnvironment(
        environment: environment,
        createClient: (config) =>
            SupabaseRpcClient(config: config, createHttpClient: http.create),
      );
      expect(wiring.repository.isConfigured, isTrue);
      final seed = await tester.runAsync(
        () => wiring.repository.query(
          mode: sw.DataMode.live,
          query: const CrimeReferenceQuery(city: '臺北市', limit: 200),
        ),
      );
      expect(seed != null, isTrue);
      final located = seed!.records.where(
        (r) => r.latitude != null && r.longitude != null,
      );
      expect(located.isNotEmpty, isTrue);
      final reference = located.first;
      // Artificial trip about a public reference location, never device GPS.
      final origin = sw.Coordinates(
        lat: reference.latitude! - 0.001,
        lng: reference.longitude! - 0.001,
      );
      final destination = sw.Coordinates(
        lat: reference.latitude! + 0.001,
        lng: reference.longitude! + 0.001,
      );
      final platform = _NoDevicePlatform();
      final routes = _IsolatedRouteService();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SafeWalkCompositionRoot(
            liveRoutes: true,
            showLiveMap: false,
            crimeRepository: wiring.repository,
            platform: platform,
            routeService: routes,
            homeLocationStore: _MemoryHome(destination),
            speaker: _SilentSpeaker(),
            watchPosition: () => const Stream.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final flow = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      // Invoke the same selected-start boundary used by the manual map picker.
      flow.onStartChanged!(origin);
      expect(http.created, 1, reason: 'opening the feature must not query');
      await tester.runAsync(() async {
        await tester.tap(find.text('點擊開始'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('同意'));
        await tester.pumpAndSettle();
        expect(find.text('犯罪參考資料查詢同意'), findsOneWidget);
        expect(
          http.created,
          1,
          reason: 'route consent must not grant crime consent',
        );
        await tester.tap(find.text('同意查詢'));
      });
      await tester.pump();
      // Alternate real I/O time and Flutter microtask/frame delivery. Waiting
      // on a Completer from the fake event zone would strand its continuation.
      final deadline = Stopwatch()..start();
      while (!routes.called && deadline.elapsed < const Duration(seconds: 25)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(
        routes.called,
        isTrue,
        reason: 'live query must settle before routing',
      );
      await tester.pumpAndSettle();
      expect(
        http.created,
        2,
        reason: 'one discovery read and one live bbox read',
      );
      expect(platform.gpsCalls, 0);
      final map = tester.widget<DemoMap>(find.byType(DemoMap));
      expect(map.crimeSpots.isNotEmpty, isTrue);
      expect(map.showTiles, isFalse);
      final spotId =
          'crime-${reference.source.sourceKey}-${reference.sourceRecordId}';
      final shown = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      final matched = shown.crimeSpots.where((spot) => spot.id == spotId);
      expect(
        matched.length,
        1,
        reason: 'the real reference must reach the map',
      );
      final label = matched.single.label;
      expect(label.contains(reference.source.name), isTrue);
      expect(label.contains(reference.source.sourceUrl.toString()), isTrue);
      expect(label.contains('位置精度：'), isTrue);
      expect(label.contains('50 公尺'), isTrue);
      final circles = tester
          .widget<CircleLayer>(find.byType(CircleLayer))
          .circles;
      expect(circles.length, map.crimeSpots.length);
      expect(
        circles.every(
          (circle) => circle.useRadiusInMeter && circle.radius == 50,
        ),
        isTrue,
      );
      expect(
        shown.crimeQueryStatus?.contains('已取得') == true,
        isTrue,
        reason: 'the map must expose a successful real lookup',
      );
      // Counts only: no key, URL, source row, place text or coordinate output.
      // ignore: avoid_print
      print(
        'Live crime map acceptance: snapshot=${seed.snapshot.recordCount}, '
        'sources=${seed.sources.length}, cityPage=${seed.records.length}, '
        'markers=${map.crimeSpots.length}, buffers=${circles.length}, '
        'realRpcCalls=${http.created}, deviceGpsCalls=${platform.gpsCalls}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip: _configPath == null || _configPath!.isEmpty,
    timeout: const Timeout(Duration(seconds: 75)),
  );
}
