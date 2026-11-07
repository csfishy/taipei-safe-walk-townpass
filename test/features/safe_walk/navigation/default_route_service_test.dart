import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/mock_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

Map<String, Object?> fixture(String relativePath) => (jsonDecode(
  File('test/fixtures/safe_walk/$relativePath').readAsStringSync(),
) as Map).cast<String, Object?>();

final now = DateTime.utc(2026, 11, 7, 3, 30);

sw.RouteRequest request({
  String mode = 'mock',
  String preference = 'via_assistance',
  List<String> ids = const ['demo-point-1'],
  Map<String, Object?>? origin,
  Map<String, Object?>? destination,
  String requestId = 'demo-request-1',
}) {
  final json = fixture('valid/05-RouteRequest.json')
    ..['mode'] = mode
    ..['preference'] = preference
    ..['assistancePointIds'] = ids
    ..['requestId'] = requestId;
  if (origin != null) json['origin'] = origin;
  if (destination != null) json['destination'] = destination;
  return sw.RouteRequest.fromJson(json);
}

Map<String, Object?> gpsOrigin({
  String observedAt = '2026-11-07T11:29:50+08:00',
}) => {
  'schemaVersion': '1.0.0',
  'coordinates': {'lat': 25.0, 'lng': 121.5},
  'source': 'gps',
  'accuracyMeters': 12.0,
  'observedAt': observedAt,
};

sw.AssistancePoint demoPoint() =>
    sw.AssistancePoint.fromJson(fixture('valid/03-AssistancePoint.json'));

Future<List<sw.AssistancePoint>> lookupDemoPoint(
  List<String> ids, {
  SafeWalkCancellation? cancellation,
}) async => [demoPoint()];

sw.RouteCandidate candidate({
  List<(double lng, double lat)> line = const [
    (121.5, 25.0),
    (121.501, 25.001),
  ],
  bool verified = true,
  String provider = 'fake-walking',
  sw.RouteKind kind = sw.RouteKind.direct,
  List<String> via = const [],
}) => sw.RouteCandidate(
  id: 'fake-route-1',
  kind: kind,
  geometry: sw.LineString(
    coordinates: [for (final p in line) (longitude: p.$1, latitude: p.$2)],
  ),
  distanceMeters: 150,
  durationSeconds: 120,
  viaPointIds: via,
  provider: provider,
  walkingNetworkVerified: verified,
  explanations: const ['測試路線'],
  warnings: const ['測試路線'],
);

final class FakeProvider implements WalkingRouteProvider {
  FakeProvider(this.onFind);

  final Future<List<sw.RouteCandidate>> Function(
    sw.RouteRequest request,
    SafeWalkCancellation? cancellation,
  )
  onFind;
  int calls = 0;

  @override
  Future<List<sw.RouteCandidate>> findRoutes(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) {
    calls++;
    return onFind(request, cancellation);
  }
}

