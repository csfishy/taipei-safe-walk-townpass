import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_store_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

Map<String, Object?> fixture(String relativePath) => (jsonDecode(
  File('test/fixtures/safe_walk/$relativePath').readAsStringSync(),
) as Map).cast<String, Object?>();

final now = DateTime.utc(2026, 11, 7, 3, 30);

sw.Position origin() => sw.Position(
  coordinates: sw.Coordinates(lat: 25.0478, lng: 121.5170),
  source: sw.PositionSource.mock,
  accuracyMeters: null,
  observedAt: null,
);

sw.AssistancePoint store(
  String id,
  double lat,
  double lng, {
  String availability = 'open',
  String? checkedAt = '2026-11-07T11:20:00+08:00',
  String kind = 'convenience_store',
}) => sw.AssistancePoint.fromJson(
  fixture('valid/03-AssistancePoint.json')
    ..['id'] = id
    ..['name'] = 'store $id'
    ..['kind'] = kind
    ..['coordinates'] = {'lat': lat, 'lng': lng}
    ..['availability'] = availability
    ..['availabilityCheckedAt'] = checkedAt,
);

sw.RouteCandidate candidate(double meters) => sw.RouteCandidate(
  id: 'r',
  kind: sw.RouteKind.direct,
  geometry: sw.LineString(
    coordinates: [
      (longitude: 121.5170, latitude: 25.0478),
      (longitude: 121.5175, latitude: 25.0485),
    ],
  ),
  distanceMeters: meters,
  durationSeconds: meters / 1.25,
  viaPointIds: const [],
  provider: 'test-walker',
  walkingNetworkVerified: true,
  explanations: const ['測試'],
  warnings: const ['路線警示'],
);

/// Answers each planRoute() from [walkMeters], keyed by destination latitude.
final class FakeRouteService implements RouteService {
  FakeRouteService(this.walkMeters);

  final Map<double, double?> walkMeters;
  final requests = <sw.RouteRequest>[];
  int running = 0;
  int maxRunning = 0;

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    requests.add(request);
    running++;
    if (running > maxRunning) maxRunning = running;
    await Future<void>.delayed(Duration.zero);
    running--;
    final meters = walkMeters[request.destination.lat];
    if (meters == null) {
      return sw.RouteFailure(
        requestId: request.requestId,
        mode: request.mode,
        generatedAt: now.toIso8601String(),
        status: sw.RouteFailureStatus.noRoute,
        reason: '找不到可步行的路線',
        warnings: const ['沒有產生路線'],
      );
    }
    return sw.RouteSuccess(
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: now.toIso8601String(),
      routes: [candidate(meters)],
      warnings: const ['警示'],
    );
  }
}

NearestStorePlanner planner(
  List<sw.AssistancePoint> points, {
  RouteService? routes,
  int candidates = 3,
}) => NearestStorePlanner(
  find: (o, {cancellation}) async => points,
  routeService: routes,
  candidates: candidates,
  clock: () => now,
);

Future<NearestStoreResult> run(
  NearestStorePlanner p, {
  SafeWalkCancellation? cancellation,
}) => p.plan(
  origin(),
  requestId: 'req',
  mode: sw.DataMode.live,
  cancellation: cancellation,
);

