import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_graph_route_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/valhalla_avoiding_route_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/route_preference.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/platform/integration/avoiding_route_service.dart';

import '../../../../support/safe_walk_fixtures.dart';

import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const _pref = RoutePreference(kind: RoutePreferenceKind.shade, applied: false);

sw.RouteCandidate _route(String id) => sw.RouteCandidate(
  id: id,
  kind: sw.RouteKind.direct,
  geometry: sw.LineString(
    coordinates: const [
      (longitude: 121.5, latitude: 25.0),
      (longitude: 121.51, latitude: 25.0),
    ],
  ),
  distanceMeters: 1000,
  durationSeconds: 700,
  viaPointIds: const [],
  provider: 'valhalla-pedestrian',
  walkingNetworkVerified: true,
  explanations: [id],
  warnings: const ['不保證安全'],
);

sw.RouteRequest _request(
  sw.DataMode mode, {
  sw.PositionSource? source,
  DateTime? at,
  sw.Coordinates? origin,
  sw.Coordinates? destination,
}) => sw.RouteRequest(
  requestId: 'r1',
  mode: mode,
  origin: sw.Position(
    coordinates: origin ?? sw.Coordinates(lat: 25.0, lng: 121.5),
    source:
        source ??
        (mode == sw.DataMode.live
            ? sw.PositionSource.gps
            : sw.PositionSource.mock),
    accuracyMeters: 10,
    observedAt: (at ?? DateTime.now()).toUtc().toIso8601String(),
  ),
  destination: destination ?? sw.Coordinates(lat: 25.0, lng: 121.51),
  departAt: DateTime.now().toUtc().toIso8601String(),
  preference: sw.RouteKind.direct,
  maxExtraDistanceMeters: 500,
  assistancePointIds: const [],
);

