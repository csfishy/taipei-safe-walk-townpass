import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final _now = DateTime.utc(2026, 11, 7, 3, 30);

sw.RouteRequest _request({
  String id = 'request-1',
  sw.DataMode mode = sw.DataMode.mock,
  sw.PositionSource? source,
  DateTime? observedAt,
}) {
  final positionSource =
      source ??
      (mode == sw.DataMode.mock
          ? sw.PositionSource.mock
          : sw.PositionSource.gps);
  return sw.RouteRequest(
    requestId: id,
    mode: mode,
    origin: sw.Position(
      coordinates: sw.Coordinates(lat: 25, lng: 121.5),
      source: positionSource,
      accuracyMeters: positionSource == sw.PositionSource.gps ? 10 : null,
      observedAt: positionSource == sw.PositionSource.gps
          ? (observedAt ?? _now).toIso8601String()
          : null,
    ),
    destination: sw.Coordinates(lat: 25.001, lng: 121.501),
    departAt: _now.toIso8601String(),
    preference: sw.RouteKind.direct,
    maxExtraDistanceMeters: 300,
    assistancePointIds: const [],
  );
}

sw.RouteSuccess _success(
  sw.RouteRequest request, {
  String? id,
  sw.DataMode? mode,
  bool? verified,
  String? provider,
}) => sw.RouteSuccess(
  requestId: id ?? request.requestId,
  mode: mode ?? request.mode,
  generatedAt: _now.toIso8601String(),
  warnings: const ['測試路線，不保證安全'],
  routes: [
    sw.RouteCandidate(
      id: 'route-1',
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: const [
          (longitude: 121.5, latitude: 25),
          (longitude: 121.501, latitude: 25.001),
        ],
      ),
      distanceMeters: 150,
      durationSeconds: null,
      viaPointIds: const [],
      provider:
          provider ??
          (request.mode == sw.DataMode.mock ? 'mock-test' : 'test-walking'),
      walkingNetworkVerified: verified ?? request.mode == sw.DataMode.live,
      explanations: const ['測試'],
      warnings: const ['不保證安全'],
    ),
  ],
);

final class _FakeRouteService implements RouteService {
  _FakeRouteService(this.run);

  final Future<sw.RouteResult> Function(sw.RouteRequest) run;
  final List<sw.RouteRequest> requests = [];
  final List<SafeWalkCancellation> cancellations = [];

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    requests.add(request);
    cancellations.add(cancellation!);
    return run(request);
  }
}

SafeWalkNavigationController _controller(
  RouteService service, {
  sw.DataMode mode = sw.DataMode.mock,
  bool presentation = false,
  bool provider = false,
}) => SafeWalkNavigationController(
  routeService: service,
  mode: mode,
  livePresentationReady: presentation,
  liveProviderReady: provider,
  clock: () => _now,
);

