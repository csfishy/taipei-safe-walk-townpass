import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/route_follower.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final now = DateTime.utc(2026, 11, 7, 3, 30);

// One metre expressed in degrees at about 25 degrees north.
const mLat = 1 / 111195;
const mLng = 1 / 100780;
const baseLat = 25.0;
const baseLng = 121.5;

/// A point [east] metres east and [north] metres north of the route start.
sw.Coordinates at(double east, [double north = 0]) =>
    sw.Coordinates(lat: baseLat + north * mLat, lng: baseLng + east * mLng);

sw.RouteCandidate routeOf(
  List<sw.Coordinates> points, {
  double? duration = 800,
}) => sw.RouteCandidate(
  id: 'r',
  kind: sw.RouteKind.direct,
  geometry: sw.LineString(coordinates: [for (final c in points) toGeoJson(c)]),
  distanceMeters: polylineLengthMeters([for (final c in points) toGeoJson(c)]),
  durationSeconds: duration,
  viaPointIds: const [],
  provider: 'test-walker',
  walkingNetworkVerified: true,
  explanations: const ['測試'],
  warnings: const ['測試'],
);

sw.Position fix(
  sw.Coordinates c, {
  double? accuracy = 5,
  String? observedAt,
  sw.PositionSource source = sw.PositionSource.mock,
}) => sw.Position(
  coordinates: c,
  source: source,
  accuracyMeters: accuracy,
  observedAt: observedAt,
);

/// 1,000 m straight east with a vertex in the middle.
sw.RouteCandidate straight({double? duration = 800}) =>
    routeOf([at(0), at(500), at(1000)], duration: duration);

RouteFollower follower(sw.RouteCandidate route) =>
    RouteFollower(route, clock: () => now);