void main() {
  test(
    'D3 unavailable online then offline, fresh combined areas, no OSRM',
    () async {
      final online = _DelayedPlanner();
      final offline = _Planner(
        AvoidRoutePlan(
          options: [
            AvoidRouteOption(
              level: AvoidLevel.full,
              route: _route('offline'),
              passedAreaIds: const [],
            ),
          ],
          originInsideAreaIds: const [],
          destinationInsideAreaIds: const [],
          preference: _pref,
        ),
      );
      var loaded = <AvoidArea>[];
      final fallback = _Fallback();
      final service = AvoidingRouteService(
        planner: online,
        offlinePlanner: offline,
        fallback: fallback,
        areas: () => loaded,
        areasLoaded: () => false,
      );
      final future = service.planRoute(_request(sw.DataMode.live));
      loaded = [
        for (final source in ['report', 'crime'])
          AvoidArea(
            id: source,
            center: sw.Coordinates(lat: 25, lng: 121.5),
            radiusMeters: 50,
            source: source,
          ),
      ];
      online.pending.completeError(const WalkingRouteProviderUnavailable());
      final result = await future as sw.RouteSuccess;
      expect(offline.areas.map((a) => a.id), ['report', 'crime']);
      expect(fallback.calls, 0);
      expect(
        result.warnings,
        contains(AvoidingRouteService.partialAreasWarning),
      );
    },
  );

  test('D3 falls through to OSRM only when offline unavailable', () async {
    final online = _Planner(null),
        offline = _Planner(null),
        fallback = _Fallback();
    final result = await AvoidingRouteService(
      planner: online,
      offlinePlanner: offline,
      fallback: fallback,
      areas: () => [],
    ).planRoute(_request(sw.DataMode.live));
    expect(result, isA<sw.RouteSuccess>());
    expect([online.calls, offline.calls, fallback.calls], [1, 1, 1]);
  });

  test('cancellation during offline work never starts OSRM', () async {
    final offline = _DelayedPlanner(),
        fallback = _Fallback(),
        token = ManualCancellation();
    final result = AvoidingRouteService(
      planner: _Planner(null),
      offlinePlanner: offline,
      fallback: fallback,
      areas: () => [],
    ).planRoute(_request(sw.DataMode.live), cancellation: token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    expect(
      (await result as sw.RouteFailure).status,
      sw.RouteFailureStatus.cancelled,
    );
    expect(fallback.calls, 0);
    offline.pending.completeError(const WalkingRouteProviderUnavailable());
  });

  test(
    'real bundled graph works without third-party consent or transport',
    () async {
      var sends = 0;
      final fallback = _Fallback();
      final service = AvoidingRouteService(
        planner: ValhallaAvoidingRoutePlanner(
          hasConsent: () => false,
          post: (uri, body, {cancellation, required hasConsent}) async {
            sends++;
            throw StateError('must not send');
          },
        ),
        offlinePlanner: OfflineGraphRoutePlanner(
          isNavigationActive: () => true,
          loadAsset: () async => (
            bytes: File('assets/safe_walk/route/taipei_walk_graph.bin')
                .readAsBytesSync(),
            meta: jsonDecode(
              File('assets/safe_walk/route/taipei_walk_graph.meta.json')
                  .readAsStringSync(),
            ) as Map<String, dynamic>,
          ),
        ),
        fallback: fallback,
        areas: () => [],
        areasLoaded: () => false,
      );
      final result = await service.planRoute(
        _request(
          sw.DataMode.live,
          origin: sw.Coordinates(lat: 25.0478, lng: 121.517),
          destination: sw.Coordinates(lat: 25.0346, lng: 121.5219),
        ),
      ) as sw.RouteSuccess;
      expect(sends, 0);
      expect(fallback.calls, 0);
      expect(
        result.routes.every((r) => r.provider == 'offline-osm-graph'),
        isTrue,
      );
      expect(result.warnings.join(), contains('離線路網資料：2026-11-11'));
      expect(
        result.warnings,
        contains(AvoidingRouteService.areasUnavailableWarning),
      );
    },
  );

  test('report radius matches between map and planner', () {
    expect(reportAvoidRadiusMeters, AvoidArea.reportRadiusMeters);
  });

  test(
    'live: most-avoiding option first, areas passed through, inside warning',
    () async {
      final planner = _Planner(
        AvoidRoutePlan(
          options: [
            AvoidRouteOption(
              level: AvoidLevel.none,
              route: _route('none'),
              passedAreaIds: const ['a'],
            ),
            AvoidRouteOption(
              level: AvoidLevel.full,
              route: _route('full'),
              passedAreaIds: const [],
            ),
          ],
          originInsideAreaIds: const ['b'],
          destinationInsideAreaIds: const [],
          preference: _pref,
        ),
      );
      final areas = [
        AvoidArea(
          id: 'a',
          center: sw.Coordinates(lat: 25.0, lng: 121.505),
          radiusMeters: 50,
          source: 'report',
        ),
      ];
      final service = AvoidingRouteService(
        planner: planner,
        fallback: _Fallback(),
        areas: () => areas,
      );
      final result = await service.planRoute(
        _request(sw.DataMode.live),
      ) as sw.RouteSuccess;
      expect(result.routes.map((r) => r.id), ['full', 'none']);
      expect(result.warnings.first, AvoidingRouteService.insideWarning);
      expect(planner.areas.single.id, 'a');
    },
  );

  // Taipei 2026-12-21: sunrise 22:34Z (06:34), sunset 09:09Z (17:09).
  final noon = DateTime.utc(2026, 12, 21, 4); // 12:00 local
  final night = DateTime.utc(2026, 12, 21, 14); // 22:00 local

  test(
    'clock decides lit at night and shade by day; disclosure is shown',
    () async {
      for (final (at, kind) in [
        (night, RoutePreferenceKind.lit),
        (noon, RoutePreferenceKind.shade),
      ]) {
        final planner = _Planner(
          AvoidRoutePlan(
            options: [
              AvoidRouteOption(
                level: AvoidLevel.none,
                route: _route('none'),
                passedAreaIds: const [],
              ),
            ],
            originInsideAreaIds: const [],
            destinationInsideAreaIds: const [],
            preference: RoutePreference(
              kind: kind,
              applied: kind == RoutePreferenceKind.lit,
            ),
          ),
        );
        final result = await AvoidingRouteService(
          planner: planner,
          fallback: _Fallback(),
          areas: () => const [],
          clock: () => at,
        ).planRoute(_request(sw.DataMode.live, at: at)) as sw.RouteSuccess;
        expect(planner.preference, kind);
        expect(
          result.warnings,
          contains(
            kind == RoutePreferenceKind.lit
                ? '夜間已優先選擇有路燈的路段（依 OpenStreetMap 路燈標記，標記不完整，不保證照明）'
                : '白天偏好樹蔭路線：尚無可驗證的樹蔭資料，這條路線沒有套用樹蔭偏好',
          ),
        );
      }
    },
  );

  test('OSRM fallback cannot honour the preference and says so', () async {
    for (final (at, text) in [
      (night, '夜間偏好路燈路線：這條路線沒有套用路燈偏好，不保證沿途有照明'),
      (noon, '白天偏好樹蔭路線：尚無可驗證的樹蔭資料，這條路線沒有套用樹蔭偏好'),
    ]) {
      final result = await AvoidingRouteService(
        planner: _Planner(null),
        fallback: _Fallback(),
        areas: () => const [],
        clock: () => at,
      ).planRoute(_request(sw.DataMode.live, at: at)) as sw.RouteSuccess;
      expect(result.warnings.take(2), [
        AvoidingRouteService.fallbackWarning,
        text,
      ]);
    }
  });

  test('planner unreachable: falls back to OSRM with a warning', () async {
    final fallback = _Fallback();
    final service = AvoidingRouteService(
      planner: _Planner(null),
      fallback: fallback,
      areas: () => const [],
    );
    final result =
        await service.planRoute(_request(sw.DataMode.live)) as sw.RouteSuccess;
    expect(fallback.calls, 1);
    expect(result.warnings.first, AvoidingRouteService.fallbackWarning);
  });

  test('no options: no_route failure', () async {
    final service = AvoidingRouteService(
      planner: _Planner(
        const AvoidRoutePlan(
          options: [],
          originInsideAreaIds: [],
          destinationInsideAreaIds: [],
          preference: _pref,
        ),
      ),
      fallback: _Fallback(),
      areas: () => const [],
    );
    final result = await service.planRoute(_request(sw.DataMode.live));
    expect((result as sw.RouteFailure).status, sw.RouteFailureStatus.noRoute);
  });

  test('mock requests never reach the planner', () async {
    final planner = _Planner(null);
    final fallback = _Fallback();
    await AvoidingRouteService(
      planner: planner,
      fallback: fallback,
      areas: () => const [],
    ).planRoute(_request(sw.DataMode.mock));
    expect(planner.calls, 0);
    expect(fallback.calls, 1);
  });

  test('cancelled before planning sends nothing', () async {
    final planner = _Planner(null);
    final fallback = _Fallback();
    final cancellation = ManualCancellation()..cancel();
    final service = AvoidingRouteService(
      planner: planner,
      fallback: fallback,
      areas: () => const [],
    );
    final result = await service.planRoute(
      _request(sw.DataMode.live),
      cancellation: cancellation,
    );
    expect((result as sw.RouteFailure).status, sw.RouteFailureStatus.cancelled);
    expect(planner.calls, 0);
    expect(fallback.calls, 0);
  });

  test('late planner after cancellation never invokes the fallback', () async {
    final planner = _DelayedPlanner();
    final fallback = _Fallback();
    final cancellation = ManualCancellation();
    final service = AvoidingRouteService(
      planner: planner,
      fallback: fallback,
      areas: () => const [],
    );
    final pending = service.planRoute(
      _request(sw.DataMode.live),
      cancellation: cancellation,
    );
    cancellation.cancel();
    expect(
      ((await pending) as sw.RouteFailure).status,
      sw.RouteFailureStatus.cancelled,
    );
    planner.pending.completeError(const WalkingRouteProviderUnavailable());
    await Future<void>.delayed(Duration.zero);
    expect(fallback.calls, 0);
  });

  test('cancellation while fallback is pending returns cancelled', () async {
    final fallback = _DelayedFallback();
    final cancellation = ManualCancellation();
    final service = AvoidingRouteService(
      planner: _Planner(null),
      fallback: fallback,
      areas: () => const [],
    );
    final pending = service.planRoute(
      _request(sw.DataMode.live),
      cancellation: cancellation,
    );
    await fallback.started.future;
    cancellation.cancel();
    expect(
      ((await pending) as sw.RouteFailure).status,
      sw.RouteFailureStatus.cancelled,
    );
    fallback.pending.completeError(const SafeWalkCancelledException());
    await Future<void>.delayed(Duration.zero);
  });

  test('an older planner result cannot replace a newer request', () async {
    final planner = _DelayedPlanner();
    final service = AvoidingRouteService(
      planner: planner,
      fallback: _Fallback(),
      areas: () => const [],
    );
    final first = service.planRoute(_request(sw.DataMode.live));
    final second = service.planRoute(_request(sw.DataMode.live));
    planner.pending.complete(
      AvoidRoutePlan(
        options: [
          AvoidRouteOption(
            level: AvoidLevel.none,
            route: _route('none'),
            passedAreaIds: const [],
          ),
        ],
        originInsideAreaIds: const [],
        destinationInsideAreaIds: const [],
        preference: _pref,
      ),
    );
    expect(
      ((await first) as sw.RouteFailure).status,
      sw.RouteFailureStatus.cancelled,
    );
    expect(await second, isA<sw.RouteSuccess>());
  });

  test('live rejects a mock origin before sending coordinates', () async {
    final planner = _Planner(null);
    final fallback = _Fallback();
    final service = AvoidingRouteService(
      planner: planner,
      fallback: fallback,
      areas: () => const [],
    );
    final result = await service.planRoute(
      _request(sw.DataMode.live, source: sw.PositionSource.mock),
    );
    expect(
      (result as sw.RouteFailure).status,
      sw.RouteFailureStatus.invalidInput,
    );
    expect(planner.calls, 0);
    expect(fallback.calls, 0);
  });
}

final class _DelayedPlanner implements AvoidingRoutePlanner {
  final pending = Completer<AvoidRoutePlan>();

  @override
  Future<AvoidRoutePlan> plan({
    required sw.Coordinates origin,
    required sw.Coordinates destination,
    required List<AvoidArea> areas,
    required RoutePreferenceKind preference,
    SafeWalkCancellation? cancellation,
  }) => pending.future;
}

final class _DelayedFallback implements RouteService {
  final pending = Completer<sw.RouteResult>();
  final started = Completer<void>();

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    started.complete();
    return pending.future;
  }
}

final class _Planner implements AvoidingRoutePlanner {
  _Planner(this.plan_);
  final AvoidRoutePlan? plan_;
  int calls = 0;
  List<AvoidArea> areas = const [];
  RoutePreferenceKind? preference;

  @override
  Future<AvoidRoutePlan> plan({
    required sw.Coordinates origin,
    required sw.Coordinates destination,
    required List<AvoidArea> areas,
    required RoutePreferenceKind preference,
    SafeWalkCancellation? cancellation,
  }) async {
    calls++;
    this.areas = areas;
    this.preference = preference;
    if (plan_ == null) throw const WalkingRouteProviderUnavailable();
    return plan_!;
  }
}

final class _Fallback implements RouteService {
  int calls = 0;
  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    calls++;
    return sw.RouteSuccess(
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      routes: [_route('osrm')],
      warnings: const ['一般路線'],
    );
  }
}