final class TestCancellation implements SafeWalkCancellation {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

DefaultRouteService service({
  WalkingRouteProvider? live,
  WalkingRouteProvider mock = const MockWalkingRouteProvider(),
  AssistancePointLookup? lookup = lookupDemoPoint,
}) => DefaultRouteService(
  mockProvider: mock,
  liveProvider: live,
  pointLookup: lookup,
  clock: () => now,
);

void expectFailure(
  sw.RouteResult result,
  sw.RouteFailureStatus status, {
  String requestId = 'demo-request-1',
  sw.DataMode mode = sw.DataMode.mock,
}) {
  expect(result, isA<sw.RouteFailure>());
  final failure = result as sw.RouteFailure;
  expect(failure.status, status);
  expect(failure.routes, isEmpty);
  expect(failure.requestId, requestId);
  expect(failure.mode, mode);
  // Every result must also be a valid RouteResult on the wire.
  expect(() => sw.RouteResult.fromJson(failure.toJson()), returnsNormally);
}

void main() {
  group('mock mode', () {
    test(
      'fixed request returns a labelled demo route that passes the contract',
      () async {
        final result = await service().planRoute(request());

        expect(result, isA<sw.RouteSuccess>());
        final success = result as sw.RouteSuccess;
        expect(success.requestId, 'demo-request-1');
        expect(success.mode, sw.DataMode.mock);
        expect(success.routes, hasLength(1));
        final route = success.routes.single;
        expect(route.kind, sw.RouteKind.viaAssistance);
        expect(route.viaPointIds, ['demo-point-1']);
        expect(route.provider, MockWalkingRouteProvider.providerId);
        expect(route.walkingNetworkVerified, isFalse);
        expect(route.durationSeconds, isNull);
        expect(route.warnings.join(), contains('禁止實地導航'));
        expect(success.warnings.join(), contains('示範模式'));
        expect(routeProblems(success, points: [demoPoint()]), isEmpty);
        expect(
          () => sw.RouteResult.fromJson(success.toJson()),
          returnsNormally,
        );
      },
    );

    test(
      'geometry is [longitude, latitude] from origin to destination',
      () async {
        final success = await service().planRoute(request()) as sw.RouteSuccess;

        final line = success.routes.single.geometry.coordinates;
        expect(line.first, (longitude: 121.5, latitude: 25.0));
        expect(line.last, (longitude: 121.501, latitude: 25.001));
        expect(
          success.routes.single.distanceMeters,
          closeTo(polylineLengthMeters(line), 1e-6),
        );
      },
    );

    test(
      'direct preference returns a direct route without via points',
      () async {
        final success = await service().planRoute(
          request(preference: 'direct', ids: const []),
        ) as sw.RouteSuccess;

        expect(success.routes.single.kind, sw.RouteKind.direct);
        expect(success.routes.single.viaPointIds, isEmpty);
      },
    );

    test(
      'via preference without ids says so and falls back to direct',
      () async {
        final success = await service().planRoute(
          request(ids: const []),
        ) as sw.RouteSuccess;

        expect(success.routes.single.kind, sw.RouteKind.direct);
        expect(success.routes.single.explanations.join(), contains('未指定途經據點'));
      },
    );

    test('keeps the caller requestId', () async {
      final result = await service().planRoute(request(requestId: 'abc-42'));

      expect(result.requestId, 'abc-42');
    });
  });

  group('live mode without a provider', () {
    test(
      'is provider_unavailable and never a mock or straight-line route',
      () async {
        final result = await service().planRoute(
          request(
            mode: 'live',
            origin: gpsOrigin(),
            preference: 'direct',
            ids: const [],
          ),
        );

        expectFailure(
          result,
          sw.RouteFailureStatus.providerUnavailable,
          mode: sw.DataMode.live,
        );
        expect((result as sw.RouteFailure).warnings.join(), contains('不以直線'));
      },
    );

    test('matches the shared provider_unavailable fixture', () async {
      final expected = sw.RouteFailure.fromJson(
        fixture('valid/07-RouteResult.json'),
      );
      final result = await service().planRoute(
        request(
          mode: 'live',
          origin: gpsOrigin(),
          preference: 'direct',
          ids: const [],
        ),
      ) as sw.RouteFailure;

      expect(result.status, expected.status);
      expect(result.reason, expected.reason);
      expect(result.warnings, expected.warnings);
    });

    test('does not use the mock provider for a live request', () async {
      final mock = FakeProvider((_, _) async => [candidate()]);
      final result = await service(mock: mock).planRoute(
        request(
          mode: 'live',
          origin: gpsOrigin(),
          preference: 'direct',
          ids: const [],
        ),
      );

      expectFailure(
        result,
        sw.RouteFailureStatus.providerUnavailable,
        mode: sw.DataMode.live,
      );
      expect(mock.calls, 0);
    });
  });

  group('live mode with an injected provider', () {
    sw.RouteRequest liveRequest() => request(
      mode: 'live',
      origin: gpsOrigin(),
      preference: 'direct',
      ids: const [],
    );

    test('returns a verified walking route', () async {
      final provider = FakeProvider((_, _) async => [candidate()]);

      final result = await service(live: provider).planRoute(liveRequest());

      expect(result, isA<sw.RouteSuccess>());
      expect(result.mode, sw.DataMode.live);
      expect(provider.calls, 1);
      expect((result as sw.RouteSuccess).warnings.join(), contains('不保證路段安全'));
    });

    test('rejects an unverified walking network', () async {
      final provider = FakeProvider(
        (_, _) async => [candidate(verified: false)],
      );

      expectFailure(
        await service(live: provider).planRoute(liveRequest()),
        sw.RouteFailureStatus.providerUnavailable,
        mode: sw.DataMode.live,
      );
    });

    test('rejects a live route from a provider named mock', () async {
      final provider = FakeProvider(
        (_, _) async => [candidate(provider: 'mock-walker')],
      );

      expectFailure(
        await service(live: provider).planRoute(liveRequest()),
        sw.RouteFailureStatus.providerUnavailable,
        mode: sw.DataMode.live,
      );
    });

    test('rejects a route whose ends are far from the request', () async {
      final provider = FakeProvider(
        (_, _) async => [
          candidate(line: const [(121.55, 25.04), (121.56, 25.05)]),
        ],
      );

      expectFailure(
        await service(live: provider).planRoute(liveRequest()),
        sw.RouteFailureStatus.providerUnavailable,
        mode: sw.DataMode.live,
      );
    });

    test('accepts ends snapped within the allowed distance', () async {
      final provider = FakeProvider(
        (_, _) async => [
          candidate(line: const [(121.5015, 25.0), (121.501, 25.0015)]),
        ],
      );

      expect(
        await service(live: provider).planRoute(liveRequest()),
        isA<sw.RouteSuccess>(),
      );
    });

    test('empty candidates are no_route', () async {
      final provider = FakeProvider((_, _) async => const []);

      expectFailure(
        await service(live: provider).planRoute(liveRequest()),
        sw.RouteFailureStatus.noRoute,
        mode: sw.DataMode.live,
      );
    });

    test('WalkingRouteNotFound is no_route', () async {
      final provider = FakeProvider(
        (_, _) async => throw const WalkingRouteNotFound(),
      );

      expectFailure(
        await service(live: provider).planRoute(liveRequest()),
        sw.RouteFailureStatus.noRoute,
        mode: sw.DataMode.live,
      );
    });

    test(
      'provider errors become provider_unavailable without leaking details',
      () async {
        final provider = FakeProvider(
          (_, _) async => throw StateError('failed at 25.0,121.5 token=SECRET'),
        );

        final result = await service(live: provider).planRoute(liveRequest());

        expectFailure(
          result,
          sw.RouteFailureStatus.providerUnavailable,
          mode: sw.DataMode.live,
        );
        expect(
          jsonEncode((result as sw.RouteFailure).toJson()),
          isNot(contains('SECRET')),
        );
        expect(result.reason, isNot(contains('121.5')));
      },
    );

    test('a via route needs known, live points', () async {
      final provider = FakeProvider(
        (_, _) async => [
          candidate(
            kind: sw.RouteKind.viaAssistance,
            via: const ['demo-point-1'],
          ),
        ],
      );

      // The demo point is mock data, so a live route may not reference it.
      expectFailure(
        await service(live: provider)
            .planRoute(request(mode: 'live', origin: gpsOrigin())),
        sw.RouteFailureStatus.providerUnavailable,
        mode: sw.DataMode.live,
      );
    });
  });

  group('input checks', () {
    test('stale GPS is invalid_input and the provider is not called', () async {
      final provider = FakeProvider((_, _) async => [candidate()]);

      final result = await service(live: provider).planRoute(
        request(
          mode: 'live',
          origin: gpsOrigin(observedAt: '2026-11-07T11:00:00+08:00'),
          preference: 'direct',
          ids: const [],
        ),
      );

      expectFailure(
        result,
        sw.RouteFailureStatus.invalidInput,
        mode: sw.DataMode.live,
      );
      expect(provider.calls, 0);
    });

    test('a live request cannot start from a demo position', () async {
      final provider = FakeProvider((_, _) async => [candidate()]);

      final result = await service(
        live: provider,
      ).planRoute(request(mode: 'live', preference: 'direct', ids: const []));

      expectFailure(
        result,
        sw.RouteFailureStatus.invalidInput,
        mode: sw.DataMode.live,
      );
      expect(provider.calls, 0);
    });

    test('same origin and destination is invalid_input', () async {
      final result = await service().planRoute(
        request(destination: {'lat': 25.0, 'lng': 121.5}),
      );

      expectFailure(result, sw.RouteFailureStatus.invalidInput);
    });

    test(
      'an unknown via point is invalid_input and the provider is not called',
      () async {
        final mock = FakeProvider((_, _) async => [candidate()]);

        final result = await service(
          mock: mock,
          lookup: (ids, {cancellation}) async => const [],
        ).planRoute(request());

        expectFailure(result, sw.RouteFailureStatus.invalidInput);
        expect((result as sw.RouteFailure).reason, contains('demo-point-1'));
        expect(mock.calls, 0);
      },
    );

    test('via points cannot be checked without a lookup', () async {
      final result = await service(lookup: null).planRoute(request());

      expectFailure(result, sw.RouteFailureStatus.invalidInput);
    });
  });

  group('cancellation', () {
    test('an already cancelled token returns cancelled without calling the provider', () async {
      final mock = FakeProvider((_, _) async => [candidate()]);
      final cancellation = TestCancellation()..cancel();

      final result = await service(mock: mock)
          .planRoute(request(), cancellation: cancellation);

      expectFailure(result, sw.RouteFailureStatus.cancelled);
      expect(mock.calls, 0);
    });

    test(
      'cancelling during the provider call returns cancelled at once',
      () async {
        final gate = Completer<List<sw.RouteCandidate>>();
        final mock = FakeProvider((_, _) => gate.future);
        final cancellation = TestCancellation();

        final pending = service(mock: mock)
            .planRoute(request(), cancellation: cancellation);
        await Future<void>.delayed(Duration.zero);
        cancellation.cancel();

        expectFailure(await pending, sw.RouteFailureStatus.cancelled);
        // A late answer from the provider must not resurrect the route.
        gate.complete([candidate()]);
        await Future<void>.delayed(Duration.zero);
      },
    );

    test('cancelling during the point lookup returns cancelled', () async {
      final gate = Completer<List<sw.AssistancePoint>>();
      final cancellation = TestCancellation();

      final pending = service(lookup: (ids, {cancellation}) => gate.future)
          .planRoute(request(), cancellation: cancellation);
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();

      expectFailure(await pending, sw.RouteFailureStatus.cancelled);
    });

    test('a provider error after cancellation is swallowed', () async {
      final gate = Completer<List<sw.RouteCandidate>>();
      final mock = FakeProvider((_, _) => gate.future);
      final cancellation = TestCancellation();

      final pending = service(mock: mock)
          .planRoute(request(), cancellation: cancellation);
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      await pending;
      gate.completeError(StateError('late failure'));
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'an older request finishing late does not overwrite the newer result',
      () async {
        final slow = Completer<List<sw.RouteCandidate>>();
        var call = 0;
        final mock = FakeProvider((_, _) {
          call++;
          return call == 1 ? slow.future : Future.value([candidate()]);
        });
        final svc = service(mock: mock);

        final first = svc.planRoute(request(requestId: 'old'));
        await Future<void>.delayed(Duration.zero);
        final second = await svc.planRoute(request(requestId: 'new'));
        slow.complete([candidate()]);
        final firstResult = await first;

        expect(second, isA<sw.RouteSuccess>());
        expect(second.requestId, 'new');
        expectFailure(
          firstResult,
          sw.RouteFailureStatus.cancelled,
          requestId: 'old',
        );
      },
    );
  });

  group('boundaries', () {
    test(
      'the service never needs a position stream, only the request origin',
      () async {
        FakeProvider? seen;
        seen = FakeProvider((req, _) async {
          expect(req.origin.coordinates.lat, 25.0);
          return [candidate()];
        });

        await service(mock: seen)
            .planRoute(request(preference: 'direct', ids: const []));

        expect(seen.calls, 1);
      },
    );

    test(
      'mock requests can be answered offline, with no injected provider',
      () async {
        final result = await DefaultRouteService(
          clock: () => now,
          pointLookup: lookupDemoPoint,
        ).planRoute(request());

        expect(result, isA<sw.RouteSuccess>());
      },
    );
  });
}
