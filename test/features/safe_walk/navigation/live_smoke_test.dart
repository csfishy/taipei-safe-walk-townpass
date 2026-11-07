import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/io_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_point.dart';
import 'package:town_pass/features/safe_walk/navigation/osm_convenience_store_source.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Calls the real public services. Skipped unless SAFE_WALK_LIVE=1, so normal
/// runs and CI stay offline:
///
///   SAFE_WALK_LIVE=1 flutter test test/features/safe_walk/navigation/live_smoke_test.dart
///
/// The public servers are fair-use and may be slow or down; a failure here is
/// not necessarily a bug in this code.
final live = Platform.environment['SAFE_WALK_LIVE'] == '1';

void main() {
  final taipeiMain = sw.Coordinates(lat: 25.0478, lng: 121.5170);
  final taipei101 = sw.Coordinates(lat: 25.0339, lng: 121.5645);

  test(
    'OSRM returns a real walking route through DefaultRouteService',
    () async {
      final service = DefaultRouteService(
        liveProvider: OsrmWalkingRouteProvider(
          transport: IoJsonTransport(),
          hasConsent: () => true,
        ),
      );
      final request = sw.RouteRequest(
        requestId: 'live-smoke-1',
        mode: sw.DataMode.live,
        origin: sw.Position(
          coordinates: taipei101,
          source: sw.PositionSource.gps,
          accuracyMeters: 10,
          observedAt: DateTime.now().toUtc().toIso8601String(),
        ),
        destination: taipeiMain,
        departAt: DateTime.now().toUtc().toIso8601String(),
        preference: sw.RouteKind.direct,
        maxExtraDistanceMeters: 0,
        assistancePointIds: const [],
      );

      final result = await service.planRoute(request);

      expect(result, isA<sw.RouteSuccess>(), reason: '$result');
      final route = (result as sw.RouteSuccess).routes.single;
      // ignore: avoid_print
      print(
        'OSRM: ${route.distanceMeters.round()} m, '
        '${route.durationSeconds?.round()} s, '
        '${route.geometry.coordinates.length} points',
      );
      expect(route.walkingNetworkVerified, isTrue);
      expect(route.distanceMeters, inInclusiveRange(4500, 9000));
      expect(route.durationSeconds, isNotNull);
    },
    skip: live ? false : 'set SAFE_WALK_LIVE=1 to call the real services',
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'Overpass lookup returns stores or a transport error, never made-up data',
    () async {
      final source = OsmConvenienceStoreSource(
        transport: IoJsonTransport(),
        hasConsent: () => true,
      );

      try {
        final points = await source.findNear(taipeiMain);
        final nearest = nearestPoints(origin: taipeiMain, points: points);
        // ignore: avoid_print
        print(
          'Overpass: ${points.length} 24/7 stores, nearest: '
          '${nearest.isEmpty ? 'none' : '${nearest.first.point.name} '
                    '${nearest.first.distanceMeters.round()} m'}',
        );
        for (final point in points) {
          expect(point.source.dataMode, sw.DataMode.live);
          expect(point.availability, sw.OpeningStatus.open);
        }
      } on JsonTransportException catch (error) {
        // ignore: avoid_print
        print('Overpass unavailable right now: ${error.failure.name}');
      }
    },
    skip: live ? false : 'set SAFE_WALK_LIVE=1 to call the real services',
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