void main() {
  group('progress along the route', () {
    test('at the start nothing is done yet and the heading is east', () {
      final update = follower(straight()).update(fix(at(0)));

      expect(update.status, FollowStatus.onRoute);
      expect(update.distanceAlongMeters, closeTo(0, 1));
      expect(update.remainingMeters, closeTo(1000, 3));
      expect(update.progress, closeTo(0, 0.01));
      expect(update.bearingDegrees, closeTo(90, 0.5));
      expect(update.distanceFromRouteMeters, closeTo(0, 0.5));
      expect(update.rejectedReason, isNull);
    });

    test('halfway reads about half done', () {
      final update = follower(straight()).update(fix(at(500)));

      expect(update.distanceAlongMeters, closeTo(500, 3));
      expect(update.remainingMeters, closeTo(500, 3));
      expect(update.progress, closeTo(0.5, 0.01));
    });

    test('remaining distance only shrinks while walking forward', () {
      final f = follower(straight());
      var previous = double.infinity;

      for (var east = 0.0; east <= 900; east += 100) {
        final remaining = f.update(fix(at(east))).remainingMeters;
        expect(remaining, lessThan(previous));
        previous = remaining;
      }
    });

    test('a point beside the route snaps onto it', () {
      final update = follower(straight()).update(fix(at(300, 10)));

      expect(update.status, FollowStatus.onRoute);
      expect(update.distanceFromRouteMeters, closeTo(10, 0.5));
      expect(update.snapped.lat, closeTo(baseLat, 1e-7));
      expect(update.snapped.lng, closeTo(at(300).lng, 1e-6));
      expect(update.distanceAlongMeters, closeTo(300, 3));
    });

    test('the camera stays on the real position, not the snapped one', () {
      final here = at(300, 10);

      final update = follower(straight()).update(fix(here));

      expect(update.cameraCenter.lat, here.lat);
      expect(update.cameraCenter.lng, here.lng);
      expect(update.snapped.lat, isNot(here.lat));
    });

    test('before the start and past the end clamp to the ends', () {
      final f = follower(straight());

      expect(f.update(fix(at(-20))).distanceAlongMeters, closeTo(0, 1));
      expect(f.update(fix(at(1030))).distanceAlongMeters, closeTo(1000, 3));
    });
  });

  group('time left', () {
    test('scales the route duration by the distance left', () {
      final update = follower(straight(duration: 800)).update(fix(at(500)));

      expect(update.remainingSeconds, closeTo(400, 4));
    });

    test('is null when the provider gave no duration', () {
      final update = follower(straight(duration: null)).update(fix(at(500)));

      expect(update.remainingSeconds, isNull);
    });
  });

  group('heading', () {
    test('follows the leg the user is on', () {
      // East 500 m, then north 500 m.
      final route = routeOf([at(0), at(500), at(500, 500)]);
      final f = follower(route);

      expect(f.update(fix(at(200))).bearingDegrees, closeTo(90, 1));
      expect(f.update(fix(at(500, 200))).bearingDegrees, closeTo(0, 1));
    });

    test('is in [0, 360) when heading west', () {
      final route = routeOf([at(1000), at(0)]);

      final bearing = follower(route).update(fix(at(500))).bearingDegrees;

      expect(bearing, closeTo(270, 0.5));
      expect(bearing, inInclusiveRange(0, 360));
    });
  });

  group('off route', () {
    test('beyond the limit is offRoute and asks for a new route', () {
      final update = follower(straight()).update(fix(at(300, 100)));

      expect(update.status, FollowStatus.offRoute);
      expect(update.shouldReroute, isTrue);
      expect(update.distanceFromRouteMeters, closeTo(100, 1));
    });

    test('inside the limit is not offRoute', () {
      final update = follower(straight()).update(fix(at(300, 30)));

      expect(update.status, FollowStatus.onRoute);
      expect(update.shouldReroute, isFalse);
    });

    test('a poor but accepted fix gets a wider limit', () {
      // 80 m accuracy: the limit becomes 160 m, so 100 m away is still on route.
      final blurry = follower(straight())
          .update(fix(at(300, 100), accuracy: 80));
      final sharp = follower(straight()).update(fix(at(300, 100), accuracy: 5));

      expect(blurry.status, FollowStatus.onRoute);
      expect(sharp.status, FollowStatus.offRoute);
    });

    test('an off-route fix does not move the progress', () {
      final f = follower(straight());
      f.update(fix(at(300)));

      f.update(fix(at(900, 200)));
      final back = f.update(fix(at(320)));

      expect(back.status, FollowStatus.onRoute);
      expect(back.distanceAlongMeters, closeTo(320, 3));
    });

    test('the thresholds are configurable', () {
      final strict = RouteFollower(
        straight(),
        offRouteMeters: 10,
        clock: () => now,
      );

      expect(strict.update(fix(at(300, 20))).status, FollowStatus.offRoute);
    });
  });

  group('arrival', () {
    test('within the arrival radius of the end is arrived', () {
      final update = follower(straight()).update(fix(at(985)));

      expect(update.status, FollowStatus.arrived);
      expect(update.remainingMeters, lessThan(20));
    });

    test('arrived stays arrived until reset', () {
      final f = follower(straight());
      f.update(fix(at(990)));

      expect(f.update(fix(at(900))).status, FollowStatus.arrived);

      f.reset();
      expect(f.update(fix(at(900))).status, FollowStatus.onRoute);
    });

    test('just outside the radius is not arrived', () {
      expect(
        follower(straight()).update(fix(at(940))).status,
        FollowStatus.onRoute,
      );
    });
  });

  group('rejected fixes', () {
    test('a very inaccurate fix is ignored and repeats the last update', () {
      final f = follower(straight());
      final good = f.update(fix(at(400)));

      final bad = f.update(fix(at(800), accuracy: 500));

      expect(bad.status, FollowStatus.positionRejected);
      expect(bad.rejectedReason, contains('精度'));
      expect(bad.distanceAlongMeters, good.distanceAlongMeters);
      expect(bad.remainingMeters, good.remainingMeters);
    });

    test('a stale GPS fix is ignored', () {
      final update = follower(straight()).update(
        fix(
          at(500),
          source: sw.PositionSource.gps,
          accuracy: 10,
          observedAt: '2026-11-07T11:00:00+08:00',
        ),
      );

      expect(update.status, FollowStatus.positionRejected);
      expect(update.rejectedReason, isNotNull);
    });

    test('a fresh GPS fix is accepted', () {
      final update = follower(straight()).update(
        fix(
          at(500),
          source: sw.PositionSource.gps,
          accuracy: 10,
          observedAt: '2026-11-07T11:29:50+08:00',
        ),
      );

      expect(update.status, FollowStatus.onRoute);
    });

    test('rejecting the very first fix reports the untouched start', () {
      final update = follower(straight()).update(fix(at(500), accuracy: 500));

      expect(update.status, FollowStatus.positionRejected);
      expect(update.distanceAlongMeters, 0);
      expect(update.remainingMeters, closeTo(1000, 3));
      expect(update.progress, 0);
    });

    test('a rejected fix does not change progress for the next good one', () {
      final f = follower(straight());
      f.update(fix(at(400)));
      f.update(fix(at(100), accuracy: 500));

      expect(f.update(fix(at(450))).distanceAlongMeters, closeTo(450, 3));
    });
  });

  group('overlapping routes', () {
    test('an out-and-back keeps moving forward instead of jumping back', () {
      // 500 m east, then straight back to the start along the same line.
      final route = routeOf([at(0), at(500), at(0)]);
      final f = follower(route);
      f.update(fix(at(480)));

      // x = 300 fits both legs equally; the one ahead (return leg) wins.
      final update = f.update(fix(at(300)));

      expect(update.distanceAlongMeters, closeTo(700, 5));
      expect(update.progress, closeTo(0.7, 0.01));
    });

    test('on the first leg the outbound leg is chosen', () {
      final route = routeOf([at(0), at(500), at(0)]);

      final update = follower(route).update(fix(at(300)));

      expect(update.distanceAlongMeters, closeTo(300, 5));
    });
  });

  group('construction', () {
    test('a route needs at least two coordinates', () {
      expect(
        () => RouteFollower(
          sw.RouteCandidate(
            id: 'r',
            kind: sw.RouteKind.direct,
            geometry: sw.LineString(coordinates: [toGeoJson(at(0))]),
            distanceMeters: 0,
            durationSeconds: null,
            viaPointIds: const [],
            provider: 'test',
            walkingNetworkVerified: true,
            explanations: const ['測試'],
            warnings: const ['測試'],
          ),
        ),
        throwsA(isA<Object>()),
      );
    });

    test('a zero-length route is refused', () {
      expect(() => RouteFollower(routeOf([at(0), at(0)])), throwsArgumentError);
    });
  });

  group('stream', () {
    test(
      'turns M1 positions into updates in order without reading GPS',
      () async {
        final f = follower(straight());
        final controller = StreamController<sw.Position>();

        final updates = f.follow(controller.stream).toList();
        controller
          ..add(fix(at(100)))
          ..add(fix(at(500)))
          ..add(fix(at(995)));
        await controller.close();
        final result = await updates;

        expect(result.map((u) => u.status), [
          FollowStatus.onRoute,
          FollowStatus.onRoute,
          FollowStatus.arrived,
        ]);
        expect(
          result.map((u) => u.remainingMeters),
          orderedEquals(
            result.map((u) => u.remainingMeters).toList()
              ..sort((a, b) => b.compareTo(a)),
          ),
        );
      },
    );
  });
}