void main() {
  // Straight-line order from the origin: near < mid < far.
  final near = store('near', 25.0485, 121.5175);
  final mid = store('mid', 25.0400, 121.5100);
  final far = store('far', 25.0600, 121.5300);

  group('without a route service', () {
    test(
      'picks the straight-line nearest open store and a Google link',
      () async {
        final result = await run(planner([far, near, mid]));

        expect(result.status, NearestStoreStatus.found);
        expect(result.store!.point.id, 'near');
        expect(result.store!.walkingRoute, isNull);
        expect(
          result.store!.straightLineMeters,
          closeTo(distanceMeters(origin().coordinates, near.coordinates), 1e-6),
        );
        expect(result.googleMapsUri!.host, 'www.google.com');
        expect(
          result.googleMapsUri!.queryParameters['destination'],
          '25.048500,121.517500',
        );
        expect(result.googleMapsUri!.queryParameters['travelmode'], 'walking');
      },
    );

    test('the link never contains the user location', () async {
      final result = await run(planner([near]));

      final text = result.googleMapsUri.toString();
      expect(text, isNot(contains('25.0478')));
      expect(text, isNot(contains('121.517000')));
      expect(
        result.googleMapsUri!.queryParameters.containsKey('origin'),
        isFalse,
      );
    });

    test('closed, unknown and non-store points are never chosen', () async {
      final result = await run(
        planner([
          store('closed', 25.0480, 121.5171, availability: 'closed'),
          store(
            'unknown',
            25.0480,
            121.5172,
            availability: 'unknown',
            checkedAt: null,
          ),
          store('police', 25.0480, 121.5173, kind: 'police'),
          far,
        ]),
      );

      expect(result.store!.point.id, 'far');
    });

    test('shows the data limits next to the answer', () async {
      final result = await run(planner([near]));

      expect(result.warnings, isNotEmpty);
      expect(result.warnings, containsAll(near.source.limitations));
    });
  });

  group('nothing to offer', () {
    test('no open store is noKnownStore with no link', () async {
      final result = await run(
        planner([store('c', 25.05, 121.52, availability: 'closed')]),
      );

      expect(result.status, NearestStoreStatus.noKnownStore);
      expect(result.store, isNull);
      expect(result.googleMapsUri, isNull);
      expect(result.reason, contains('不代表附近沒有'));
    });

    test('an empty list is noKnownStore', () async {
      expect(
        (await run(planner(const []))).status,
        NearestStoreStatus.noKnownStore,
      );
    });

    test('missing consent is reported and nothing else happens', () async {
      final routes = FakeRouteService({});
      final p = NearestStorePlanner(
        find: (o, {cancellation}) => throw const ConsentRequiredException(),
        routeService: routes,
        clock: () => now,
      );

      final result = await run(p);

      expect(result.status, NearestStoreStatus.consentRequired);
      expect(result.googleMapsUri, isNull);
      expect(routes.requests, isEmpty);
    });

    test('a failed lookup is lookupFailed without leaking details', () async {
      final p = NearestStorePlanner(
        find: (o, {cancellation}) => Future.error(
          const JsonTransportException(TransportFailure.timeout),
        ),
        clock: () => now,
      );

      final result = await run(p);

      expect(result.status, NearestStoreStatus.lookupFailed);
      expect(result.reason, isNot(contains('timeout')));
    });
  });

  group('with a route service', () {
    test(
      'picks the shortest real walk, not just the straight-line nearest',
      () async {
        final routes = FakeRouteService({
          near.coordinates.lat: 900, // close as the crow flies, long way round
          mid.coordinates.lat: 400,
          far.coordinates.lat: 700,
        });

        final result = await run(planner([near, mid, far], routes: routes));

        expect(result.store!.point.id, 'mid');
        expect(result.store!.walkingRoute!.distanceMeters, 400);
        expect(
          result.googleMapsUri!.queryParameters['destination'],
          '25.040000,121.510000',
        );
        expect(result.warnings, contains('路線警示'));
      },
    );

    test('routes one store at a time', () async {
      final routes = FakeRouteService({
        near.coordinates.lat: 100,
        mid.coordinates.lat: 200,
        far.coordinates.lat: 300,
      });

      await run(planner([near, mid, far], routes: routes));

      expect(routes.requests, hasLength(3));
      expect(routes.maxRunning, 1);
    });

    test('request ids are unique and requests are direct live walks', () async {
      final routes = FakeRouteService({
        near.coordinates.lat: 100,
        mid.coordinates.lat: 200,
      });

      await run(planner([near, mid], routes: routes));

      expect(routes.requests.map((r) => r.requestId), ['req-1', 'req-2']);
      for (final request in routes.requests) {
        expect(request.mode, sw.DataMode.live);
        expect(request.preference, sw.RouteKind.direct);
        expect(request.assistancePointIds, isEmpty);
        expect(request.origin.coordinates.lat, 25.0478);
      }
    });

    test('only the closest candidates are routed', () async {
      final routes = FakeRouteService({
        near.coordinates.lat: 100,
        mid.coordinates.lat: 200,
        far.coordinates.lat: 300,
      });

      await run(planner([near, mid, far], routes: routes, candidates: 2));

      expect(routes.requests, hasLength(2));
    });

    test(
      'a store that cannot be routed is skipped, the others still count',
      () async {
        final routes = FakeRouteService({
          near.coordinates.lat: null,
          mid.coordinates.lat: 400,
        });

        final result = await run(planner([near, mid], routes: routes));

        expect(result.store!.point.id, 'mid');
      },
    );

    test(
      'when nothing can be routed it falls back to straight-line and says so',
      () async {
        final routes = FakeRouteService({
          near.coordinates.lat: null,
          mid.coordinates.lat: null,
        });

        final result = await run(planner([mid, near], routes: routes));

        expect(result.status, NearestStoreStatus.found);
        expect(result.store!.point.id, 'near');
        expect(result.store!.walkingRoute, isNull);
        expect(result.googleMapsUri, isNotNull);
        expect(result.warnings.join(), contains('直線距離'));
      },
    );

    test('a route service that throws does not break the answer', () async {
      final result = await run(
        planner([near], routes: _ThrowingRouteService()),
      );

      expect(result.status, NearestStoreStatus.found);
      expect(result.googleMapsUri, isNotNull);
    });
  });

  group('cancellation', () {
    test('cancelled before starting does nothing', () async {
      var asked = false;
      final p = NearestStorePlanner(
        find: (o, {cancellation}) async {
          asked = true;
          return [near];
        },
        clock: () => now,
      );
      final cancellation = ManualCancellation()..cancel();

      final result = await run(p, cancellation: cancellation);

      expect(result.status, NearestStoreStatus.cancelled);
      expect(asked, isFalse);
    });

    test('cancelling during the lookup returns cancelled at once', () async {
      final p = NearestStorePlanner(
        find: (o, {cancellation}) =>
            Completer<List<sw.AssistancePoint>>().future,
        clock: () => now,
      );
      final cancellation = ManualCancellation();

      final pending = run(p, cancellation: cancellation);
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();

      expect((await pending).status, NearestStoreStatus.cancelled);
    });

    test('cancelling between routes stops further routing', () async {
      final cancellation = ManualCancellation();
      final routes = _CancellingRouteService(cancellation);

      final result = await run(
        planner([near, mid, far], routes: routes),
        cancellation: cancellation,
      );

      expect(result.status, NearestStoreStatus.cancelled);
      expect(routes.calls, 1);
    });
  });
}

final class _ThrowingRouteService implements RouteService {
  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) => throw StateError('boom 25.0478,121.5170');
}

final class _CancellingRouteService implements RouteService {
  _CancellingRouteService(this.cancellation);

  final ManualCancellation cancellation;
  int calls = 0;

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    calls++;
    this.cancellation.cancel();
    return sw.RouteFailure(
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: now.toIso8601String(),
      status: sw.RouteFailureStatus.cancelled,
      reason: '使用者已取消',
      warnings: const ['沒有產生路線'],
    );
  }
}
