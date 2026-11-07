import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

void main() {
  Future<void> mount(WidgetTester t, _Routes routes, _Gps gps) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: SafeWalkCompositionRoot(liveRoutes: true, routeService: routes, platform: gps)));
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
