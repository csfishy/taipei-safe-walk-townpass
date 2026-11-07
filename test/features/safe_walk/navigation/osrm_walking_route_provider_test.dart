import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
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
  String preference = 'direct',
  List<String> ids = const [],
  int maxExtra = 300,
  Map<String, Object?>? origin,
}) {
  final json = fixture('valid/05-RouteRequest.json')
    ..['mode'] = mode
    ..['preference'] = preference
    ..['assistancePointIds'] = ids
    ..['maxExtraDistanceMeters'] = maxExtra;
  if (origin != null) json['origin'] = origin;
  return sw.RouteRequest.fromJson(json);
}

Map<String, Object?> gpsOrigin() => {
  'schemaVersion': '1.0.0',
  'coordinates': {'lat': 25.0, 'lng': 121.5},
  'source': 'gps',
  'accuracyMeters': 12.0,
  'observedAt': '2026-11-07T11:29:50+08:00',
};

sw.AssistancePoint viaPoint({String id = 'demo-point-1'}) =>
    sw.AssistancePoint.fromJson(
      fixture('valid/03-AssistancePoint.json')
        ..['id'] = id
        ..['coordinates'] = {'lat': 25.0005, 'lng': 121.5005},
    );

Future<List<sw.AssistancePoint>> lookup(
  List<String> ids, {
  SafeWalkCancellation? cancellation,
}) async => [viaPoint()];

/// The shape of a real routing.openstreetmap.de answer, with a short geometry.
Map<String, Object?> osrmOk({
  double distance = 300,
  double duration = 240,
  List<List<double>> coordinates = const [
    [121.5, 25.0],
    [121.5005, 25.0004],
    [121.501, 25.001],
  ],
}) => {
  'code': 'Ok',
  'routes': [
    {
      'legs': [
        {
          'steps': <Object?>[],
          'weight': 1.0,
          'summary': '',
          'duration': duration,
          'distance': distance,
        },
      ],
      'weight_name': 'routability',
      'geometry': {'coordinates': coordinates, 'type': 'LineString'},
      'weight': 1.0,
      'duration': duration,
      'distance': distance,
    },
  ],
  'waypoints': <Object?>[],
};

final class FakeTransport implements JsonTransport {
  FakeTransport(this.onGet);

  final Future<Object?> Function(Uri url, SafeWalkCancellation? cancellation)
  onGet;
  final urls = <Uri>[];

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) {
    urls.add(url);
    return onGet(url, cancellation);
  }

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) => throw UnimplementedError();
}

OsrmWalkingRouteProvider provider(
  FakeTransport transport, {
  bool consent = true,
  AssistancePointLookup? pointLookup = lookup,
}) => OsrmWalkingRouteProvider(
  transport: transport,
  hasConsent: () => consent,
  pointLookup: pointLookup,
);

