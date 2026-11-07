import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

void main() {
  Future<void> mount(WidgetTester t, RouteService routes, PlatformService gps, {Stream<sw.Position> Function()? watch, bool home = true}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = _MemStore();
    if (home) await HomeLocationService(store).save(25.0400, 121.5650);
    await t.pumpWidget(MaterialApp(home: SafeWalkCompositionRoot(liveRoutes: true, routeService: routes, platform: gps, watchPosition: watch, homeLocationStore: store)));
    await t.pumpAndSettle();
    await t.tap(find.text('點擊開始'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opening the map asks consent, then plans a live route from GPS', (t) async {
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
  });

  testWidgets('follows the route, re-plans when off every option, stops when leaving the map', (t) async {
    final routes = _Answering();
    final positions = StreamController<sw.Position>();
    var listening = false;
    positions.onListen = () => listening = true;
    positions.onCancel = () => listening = false;
    await mount(t, routes, _Gps(), watch: () => positions.stream);
    await t.tap(find.text('同意'));
    await t.pumpAndSettle();
    expect(routes.requests, hasLength(1));
    expect(listening, isTrue, reason: 'GPS follows once a live route exists');

    positions.add(_at(25.0330, 121.5655)); // on the route
    await t.pump();
    expect(routes.requests, hasLength(1));

    positions.add(_at(25.0400, 121.5655)); // ~780 m north: off route
    await t.pumpAndSettle();
    expect(routes.requests, hasLength(2));
    expect(routes.requests.last.origin.coordinates.lat, 25.0400);

    await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).first);
    await t.pumpAndSettle();
    expect(listening, isFalse, reason: 'leaving the map stops GPS');
  });

  group('late answers after the user moved on send nothing', () {
    Future<_SlowGps> started(WidgetTester t, _Routes routes) async {
      final gps = _SlowGps();
      await mount(t, routes, gps);
      await t.tap(find.text('同意'));
      await t.pump();
      expect(gps.pending, hasLength(1), reason: 'GPS asked, not answered yet');
      return gps;
    }

    testWidgets('leaving the map', (t) async {
      final routes = _Routes();
      final gps = await started(t, routes);
      await t.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).first);
      await t.pumpAndSettle();
      gps.answer(0);
      await t.pumpAndSettle();
      expect(routes.requests, isEmpty);
    });

    testWidgets('going to the background', (t) async {
      final routes = _Routes();
      final gps = await started(t, routes);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      gps.answer(0);
      await t.pumpAndSettle();
      expect(routes.requests, isEmpty);
    });

    testWidgets('opening SOS', (t) async {
      final routes = _Routes();
      final gps = await started(t, routes);
      await t.tap(find.textContaining('緊急求助').first);
      await t.pumpAndSettle();
      gps.answer(0);
      await t.pumpAndSettle();
      expect(routes.requests, isEmpty);
    });

    testWidgets('changing destination: only the new plan reaches the route service', (t) async {
      final routes = _Routes();
      final gps = await started(t, routes);
      await t.tap(find.textContaining('→ 家'));
      await t.pumpAndSettle();
      await t.tap(find.text('公司'));
      await t.pumpAndSettle();
      expect(gps.pending, hasLength(2));
      gps.answer(0); // the old plan's late GPS
      await t.pumpAndSettle();
      expect(routes.requests, isEmpty);
      gps.answer(1);
      await t.pumpAndSettle();
      expect(routes.requests.single.destination.lat, closeTo(25.114604, 1e-6));
    });
  });

  testWidgets('without a saved home, live planning asks for home and sends nothing', (t) async {
    final routes = _Routes();
    final gps = _Gps();
    await mount(t, routes, gps, home: false);
    expect(find.text('規劃路線需要你的位置'), findsNothing);
    expect(gps.calls, 0);
    expect(routes.requests, isEmpty);
  });

  testWidgets('declining consent sends nothing', (t) async {
    final routes = _Routes();
    final gps = _Gps();
    await mount(t, routes, gps);
    await t.tap(find.text('不要'));
    await t.pump();
    expect(gps.calls, 0);
    expect(routes.requests, isEmpty);
  });
}

final class _Routes implements RouteService {
  final requests = <sw.RouteRequest>[];
  @override
  Future<sw.RouteResult> planRoute(sw.RouteRequest request, {SafeWalkCancellation? cancellation}) {
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
  Future<sw.RouteResult> planRoute(sw.RouteRequest request, {SafeWalkCancellation? cancellation}) async {
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
          geometry: sw.LineString(coordinates: [(longitude: o.lng, latitude: o.lat), (longitude: request.destination.lng, latitude: request.destination.lat)]),
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
  @override
  Future<sw.LocationResult> getCurrentPosition({required sw.DataMode mode, required bool userInitiated, SafeWalkCancellation? cancellation}) async {
    if (mode == sw.DataMode.mock) {
      return sw.LocationFailure(status: sw.LocationFailureStatus.unavailable, message: 'mock');
    }
    calls++;
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
  Future<sw.EmergencyActionResult> requestEmergency({required sw.DataMode mode, required sw.EmergencyChannel channel, required bool userInitiated, required bool allowRealCalls, sw.IncidentSummary? summary}) async =>
      sw.EmergencyActionResult(channel: channel, action: sw.EmergencyAction.notConfigured, message: 'test');
}

final class _MemStore implements HomeLocationStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> clear() async => value = null;
}

/// GPS that answers only when the test says so.
final class _SlowGps implements PlatformService {
  final pending = <Completer<sw.LocationResult>>[];
  void answer(int i) => pending[i].complete(
    sw.LocationSuccess(
      position: sw.Position(
        coordinates: sw.Coordinates(lat: 25.0330, lng: 121.5654),
        source: sw.PositionSource.gps,
        accuracyMeters: 10,
        observedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    ),
  );

  @override
  Future<sw.LocationResult> getCurrentPosition({required sw.DataMode mode, required bool userInitiated, SafeWalkCancellation? cancellation}) {
    if (mode == sw.DataMode.mock) {
      return Future.value(sw.LocationFailure(status: sw.LocationFailureStatus.unavailable, message: 'mock'));
    }
    final c = Completer<sw.LocationResult>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({required sw.DataMode mode, required sw.EmergencyChannel channel, required bool userInitiated, required bool allowRealCalls, sw.IncidentSummary? summary}) async =>
      sw.EmergencyActionResult(channel: channel, action: sw.EmergencyAction.notConfigured, message: 'test');
}
