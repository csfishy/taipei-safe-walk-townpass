import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_live_navigation_coordinator.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final _now = DateTime.utc(2026, 11, 7, 3, 30);
final _destination = sw.Coordinates(lat: 25.035, lng: 121.52);

sw.LocationSuccess _fix({
  sw.PositionSource source = sw.PositionSource.gps,
  double? accuracy = 12,
  DateTime? observedAt,
}) => sw.LocationSuccess(
  position: sw.Position(
    coordinates: sw.Coordinates(lat: 25.03, lng: 121.51),
    source: source,
    accuracyMeters: accuracy,
    observedAt: (observedAt ?? _now).toIso8601String(),
  ),
);

sw.RouteSuccess _success(sw.RouteRequest request) => sw.RouteSuccess(
  requestId: request.requestId,
  mode: sw.DataMode.live,
  generatedAt: _now.toIso8601String(),
  warnings: const ['步行路網不代表安全保證'],
  routes: [
    sw.RouteCandidate(
      id: 'walking-test',
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: [
          (
            longitude: request.origin.coordinates.lng,
            latitude: request.origin.coordinates.lat,
          ),
          (
            longitude: request.destination.lng,
            latitude: request.destination.lat,
          ),
        ],
      ),
      distanceMeters: 1234,
      durationSeconds: null,
      viaPointIds: const [],
      provider: 'synthetic-walking-test',
      walkingNetworkVerified: true,
      explanations: const ['合成資料，不呼叫外部服務'],
      warnings: const ['未實機驗證'],
    ),
  ],
);

final class _Platform implements PlatformService {
  _Platform(this.run);

  final Future<sw.LocationResult> Function() run;
  final calls =
      <({sw.DataMode mode, bool userInitiated, SafeWalkCancellation token})>[];

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    calls.add((mode: mode, userInitiated: userInitiated, token: cancellation!));
    return run();
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) => throw StateError('Navigation must not invoke emergency handoffs');
}

final class _Routes implements RouteService {
  _Routes(this.run);

  final Future<sw.RouteResult> Function(sw.RouteRequest) run;
  final requests = <sw.RouteRequest>[];
  final tokens = <SafeWalkCancellation>[];

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    requests.add(request);
    tokens.add(cancellation!);
    return run(request);
  }
}

({
  SafeWalkLiveNavigationCoordinator coordinator,
  SafeWalkNavigationController controller,
  _Platform platform,
  _Routes routes,
})
_session({
  Future<sw.LocationResult> Function()? locate,
  Future<sw.RouteResult> Function(sw.RouteRequest)? route,
  sw.DataMode mode = sw.DataMode.live,
  bool providerReady = true,
  bool presentationReady = true,
  DateTime Function()? clock,
}) {
  final platform = _Platform(locate ?? () async => _fix());
  final routes = _Routes(route ?? (request) async => _success(request));
  final controller = SafeWalkNavigationController(
    routeService: routes,
    mode: mode,
    liveProviderReady: providerReady,
    livePresentationReady: presentationReady,
    clock: clock ?? () => _now,
  );
  final coordinator = SafeWalkLiveNavigationCoordinator(
    controller: controller,
    platform: platform,
    clock: clock ?? () => _now,
  );
  addTearDown(() {
    coordinator.dispose();
    controller.dispose();
  });
  return (
    coordinator: coordinator,
    controller: controller,
    platform: platform,
    routes: routes,
  );
}

void _allowAndOpen(SafeWalkLiveNavigationCoordinator coordinator) {
  coordinator.setLocationConsent(true);
  coordinator.setRoutingConsent(true);
  coordinator.openNavigation();
}