void main() {
  group('consent', () {
    test('without consent nothing is requested', () async {
      final transport = FakeTransport((_, _) async => osrmOk());

      await expectLater(
        provider(transport, consent: false).findRoutes(request()),
        throwsA(isA<ConsentRequiredException>()),
      );
      expect(transport.urls, isEmpty);
    });

    test('consent is read again on every request', () async {
      var allowed = true;
      final transport = FakeTransport((_, _) async => osrmOk());
      final p = OsrmWalkingRouteProvider(
        transport: transport,
        hasConsent: () => allowed,
      );

      await p.findRoutes(request());
      allowed = false;

      await expectLater(
        p.findRoutes(request()),
        throwsA(isA<ConsentRequiredException>()),
      );
      expect(transport.urls, hasLength(1));
    });

    test(
      'the service reports it as provider_unavailable asking for consent',
      () async {
        final transport = FakeTransport((_, _) async => osrmOk());
        final service = DefaultRouteService(
          liveProvider: provider(transport, consent: false),
          clock: () => now,
        );

        final result = await service.planRoute(
          request(mode: 'live', origin: gpsOrigin()),
        ) as sw.RouteFailure;

        expect(result.status, sw.RouteFailureStatus.providerUnavailable);
        expect(result.reason, contains('同意'));
        expect(transport.urls, isEmpty);
      },
    );
  });

  group('request', () {
    test(
      'sends longitude,latitude pairs in order and asks for GeoJSON',
      () async {
        final transport = FakeTransport((_, _) async => osrmOk());

        await provider(transport).findRoutes(request());

        final url = transport.urls.single;
        expect(url.scheme, 'https');
        expect(
          url.path,
          endsWith('/121.500000,25.000000;121.501000,25.001000'),
        );
        expect(
          url.toString(),
          startsWith(OsrmWalkingRouteProvider.defaultEndpoint),
        );
        expect(url.queryParameters, {
          'overview': 'full',
          'geometries': 'geojson',
          'alternatives': 'false',
          'steps': 'false',
        });
      },
    );
  });

  group('direct route', () {
    test('turns the answer into a verified walking candidate', () async {
      final transport = FakeTransport(
        (_, _) async => osrmOk(distance: 312.5, duration: 250.2),
      );

      final routes = await provider(transport).findRoutes(request());

      expect(routes, hasLength(1));
      final route = routes.single;
      expect(route.kind, sw.RouteKind.direct);
      expect(route.provider, OsrmWalkingRouteProvider.providerId);
      expect(route.walkingNetworkVerified, isTrue);
      expect(route.distanceMeters, 312.5);
      expect(route.durationSeconds, 250.2);
      expect(route.viaPointIds, isEmpty);
      expect(route.geometry.coordinates.first, (
        longitude: 121.5,
        latitude: 25.0,
      ));
      expect(route.geometry.coordinates, hasLength(3));
      expect(route.warnings.join(), contains('不保證路段安全'));
      expect(route.warnings.join(), contains('OpenStreetMap'));
    });

    test(
      'the provider name is not mock, so a live result passes the contract',
      () async {
        final transport = FakeTransport((_, _) async => osrmOk());
        final service = DefaultRouteService(
          liveProvider: provider(transport),
          clock: () => now,
        );

        final result = await service.planRoute(
          request(mode: 'live', origin: gpsOrigin()),
        );

        expect(result, isA<sw.RouteSuccess>());
        expect(result.mode, sw.DataMode.live);
        expect(routeProblems(result), isEmpty);
      },
    );
  });

  group('bad answers', () {
    Future<Object?> run(Object? body) {
      final transport = FakeTransport((_, _) async => body);
      return provider(transport).findRoutes(request());
    }

    test('NoRoute and NoSegment are WalkingRouteNotFound', () async {
      await expectLater(
        run({'code': 'NoRoute'}),
        throwsA(isA<WalkingRouteNotFound>()),
      );
      await expectLater(
        run({'code': 'NoSegment'}),
        throwsA(isA<WalkingRouteNotFound>()),
      );
    });

    test('a single-point geometry is not a route', () async {
      await expectLater(
        run(
          osrmOk(
            coordinates: const [
              [121.5, 25.0],
            ],
          ),
        ),
        throwsA(isA<WalkingRouteNotFound>()),
      );
    });

    test('other codes and malformed bodies are provider_unavailable', () async {
      final bad = <Object?>[
        {'code': 'InvalidQuery'},
        {'code': 'Ok'},
        {'code': 'Ok', 'routes': <Object?>[]},
        'not a map',
        null,
        [1, 2],
        {
          'code': 'Ok',
          'routes': [
            {'distance': 'far', 'duration': 1, 'geometry': {}},
          ],
        },
        {
          'code': 'Ok',
          'routes': [
            {
              'distance': -5,
              'duration': 1,
              'geometry': {
                'coordinates': [
                  [121.5, 25.0],
                  [121.6, 25.1],
                ],
              },
            },
          ],
        },
      ];
      for (final body in bad) {
        await expectLater(
          run(body),
          throwsA(isA<WalkingRouteProviderUnavailable>()),
          reason: '$body',
        );
      }
    });

    test('an out of range coordinate is rejected', () async {
      await expectLater(
        run(
          osrmOk(
            coordinates: const [
              [121.5, 25.0],
              [25.0, 121.5],
            ],
          ),
        ),
        throwsA(isA<WalkingRouteProviderUnavailable>()),
      );
    });

    test('transport failures pass through unchanged', () async {
      final transport = FakeTransport(
        (_, _) => Future.error(
          const JsonTransportException(TransportFailure.timeout),
        ),
      );

      await expectLater(
        provider(transport).findRoutes(request()),
        throwsA(isA<JsonTransportException>()),
      );
    });
  });

  group('via assistance point', () {
    sw.RouteRequest viaRequest({int maxExtra = 300}) => request(
      preference: 'via_assistance',
      ids: const ['demo-point-1'],
      maxExtra: maxExtra,
    );

    // Three waypoints means the via leg; two means the direct leg.
    Future<Object?> answer(Uri url, {double viaDistance = 400}) async =>
        url.path.split(';').length == 3
        ? osrmOk(distance: viaDistance)
        : osrmOk(distance: 300);

    test(
      'returns the via route and the direct route when the detour is allowed',
      () async {
        final transport = FakeTransport((url, _) => answer(url));

        final routes = await provider(transport).findRoutes(viaRequest());

        expect(routes, hasLength(2));
        expect(routes.first.kind, sw.RouteKind.viaAssistance);
        expect(routes.first.viaPointIds, ['demo-point-1']);
        expect(routes.first.explanations.join(), contains('多繞約 100 公尺'));
        expect(routes.last.kind, sw.RouteKind.direct);
        expect(
          transport.urls.any(
            (u) =>
                u.path.contains('121.500000,25.000000;121.500500,25.000500;'),
          ),
          isTrue,
          reason: 'the via point sits between origin and destination',
        );
      },
    );

    test('a detour over the limit falls back to direct and says why', () async {
      final transport = FakeTransport((url, _) => answer(url));

      final routes = await provider(transport)
          .findRoutes(viaRequest(maxExtra: 50));

      expect(routes, hasLength(1));
      expect(routes.single.kind, sw.RouteKind.direct);
      expect(routes.single.viaPointIds, isEmpty);
      expect(routes.single.explanations.join(), contains('超過上限'));
    });

    test('no walkable route through the point falls back to direct', () async {
      final transport = FakeTransport(
        (url, _) async =>
            url.path.split(';').length == 3 ? {'code': 'NoRoute'} : osrmOk(),
      );

      final routes = await provider(transport).findRoutes(viaRequest());

      expect(routes.single.kind, sw.RouteKind.direct);
      expect(routes.single.explanations.join(), contains('沒有可步行'));
    });

    test('needs a lookup to know where the point is', () async {
      final transport = FakeTransport((url, _) => answer(url));

      await expectLater(
        provider(transport, pointLookup: null).findRoutes(viaRequest()),
        throwsA(isA<WalkingRouteProviderUnavailable>()),
      );
    });

    test('an id the lookup does not return is unavailable', () async {
      final transport = FakeTransport((url, _) => answer(url));

      await expectLater(
        provider(
          transport,
          pointLookup: (ids, {cancellation}) async => const [],
        ).findRoutes(viaRequest()),
        throwsA(isA<WalkingRouteProviderUnavailable>()),
      );
    });

    test('direct preference ignores point ids and makes one request', () async {
      final transport = FakeTransport((url, _) => answer(url));

      final routes = await provider(
        transport,
      ).findRoutes(request(preference: 'direct', ids: const ['demo-point-1']));

      expect(routes, hasLength(1));
      expect(transport.urls, hasLength(1));
    });
  });

  group('cancellation', () {
    test('cancelled before starting makes no request', () async {
      final transport = FakeTransport((_, _) async => osrmOk());
      final cancellation = ManualCancellation()..cancel();

      await expectLater(
        provider(transport).findRoutes(request(), cancellation: cancellation),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(transport.urls, isEmpty);
    });

    test(
      'the token is handed to the transport so it can close the socket',
      () async {
        SafeWalkCancellation? seen;
        final transport = FakeTransport((_, cancellation) async {
          seen = cancellation;
          return osrmOk();
        });
        final cancellation = ManualCancellation();

        await provider(transport)
            .findRoutes(request(), cancellation: cancellation);

        expect(seen, same(cancellation));
      },
    );
  });
}
