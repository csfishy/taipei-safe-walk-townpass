import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/nearby_places.dart';
import 'package:town_pass/features/safe_walk/navigation/osm_convenience_store_source.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final now = DateTime.utc(2026, 11, 8, 3, 0);

// Sample Overpass reply (fixture, not live data; ids are fake).
Map<String, Object?> sampleReply() => {
  'version': 0.6,
  'elements': [
    {
      'type': 'node',
      'id': 1001,
      'lat': 25.0485,
      'lon': 121.5175,
      'tags': {'shop': 'convenience', 'name': 'A店', 'opening_hours': '24/7'},
    },
    {
      'type': 'node',
      'id': 1002,
      'lat': 25.0480,
      'lon': 121.5171,
      'tags': {'shop': 'convenience', 'name': 'B店'},
    },
    {
      'type': 'way',
      'id': 1003,
      'center': {'lat': 25.0490, 'lon': 121.5180},
      'tags': {
        'shop': 'convenience',
        'name': 'C店',
        'opening_hours': 'Mo-Su 07:00-23:00',
      },
    },
    {'type': 'node', 'id': 1004, 'lat': 999, 'lon': 121.5, 'tags': {}},
  ],
};

final class FakeTransport implements JsonTransport {
  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) =>
      throw UnimplementedError();

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) async => sampleReply();
}

final class FakeRouteService implements RouteService {
  sw.RouteRequest? last;

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    last = request;
    return sw.RouteFailure(
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: '2026-11-08T03:00:00Z',
      status: sw.RouteFailureStatus.providerUnavailable,
      reason: 'fake',
      warnings: const ["fake"],
    );
  }
}

sw.Position position() => sw.Position(
  coordinates: sw.Coordinates(lat: 25.0478, lng: 121.5170),
  source: sw.PositionSource.mock,
  accuracyMeters: null,
  observedAt: null,
);

NearbyPlacesService service(FakeRouteService routes) {
  final source = OsmConvenienceStoreSource(
    transport: FakeTransport(),
    hasConsent: () => true,
    endpoints: const ['https://a.test/x'],
    radiiMeters: const [1500],
    only24Hours: false,
    clock: () => now,
  );
  return NearbyPlacesService(
    find: source.findNear,
    routeService: routes,
    clock: () => now,
  );
}

void main() {
  test(
    'parses places with source id, WGS84, retrieval date and license',
    () async {
      final places = await service(FakeRouteService())
          .nearby(position().coordinates);
      expect(places.map((p) => p.sourceRecordId), [
        'osm-node-1002',
        'osm-node-1001',
        'osm-way-1003',
      ]);
      final first = places.first;
      expect(first.name, 'B店');
      expect(first.coordinates.lat, 25.0480);
      expect(first.retrievedAt, now.toIso8601String());
      expect(first.license, contains('ODbL'));
      expect(first.datasetId, 'osm-overpass-convenience-stores');
    },
  );

  test('unknown or unparsed opening hours are never treated as 24h', () async {
    final places = await service(FakeRouteService())
        .nearby(position().coordinates);
    final byId = {for (final p in places) p.sourceRecordId: p};
    expect(byId['osm-node-1001']!.hours, sw.OpeningStatus.open);
    expect(byId['osm-node-1002']!.hours, sw.OpeningStatus.unknown);
    expect(byId['osm-node-1002']!.hoursLabel, '營業時間未知');
    expect(byId['osm-way-1003']!.hours, sw.OpeningStatus.unknown);
  });

  test('maxDistance and limit apply', () async {
    final svc = service(FakeRouteService());
    expect((await svc.nearby(position().coordinates, limit: 1)).length, 1);
    expect(
      (await svc.nearby(position().coordinates, maxDistanceMeters: 50)).length,
      1,
    );
  });

  test(
    'route request is built from the place and sent to RouteService',
    () async {
      final routes = FakeRouteService();
      final svc = service(routes);
      final place = (await svc.nearby(position().coordinates)).first;
      final result = await svc.routeTo(
        place,
        position(),
        requestId: 'req-1',
        mode: sw.DataMode.live,
      );
      expect(result, isA<sw.RouteFailure>());
      final request = routes.last!;
      expect(request.requestId, 'req-1');
      expect(request.mode, sw.DataMode.live);
      expect(request.destination.lat, place.coordinates.lat);
      expect(request.destination.lng, place.coordinates.lng);
      expect(request.departAt, now.toIso8601String());
    },
  );
}
