import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// These exercise M1's published scope boundary. M3 does not consume the new
// route callbacks yet; these are not assertions about its current map or SOS UI.
SafeWalkNavigationScope _scope(WidgetTester tester) => tester
    .element(find.byType(SafeWalkFlow))
    .getInheritedWidgetOfExactType<SafeWalkNavigationScope>()!;

sw.RouteRequest _request(
  SafeWalkNavigationScope scope, {
  sw.RouteKind? preference,
  List<String>? ids,
}) => scope.createRouteRequest(
  origin: sw.Position(
    coordinates: sw.Coordinates(lat: 25, lng: 121.5),
    source: sw.PositionSource.mock,
    accuracyMeters: null,
    observedAt: null,
  ),
  destination: sw.Coordinates(lat: 25.001, lng: 121.5012),
  preference: preference,
  assistancePointIds: ids,
);

sw.RouteSuccess _success(sw.RouteRequest request) => sw.RouteSuccess(
  requestId: request.requestId,
  mode: request.mode,
  generatedAt: DateTime.now().toUtc().toIso8601String(),
  warnings: const ['人工示範，不保證安全'],
  routes: [
    sw.RouteCandidate(
      id: 'test-route',
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: const [
          (longitude: 121.5, latitude: 25),
          (longitude: 121.5012, latitude: 25.001),
        ],
      ),
      distanceMeters: 170,
      durationSeconds: null,
      viaPointIds: const [],
      provider: 'mock-wiring-test',
      walkingNetworkVerified: false,
      explanations: const ['測試資料'],
      warnings: const ['禁止實地導航'],
    ),
  ],
);

Future<void> _mount(
  WidgetTester tester, {
  RouteService? routes,
  JsonTransport? transport,
  PlatformService? platform,
  VoidCallback? onExit,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SafeWalkCompositionRoot(
        mode: sw.DataMode.mock,
        routeService: routes,
        routeTransport: transport,
        platform: platform,
        onExit: onExit,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Routes implements RouteService {
  final requests = <sw.RouteRequest>[];
  final cancellations = <SafeWalkCancellation>[];
  final completions = <Completer<sw.RouteResult>>[];

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    requests.add(request);
    cancellations.add(cancellation!);
    final pending = Completer<sw.RouteResult>();
    completions.add(pending);
    return pending.future;
  }
}

final class _NoNetwork implements JsonTransport {
  int gets = 0, posts = 0;

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) async {
    gets++;
    throw StateError('The Mock composition must not call a transport');
  }

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) async {
    posts++;
    throw StateError('The Mock composition must not call Overpass');
  }
}

final class _Platform implements PlatformService {
  int locations = 0, emergencies = 0;
  void Function()? beforeEmergency;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    locations++;
    return sw.LocationFailure(
      status: sw.LocationFailureStatus.unavailable,
      message: '測試不取 GPS',
    );
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async {
    beforeEmergency?.call();
    expect(mode, sw.DataMode.mock);
    expect(userInitiated, isTrue);
    expect(allowRealCalls, isFalse);
    expect(summary, isNull);
    emergencies++;
    return sw.EmergencyActionResult(
      channel: channel,
      action: sw.EmergencyAction.notConfigured,
      message: '示範：未撥號、未傳送。',
    );
  }
}

