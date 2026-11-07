import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/io_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_point.dart';
import 'package:town_pass/features/safe_walk/navigation/osm_convenience_store_source.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_store_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/route_follower.dart';
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

      // Walk the real geometry point by point: progress must only advance and
      // the walk must end as arrived.
      final follower = RouteFollower(route);
      var previous = double.infinity;
      FollowUpdate? last;
      for (final c in route.geometry.coordinates) {
        last = follower.update(
          sw.Position(
            coordinates: sw.Coordinates(lat: c.latitude, lng: c.longitude),
            source: sw.PositionSource.mock,
            accuracyMeters: 5,
            observedAt: null,
          ),
        );
        expect(last.status, isNot(FollowStatus.offRoute));
        expect(last.remainingMeters, lessThanOrEqualTo(previous + 1));
        previous = last.remainingMeters;
      }
      expect(last!.status, FollowStatus.arrived);
      expect(last.remainingMeters, lessThan(30));
      // ignore: avoid_print
      print(
        'Follower: walked ${route.geometry.coordinates.length} points, arrived',
      );
    },
    skip: live ? false : 'set SAFE_WALK_LIVE=1 to call the real services',
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'planner picks the shortest real walk to a store ',
    () async {
      // Two stand-in stores (not real shops) so only the routing is live.
      sw.AssistancePoint standIn(String id, double lat, double lng) =>
          sw.AssistancePoint(
            id: id,
            name: '測試用店 $id',
            kind: sw.AssistancePointKind.convenienceStore,
            coordinates: sw.Coordinates(lat: lat, lng: lng),
            address: null,
            publicPhone: null,
            recognition: sw.UnconfirmedRecognition(
              status: sw.UnconfirmedRecognitionStatus.unconfirmed,
              checkedAt: null,
            ),
            availability: sw.OpeningStatus.open,
            availabilityCheckedAt: DateTime.now().toUtc().toIso8601String(),
            capabilities: const [sw.AssistanceCapability.unknown],
            source: sw.SourceMetadata(
              datasetId: 'live-smoke',
              title: '測試用資料',
              dataMode: sw.DataMode.live,
              sourceUrl: 'https://example.org/',
              retrievedAt: DateTime.now().toUtc().toIso8601String(),
              dataUpdatedAt: null,
              license: null,
              coverage: '只供冒煙測試',
              limitations: const ['測試用資料，不是真實店家'],
            ),
          );
      final stores = [
        standIn('a', 25.0495, 121.5190),
        standIn('b', 25.0440, 121.5200),
      ];
      final planner = NearestStorePlanner(
        find: (o, {cancellation}) async => stores,
        routeService: DefaultRouteService(
          liveProvider: OsrmWalkingRouteProvider(
            transport: IoJsonTransport(),
            hasConsent: () => true,
          ),
        ),
      );

      final result = await planner.plan(
        sw.Position(
          coordinates: taipeiMain,
          source: sw.PositionSource.gps,
          accuracyMeters: 10,
          observedAt: DateTime.now().toUtc().toIso8601String(),
        ),
        requestId: 'live-smoke-planner',
        mode: sw.DataMode.live,
      );

      expect(
        result.status,
        NearestStoreStatus.found,
        reason: '${result.reason}',
      );
      expect(result.store!.walkingRoute, isNotNull);
      // ignore: avoid_print
      print(
        'Planner: ${result.store!.point.name}, walk '
        '${result.store!.walkingRoute!.distanceMeters.round()} m',
      );
      expect(result.store!.walkingRoute, isNotNull);
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