void main() {
  test('construction, consent and opening do not obtain GPS', () async {
    final s = _session();
    expect(s.coordinator.hasLocationConsent, isFalse);
    expect(s.coordinator.hasRoutingConsent, isFalse);
    expect(s.controller.hasRoutingConsent, isFalse);
    expect(s.coordinator.active, isFalse);
    expect(s.coordinator.foreground, isTrue);
    expect(s.coordinator.position, isNull);
    expect(s.coordinator.locationLoading, isFalse);
    expect(s.coordinator.locationError, isNull);
    _allowAndOpen(s.coordinator);
    expect(s.platform.calls, isEmpty);
    expect(s.routes.requests, isEmpty);
  });

  for (final gates in [
    (open: false, location: true, routing: true),
    (open: true, location: false, routing: true),
    (open: true, location: true, routing: false),
  ]) {
    test('GPS requires explicit open and both consents: $gates', () async {
      final s = _session();
      s.coordinator.setLocationConsent(gates.location);
      s.coordinator.setRoutingConsent(gates.routing);
      if (gates.open) s.coordinator.openNavigation();
      await s.coordinator.planDestination(_destination);
      expect(s.platform.calls, isEmpty);
      expect(s.routes.requests, isEmpty);
      expect(s.coordinator.locationError, isNotNull);
    });
  }

  for (final config in [
    (mode: sw.DataMode.mock, provider: true, presentation: true),
    (mode: sw.DataMode.live, provider: false, presentation: true),
    (mode: sw.DataMode.live, provider: true, presentation: false),
  ]) {
    test('unconfigured live session does not acquire GPS: $config', () async {
      final s = _session(
        mode: config.mode,
        providerReady: config.provider,
        presentationReady: config.presentation,
      );
      _allowAndOpen(s.coordinator);
      await s.coordinator.planDestination(_destination);
      expect(s.platform.calls, isEmpty);
      expect(s.routes.requests, isEmpty);
      expect(s.coordinator.liveNavigationAvailable, isFalse);
    });
  }

  test('explicit plan uses live GPS and canonical direct request', () async {
    final s = _session();
    _allowAndOpen(s.coordinator);
    var notifications = 0;
    s.coordinator.addListener(() => notifications++);
    await s.coordinator.planDestination(_destination);
    final call = s.platform.calls.single;
    expect(call.mode, sw.DataMode.live);
    expect(call.userInitiated, isTrue);
    final request = s.routes.requests.single;
    expect(request.mode, sw.DataMode.live);
    expect(request.origin.toJson(), _fix().position.toJson());
    expect(request.destination.toJson(), _destination.toJson());
    expect(request.departAt, _now.toIso8601String());
    expect(request.preference, sw.RouteKind.direct);
    expect(request.maxExtraDistanceMeters, 500);
    expect(request.assistancePointIds, isEmpty);
    expect(s.coordinator.position!.toJson(), _fix().position.toJson());
    final result = s.coordinator.routeResult as sw.RouteSuccess;
    expect(result.routes.single.distanceMeters, 1234);
    expect(result.routes.single.durationSeconds, isNull);
    expect(s.coordinator.routeLoading, isFalse);
    expect(s.coordinator.routeError, isNull);
    expect(s.coordinator.locationLoading, isFalse);
    expect(s.coordinator.locationError, isNull);
    expect(notifications, greaterThan(1));
    await s.coordinator.planDestination(_destination);
    expect(s.routes.requests.map((r) => r.requestId).toSet(), hasLength(2));
  });

  for (final invalid in [
    (label: 'mock', fix: _fix(source: sw.PositionSource.mock)),
    (label: 'manual', fix: _fix(source: sw.PositionSource.manual)),
    (label: 'missing accuracy', fix: _fix(accuracy: null)),
    (
      label: 'missing observation time',
      fix: sw.LocationSuccess(
        position: sw.Position(
          coordinates: sw.Coordinates(lat: 25.03, lng: 121.51),
          source: sw.PositionSource.gps,
          accuracyMeters: 12,
          observedAt: null,
        ),
      ),
    ),
    (label: 'poor accuracy', fix: _fix(accuracy: 101)),
    (
      label: 'stale',
      fix: _fix(observedAt: _now.subtract(const Duration(seconds: 61))),
    ),
    (
      label: 'future',
      fix: _fix(observedAt: _now.add(const Duration(seconds: 31))),
    ),
  ]) {
    test('rejects ${invalid.label} position without routing', () async {
      final s = _session(locate: () async => invalid.fix);
      _allowAndOpen(s.coordinator);
      await s.coordinator.planDestination(_destination);
      expect(s.coordinator.position, isNull);
      expect(s.coordinator.locationError, isNotNull);
      expect(s.coordinator.locationLoading, isFalse);
      expect(s.routes.requests, isEmpty);
    });
  }

  test('location failure stays unavailable without demo fallback', () async {
    final s = _session(
      locate: () async => sw.LocationFailure(
        status: sw.LocationFailureStatus.denied,
        message: '未允許定位，請調整系統權限。',
      ),
    );
    _allowAndOpen(s.coordinator);
    await s.coordinator.planDestination(_destination);
    expect(s.coordinator.locationError, contains('未允許定位'));
    expect(s.coordinator.position, isNull);
    expect(s.routes.requests, isEmpty);
    expect(s.coordinator.routeResult, isNull);
  });

  test('synchronous platform exception is sanitized', () async {
    final s = _session(locate: () => throw StateError('private location URL'));
    _allowAndOpen(s.coordinator);
    await s.coordinator.planDestination(_destination);
    expect(s.coordinator.locationError, isNot(contains('private')));
    expect(s.coordinator.locationError, isNotNull);
    expect(s.routes.requests, isEmpty);
  });

  test(
    'provider failure is forwarded without a demo route or invented time',
    () async {
      final s = _session(
        route: (request) async => sw.RouteFailure(
          requestId: request.requestId,
          mode: sw.DataMode.live,
          generatedAt: _now.toIso8601String(),
          status: sw.RouteFailureStatus.noRoute,
          reason: '找不到可用步行路線。',
          warnings: const ['未改用示範路線'],
        ),
      );
      _allowAndOpen(s.coordinator);
      await s.coordinator.planDestination(_destination);
      expect(s.coordinator.routeResult, isA<sw.RouteFailure>());
      expect(s.coordinator.routeResult, same(s.controller.routeResult));
      expect(s.coordinator.routeError, '找不到可用步行路線。');
      expect(s.coordinator.locationError, isNull);
      expect(s.coordinator.routeLoading, isFalse);
    },
  );

  final interruptions =
      <String, void Function(SafeWalkLiveNavigationCoordinator)>{
        'close': (c) => c.closeNavigation(),
        'cancel/SOS': (c) => c.cancel(),
        'background': (c) => c.setForeground(false),
        'location revoked': (c) => c.setLocationConsent(false),
        'routing revoked': (c) => c.setRoutingConsent(false),
        'destination changed': (c) => c.destinationChanged(),
        'dispose': (c) => c.dispose(),
      };
  for (final interruption in interruptions.entries) {
    for (final lateError in [false, true]) {
      test('${interruption.key} cancels GPS and ignores late '
          '${lateError ? 'error' : 'success'}', () async {
        final pending = Completer<sw.LocationResult>();
        final s = _session(locate: () => pending.future);
        _allowAndOpen(s.coordinator);
        final work = s.coordinator.planDestination(_destination);
        expect(s.coordinator.locationLoading, isTrue);
        interruption.value(s.coordinator);
        await work;
        expect(s.platform.calls.single.token.isCancelled, isTrue);
        expect(s.coordinator.position, isNull);
        expect(s.coordinator.locationLoading, isFalse);
        expect(s.coordinator.locationError, isNull);
        expect(s.coordinator.routeResult, isNull);
        if (lateError) {
          pending.completeError(StateError('late private GPS failure'));
        } else {
          pending.complete(_fix());
        }
        await Future<void>.delayed(Duration.zero);
        expect(s.routes.requests, isEmpty);
        expect(s.coordinator.position, isNull);
        expect(s.coordinator.locationError, isNull);
      });
    }

    test(
      '${interruption.key} clears in-flight route and late result',
      () async {
        final pending = Completer<sw.RouteResult>();
        final s = _session(route: (_) => pending.future);
        _allowAndOpen(s.coordinator);
        final work = s.coordinator.planDestination(_destination);
        await Future<void>.delayed(Duration.zero);
        expect(s.coordinator.routeLoading, isTrue);
        interruption.value(s.coordinator);
        await work;
        expect(s.routes.tokens.single.isCancelled, isTrue);
        expect(s.coordinator.position, isNull);
        expect(s.coordinator.routeLoading, isFalse);
        expect(s.coordinator.routeResult, isNull);
        pending.complete(_success(s.routes.requests.single));
        await Future<void>.delayed(Duration.zero);
        expect(s.coordinator.routeResult, isNull);
        expect(s.coordinator.routeError, isNull);
      },
    );
  }

  test('resuming or restoring consent never rearms navigation', () async {
    final s = _session();
    _allowAndOpen(s.coordinator);
    await s.coordinator.planDestination(_destination);
    s.coordinator.setForeground(false);
    s.coordinator.setForeground(true);
    expect(s.coordinator.active, isFalse);
    expect(s.coordinator.position, isNull);
    await s.coordinator.planDestination(_destination);
    expect(s.platform.calls, hasLength(1));
    s.coordinator.openNavigation();
    s.coordinator.setRoutingConsent(false);
    s.coordinator.setRoutingConsent(true);
    await s.coordinator.planDestination(_destination);
    expect(s.platform.calls, hasLength(1));
    s.coordinator.openNavigation();
    await s.coordinator.planDestination(_destination);
    expect(s.platform.calls, hasLength(2));
  });

  test('a new explicit destination cannot be overwritten by old GPS', () async {
    final pending = [
      Completer<sw.LocationResult>(),
      Completer<sw.LocationResult>(),
    ];
    var next = 0;
    final s = _session(locate: () => pending[next++].future);
    _allowAndOpen(s.coordinator);
    final oldPlan = s.coordinator.planDestination(_destination);
    s.coordinator.destinationChanged();
    final newDestination = sw.Coordinates(lat: 25.04, lng: 121.53);
    final newPlan = s.coordinator.planDestination(newDestination);
    pending.last.complete(_fix());
    await newPlan;
    pending.first.complete(_fix());
    await oldPlan;
    expect(s.routes.requests, hasLength(1));
    expect(
      s.routes.requests.single.destination.toJson(),
      newDestination.toJson(),
    );
    expect(s.platform.calls.first.token.isCancelled, isTrue);
  });

  test('loading listener may cancel before the native request', () async {
    final s = _session();
    _allowAndOpen(s.coordinator);
    s.coordinator.addListener(() {
      if (s.coordinator.locationLoading) s.coordinator.cancel();
    });
    await s.coordinator.planDestination(_destination);
    expect(s.platform.calls, isEmpty);
    expect(s.routes.requests, isEmpty);
  });

  test(
    'position listener may revoke consent before coordinates leave',
    () async {
      final s = _session();
      _allowAndOpen(s.coordinator);
      s.coordinator.addListener(() {
        if (s.coordinator.position != null) {
          s.coordinator.setRoutingConsent(false);
        }
      });
      await s.coordinator.planDestination(_destination);
      expect(s.platform.calls, hasLength(1));
      expect(s.routes.requests, isEmpty);
      expect(s.coordinator.position, isNull);
    },
  );

  test(
    'a position that expires during notification is not sent to routing',
    () async {
      var now = _now;
      final s = _session(clock: () => now);
      _allowAndOpen(s.coordinator);
      s.coordinator.addListener(() {
        if (s.coordinator.position != null) {
          now = _now.add(const Duration(minutes: 2));
        }
      });
      await s.coordinator.planDestination(_destination);
      expect(s.routes.requests, isEmpty);
      expect(s.coordinator.position, isNull);
      expect(s.coordinator.locationError, contains('過期'));
    },
  );

  test(
    'dispose detaches notifications and does not own the injected controller',
    () async {
      final s = _session();
      _allowAndOpen(s.coordinator);
      var changes = 0;
      s.coordinator.addListener(() => changes++);
      s.coordinator.dispose();
      final before = changes;
      s.controller.setRoutingConsent(false);
      s.controller.cancelRoute();
      await s.coordinator.planDestination(_destination);
      expect(changes, before);
      expect(s.platform.calls, isEmpty);
      s.coordinator.dispose();
    },
  );
}