void main() {
  testWidgets(
    'scope plans with default M2 Mock service without network or GPS',
    (tester) async {
      final platform = _Platform();
      final transport = _NoNetwork();
      await _mount(tester, platform: platform, transport: transport);
      final scope = _scope(tester);
      expect(scope.mode, sw.DataMode.mock);
      expect(scope.liveNavigationAvailable, isFalse);
      expect(scope.hasRoutingConsent, isFalse);
      expect(scope.routeResult, isNull);
      expect(platform.locations, 0);

      final request = _request(scope);
      expect(request.requestId, startsWith('m1-route-'));
      expect(request.mode, sw.DataMode.mock);
      expect(DateTime.tryParse(request.departAt), isNotNull);
      await scope.onPlanRoute(request);
      expect(_scope(tester).routeResult, isNull);
      scope.onNavigationOpened();
      await scope.onPlanRoute(request);
      await tester.pump();

      final result = _scope(tester).routeResult as sw.RouteSuccess;
      expect(result.requestId, request.requestId);
      expect(result.routes.single.provider, 'mock-straight-line');
      expect(result.routes.single.walkingNetworkVerified, isFalse);
      expect(result.warnings.join(), contains('示範'));
      expect(_scope(tester).routeLoading, isFalse);
      expect(_scope(tester).routeError, isNull);
      expect(platform.locations, 0);
      expect(platform.emergencies, 0);
      expect(transport.gets + transport.posts, 0);
    },
  );

  testWidgets('scope resolves via IDs using the validated M4 point snapshot', (
    tester,
  ) async {
    final transport = _NoNetwork();
    await _mount(tester, transport: transport);
    final scope = _scope(tester);
    scope.onNavigationOpened();
    final via = _request(
      scope,
      preference: sw.RouteKind.viaAssistance,
      ids: const ['demo-point-1'],
    );
    await scope.onPlanRoute(via);
    await tester.pump();
    final result = _scope(tester).routeResult as sw.RouteSuccess;
    expect(result.routes.single.kind, sw.RouteKind.viaAssistance);
    expect(result.routes.single.viaPointIds, ['demo-point-1']);

    final missing = _request(
      scope,
      preference: sw.RouteKind.viaAssistance,
      ids: const ['missing-point'],
    );
    expect(missing.requestId, isNot(via.requestId));
    await scope.onPlanRoute(missing);
    await tester.pump();
    final failure = _scope(tester).routeResult as sw.RouteFailure;
    expect(failure.status, sw.RouteFailureStatus.invalidInput);
    expect(failure.routes, isEmpty);
    expect(_scope(tester).routeError, isNotNull);
    expect(transport.gets + transport.posts, 0);
  });

  testWidgets('scope consent cannot enable Live in the Mock composition', (
    tester,
  ) async {
    final routes = _Routes();
    await _mount(tester, routes: routes);
    final scope = _scope(tester);
    scope.onNavigationOpened();
    scope.onRoutingConsentChanged(true);
    final request = _request(scope).toJson();
    request['mode'] = 'live';
    await scope.onPlanRoute(sw.RouteRequest.fromJson(request));
    await tester.pump();
    expect(_scope(tester).hasRoutingConsent, isTrue);
    expect(_scope(tester).liveNavigationAvailable, isFalse);
    expect(routes.requests, isEmpty);
    expect(
      (_scope(tester).routeResult as sw.RouteFailure).status,
      sw.RouteFailureStatus.invalidInput,
    );
  });

  for (final operation in ['destination', 'cancel', 'close', 'emergency']) {
    testWidgets(
      'scope $operation cancels pending route and rejects its late result',
      (tester) async {
        final routes = _Routes();
        await _mount(tester, routes: routes);
        final scope = _scope(tester);
        scope.onNavigationOpened();
        final request = _request(scope);
        final work = scope.onPlanRoute(request);
        await tester.pump();
        expect(_scope(tester).routeLoading, isTrue);
        switch (operation) {
          case 'destination':
            scope.onDestinationChanged();
          case 'cancel':
            scope.onCancelRoute();
          case 'close':
            scope.onNavigationClosed();
          case 'emergency':
            scope.onEmergencyOpened();
        }
        await work;
        await tester.pump();
        expect(routes.cancellations.single.isCancelled, isTrue);
        expect(_scope(tester).routeLoading, isFalse);
        expect(_scope(tester).routeResult, isNull);
        expect(_scope(tester).routeError, isNull);
        routes.completions.single.complete(_success(request));
        await tester.pump();
        expect(_scope(tester).routeResult, isNull);

        if (operation == 'close' || operation == 'emergency') {
          await scope.onPlanRoute(_request(scope));
          expect(routes.requests, hasLength(1));
          scope.onNavigationOpened();
          final retry = scope.onPlanRoute(_request(scope));
          expect(routes.requests, hasLength(2));
          scope.onCancelRoute();
          await retry;
          routes.completions.last.complete(_success(routes.requests.last));
          await tester.pump();
        }
      },
    );
  }

  testWidgets(
    'background cancels scope work and resume requires explicit reentry',
    (tester) async {
      final routes = _Routes();
      await _mount(tester, routes: routes);
      final scope = _scope(tester);
      scope.onNavigationOpened();
      final work = scope.onPlanRoute(_request(scope));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await work;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(routes.cancellations.single.isCancelled, isTrue);
      expect(_scope(tester).routeResult, isNull);
      expect(_scope(tester).routeLoading, isFalse);
      await scope.onPlanRoute(_request(scope));
      expect(routes.requests, hasLength(1));
      routes.completions.single.complete(_success(routes.requests.single));
      await tester.pump();
      expect(_scope(tester).routeResult, isNull);
      scope.onNavigationOpened();
      final retry = scope.onPlanRoute(_request(scope));
      expect(routes.requests, hasLength(2));
      scope.onCancelRoute();
      await retry;
      routes.completions.last.complete(_success(routes.requests.last));
      await tester.pump();
    },
  );

  testWidgets(
    'custom exit cancels scope work even while its widget stays mounted',
    (tester) async {
      final routes = _Routes();
      var exits = 0;
      await _mount(tester, routes: routes, onExit: () => exits++);
      final scope = _scope(tester);
      scope.onNavigationOpened();
      final work = scope.onPlanRoute(_request(scope));
      tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).onExit!();
      await work;
      await tester.pump();
      expect(exits, 1);
      expect(find.byType(SafeWalkFlow), findsOneWidget);
      expect(routes.cancellations.single.isCancelled, isTrue);
      scope.onNavigationOpened();
      await scope.onPlanRoute(_request(scope));
      expect(routes.requests, hasLength(1));
      routes.completions.single.complete(_success(routes.requests.single));
      await tester.pump();
      expect(_scope(tester).routeResult, isNull);
    },
  );

  testWidgets(
    'disposing the composition cancels route and observes late errors',
    (tester) async {
      final routes = _Routes();
      await _mount(tester, routes: routes);
      final scope = _scope(tester);
      scope.onNavigationOpened();
      final work = scope.onPlanRoute(_request(scope));
      await tester.pumpWidget(const SizedBox.shrink());
      await work;
      expect(routes.cancellations.single.isCancelled, isTrue);
      routes.completions.single.completeError(
        StateError('late synthetic failure'),
      );
      await tester.pump();
      expect(find.byType(SafeWalkFlow), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'emergency channel fallback cancels route before Mock platform action',
    (tester) async {
      final routes = _Routes();
      final platform = _Platform();
      await _mount(tester, routes: routes, platform: platform);
      final scope = _scope(tester);
      scope.onNavigationOpened();
      final work = scope.onPlanRoute(_request(scope));
      platform.beforeEmergency = () =>
          expect(routes.cancellations.single.isCancelled, isTrue);
      final action = await tester
          .widget<SafeWalkFlow>(find.byType(SafeWalkFlow))
          .onEmergency!(sw.EmergencyChannel.police);
      await work;
      await tester.pump();
      expect(platform.emergencies, 1);
      expect(platform.locations, 0);
      expect(action.action, sw.EmergencyAction.notConfigured);
      expect(action.officialReceipt, isNull);
      expect(_scope(tester).routeResult, isNull);
      await scope.onPlanRoute(_request(scope));
      expect(routes.requests, hasLength(1));
      routes.completions.single.complete(_success(routes.requests.single));
      await tester.pump();
      expect(_scope(tester).routeResult, isNull);
    },
  );
}