void main() {
  test(
    'M2 default mock service returns the shared route with warnings',
    () async {
      final controller = _controller(DefaultRouteService(clock: () => _now));
      addTearDown(controller.dispose);
      expect(controller.routeResult, isNull);
      expect(controller.routeLoading, isFalse);
      expect(controller.hasRoutingConsent, isFalse);
      expect(controller.liveNavigationAvailable, isFalse);

      await controller.planRoute(_request());

      final result = controller.routeResult as sw.RouteSuccess;
      expect(result.requestId, 'request-1');
      expect(result.mode, sw.DataMode.mock);
      expect(result.routes.single.provider, 'mock-straight-line');
      expect(result.routes.single.durationSeconds, isNull);
      expect(result.routes.single.walkingNetworkVerified, isFalse);
      expect(result.warnings.join(), contains('示範'));
      expect(controller.routeLoading, isFalse);
      expect(controller.routeError, isNull);
    },
  );

  test(
    'new destination cancels old request and ignores its late success',
    () async {
      final first = Completer<sw.RouteResult>();
      final second = Completer<sw.RouteResult>();
      final service = _FakeRouteService(
        (request) =>
            request.requestId == 'first' ? first.future : second.future,
      );
      final controller = _controller(service);
      addTearDown(controller.dispose);
      final a = _request(id: 'first');
      final b = _request(id: 'second');

      final firstPlan = controller.planRoute(a);
      expect(controller.routeLoading, isTrue);
      final secondPlan = controller.planRoute(b);
      expect(service.cancellations.first.isCancelled, isTrue);
      expect(controller.routeResult, isNull);
      expect(controller.routeError, isNull);
      second.complete(_success(b));
      await secondPlan;
      first.complete(_success(a));
      await firstPlan;

      expect(controller.routeResult!.requestId, 'second');
      expect(controller.routeLoading, isFalse);
    },
  );

  test('reusing a request ID cannot revive an older request', () async {
    final pending = [Completer<sw.RouteResult>(), Completer<sw.RouteResult>()];
    var next = 0;
    final service = _FakeRouteService((_) => pending[next++].future);
    final controller = _controller(service);
    addTearDown(controller.dispose);
    final request = _request();
    final first = controller.planRoute(request);
    final second = controller.planRoute(request);
    final current = _success(request);
    pending.last.complete(current);
    await second;
    pending.first.complete(_success(request));
    await first;
    expect(controller.routeResult, same(current));
    expect(service.cancellations.first.isCancelled, isTrue);
  });

  test(
    'cancel finishes immediately and observes a late provider error',
    () async {
      final pending = Completer<sw.RouteResult>();
      final service = _FakeRouteService((_) => pending.future);
      final controller = _controller(service);
      addTearDown(controller.dispose);
      final work = controller.planRoute(_request());

      controller.cancelRoute();
      await work;
      expect(service.cancellations.single.isCancelled, isTrue);
      expect(controller.routeLoading, isFalse);
      expect(controller.routeResult, isNull);
      expect(controller.routeError, isNull);
      pending.completeError(
        StateError('late coordinate-bearing service error'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.routeResult, isNull);
    },
  );

  test(
    'cancel clears a completed route before selecting another destination',
    () async {
      final service = _FakeRouteService((request) async => _success(request));
      final controller = _controller(service);
      addTearDown(controller.dispose);
      await controller.planRoute(_request());
      controller.cancelRoute();
      expect(controller.routeResult, isNull);
      expect(controller.routeLoading, isFalse);
      expect(controller.routeError, isNull);
    },
  );

  test(
    'dispose cancels outstanding work and suppresses late notifications',
    () async {
      final pending = Completer<sw.RouteResult>();
      final service = _FakeRouteService((_) => pending.future);
      final controller = _controller(service);
      var changes = 0;
      controller.addListener(() => changes++);
      final request = _request();
      final work = controller.planRoute(request);
      controller.dispose();
      await work;
      final countAfterDispose = changes;
      pending.complete(_success(request));
      await Future<void>.delayed(Duration.zero);
      expect(service.cancellations.single.isCancelled, isTrue);
      expect(changes, countAfterDispose);
      expect(controller.routeResult, isNull);
      await controller.planRoute(request);
      expect(service.requests, hasLength(1));
    },
  );

  test('synchronous service throw becomes a sanitized failure', () async {
    final service = _FakeRouteService(
      (_) => throw StateError('private latitude URL'),
    );
    final controller = _controller(service);
    addTearDown(controller.dispose);
    await controller.planRoute(_request());
    final failure = controller.routeResult as sw.RouteFailure;
    expect(failure.status, sw.RouteFailureStatus.providerUnavailable);
    expect(controller.routeError, isNot(contains('private')));
    expect(controller.routeLoading, isFalse);
    expect(failure.routes, isEmpty);
  });

  test(
    'provider no-route remains an error without creating a mock result',
    () async {
      final service = _FakeRouteService(
        (request) async => sw.RouteFailure(
          requestId: request.requestId,
          mode: request.mode,
          generatedAt: _now.toIso8601String(),
          status: sw.RouteFailureStatus.noRoute,
          reason: '找不到路線',
          warnings: const ['沒有路線'],
        ),
      );
      final controller = _controller(service);
      addTearDown(controller.dispose);
      await controller.planRoute(_request());
      expect(controller.routeError, '找不到路線');
      expect((controller.routeResult as sw.RouteFailure).routes, isEmpty);
    },
  );

  for (final invalid in [
    (
      name: 'mock request in live controller',
      controllerMode: sw.DataMode.live,
      request: _request(),
    ),
    (
      name: 'live request in mock controller',
      controllerMode: sw.DataMode.mock,
      request: _request(mode: sw.DataMode.live),
    ),
    (
      name: 'GPS position in mock session',
      controllerMode: sw.DataMode.mock,
      request: _request(source: sw.PositionSource.gps),
    ),
    (
      name: 'mock position in live session',
      controllerMode: sw.DataMode.live,
      request: _request(mode: sw.DataMode.live, source: sw.PositionSource.mock),
    ),
    (
      name: 'stale GPS position',
      controllerMode: sw.DataMode.live,
      request: _request(
        mode: sw.DataMode.live,
        observedAt: _now.subtract(const Duration(seconds: 61)),
      ),
    ),
  ]) {
    test('rejects ${invalid.name} before calling M2', () async {
      final service = _FakeRouteService((request) async => _success(request));
      final controller = _controller(
        service,
        mode: invalid.controllerMode,
        presentation: true,
        provider: true,
      );
      addTearDown(controller.dispose);
      controller.setRoutingConsent(true);
      await controller.planRoute(invalid.request);
      expect(service.requests, isEmpty);
      expect(
        (controller.routeResult as sw.RouteFailure).status,
        sw.RouteFailureStatus.invalidInput,
      );
      expect(controller.routeError, isNotNull);
    });
  }

  for (final gates in [
    (presentation: false, provider: true, consent: true),
    (presentation: true, provider: false, consent: true),
    (presentation: true, provider: true, consent: false),
  ]) {
    test(
      'live requires UI, provider and explicit routing consent: $gates',
      () async {
        final service = _FakeRouteService((request) async => _success(request));
        final controller = _controller(
          service,
          mode: sw.DataMode.live,
          presentation: gates.presentation,
          provider: gates.provider,
        );
        addTearDown(controller.dispose);
        controller.setRoutingConsent(gates.consent);
        await controller.planRoute(_request(mode: sw.DataMode.live));
        expect(service.requests, isEmpty);
        expect(
          (controller.routeResult as sw.RouteFailure).status,
          sw.RouteFailureStatus.providerUnavailable,
        );
      },
    );
  }

  test(
    'live routes only after all gates; revoke cancels and clears data',
    () async {
      final pending = Completer<sw.RouteResult>();
      final service = _FakeRouteService((_) => pending.future);
      final controller = _controller(
        service,
        mode: sw.DataMode.live,
        presentation: true,
        provider: true,
      );
      addTearDown(controller.dispose);
      final request = _request(mode: sw.DataMode.live);
      controller.setRoutingConsent(true);
      final work = controller.planRoute(request);
      expect(service.requests, hasLength(1));
      controller.setRoutingConsent(false);
      await work;
      expect(service.cancellations.single.isCancelled, isTrue);
      pending.complete(_success(request));
      await Future<void>.delayed(Duration.zero);
      expect(controller.hasRoutingConsent, isFalse);
      expect(controller.routeLoading, isFalse);
      expect(controller.routeResult, isNull);
      await controller.planRoute(request);
      expect(service.requests, hasLength(1));
    },
  );

  for (final mismatch in [
    'requestId',
    'mode',
    'unverified live',
    'mock live',
  ]) {
    test('rejects a $mismatch result from an injected service', () async {
      final live = mismatch.endsWith('live');
      final mode = live ? sw.DataMode.live : sw.DataMode.mock;
      final service = _FakeRouteService(
        (request) async => _success(
          request,
          id: mismatch == 'requestId' ? 'wrong-request' : null,
          mode: mismatch == 'mode' ? sw.DataMode.live : null,
          verified: mismatch == 'unverified live' ? false : null,
          provider: mismatch == 'mock live' ? 'mock-route' : null,
        ),
      );
      final controller = _controller(
        service,
        mode: mode,
        presentation: true,
        provider: true,
      );
      addTearDown(controller.dispose);
      controller.setRoutingConsent(true);
      await controller.planRoute(_request(mode: mode));
      final failure = controller.routeResult as sw.RouteFailure;
      expect(failure.status, sw.RouteFailureStatus.providerUnavailable);
      expect(failure.mode, mode);
      expect(failure.requestId, 'request-1');
      expect(controller.routeError, contains('已拒絕'));
    });
  }

  test(
    'a listener cancelling loading prevents the initial service call',
    () async {
      final service = _FakeRouteService((request) async => _success(request));
      final controller = _controller(service);
      addTearDown(controller.dispose);
      controller.addListener(() {
        if (controller.routeLoading) controller.cancelRoute();
      });
      await controller.planRoute(_request());
      expect(service.requests, isEmpty);
      expect(controller.routeLoading, isFalse);
    },
  );
}
