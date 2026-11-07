import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_point.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

Map<String, Object?> fixture(String relativePath) => (jsonDecode(
  File('test/fixtures/safe_walk/$relativePath').readAsStringSync(),
) as Map).cast<String, Object?>();

final now = DateTime.utc(2026, 11, 7, 3, 30);
final origin = sw.Coordinates(lat: 25.0478, lng: 121.5170);

sw.AssistancePoint point(
  String id, {
  double lat = 25.0485,
  double lng = 121.5175,
  String kind = 'convenience_store',
  String availability = 'open',
  String? checkedAt = '2026-11-07T11:20:00+08:00',
}) => sw.AssistancePoint.fromJson(
  fixture('valid/03-AssistancePoint.json')
    ..['id'] = id
    ..['kind'] = kind
    ..['coordinates'] = {'lat': lat, 'lng': lng}
    ..['availability'] = availability
    ..['availabilityCheckedAt'] = checkedAt,
);

List<String> ids(List<NearestPoint> found) => [
  for (final item in found) item.point.id,
];

List<NearestPoint> find(
  List<sw.AssistancePoint> points, {
  bool requireOpenNow = true,
  Set<sw.AssistancePointKind>? kinds,
  double? maxDistanceMeters,
  int? limit,
  Duration maxAge = defaultMaxAvailabilityAge,
}) => nearestPoints(
  origin: origin,
  points: points,
  kinds: kinds ?? const {sw.AssistancePointKind.convenienceStore},
  requireOpenNow: requireOpenNow,
  maxAvailabilityAge: maxAge,
  maxDistanceMeters: maxDistanceMeters,
  limit: limit,
  now: now,
);

void main() {
  group('nearestPoints', () {
    test('sorts by straight-line distance from the origin', () {
      final found = find([
        point('far', lat: 25.08, lng: 121.56),
        point('near', lat: 25.0485, lng: 121.5175),
        point('mid', lat: 25.04, lng: 121.5),
      ]);

      expect(ids(found), ['near', 'mid', 'far']);
      expect(
        found.first.distanceMeters,
        closeTo(distanceMeters(origin, found.first.point.coordinates), 1e-6),
      );
    });

    test('ties are broken by id so the order is stable', () {
      final found = find([point('b'), point('a'), point('c')]);

      expect(ids(found), ['a', 'b', 'c']);
    });

    test('covers every convenience chain, not just one brand', () {
      // The contract has no brand field: any convenience_store qualifies.
      final found = find([
        point('seven-eleven'),
        point('family-mart', lat: 25.049),
        point('hi-life', lat: 25.05),
      ]);

      expect(found, hasLength(3));
    });

    test('ignores other kinds unless asked for', () {
      final points = [
        point('shop'),
        point('station', kind: 'police'),
        point('toilet', kind: 'public_facility'),
      ];

      expect(ids(find(points)), ['shop']);
      expect(
        ids(
          find(
            points,
            kinds: {
              sw.AssistancePointKind.convenienceStore,
              sw.AssistancePointKind.police,
            },
          ),
        ),
        containsAll(['shop', 'station']),
      );
    });
  });

  group('open now', () {
    test('unknown and closed are never treated as open', () {
      final found = find([
        point('unknown', availability: 'unknown', checkedAt: null),
        point(
          'closed',
          availability: 'closed',
          checkedAt: '2026-11-07T11:20:00+08:00',
        ),
        point('open'),
      ]);

      expect(ids(found), ['open']);
    });

    test('an open check that is too old is dropped', () {
      final found = find([
        point('stale', checkedAt: '2026-11-07T08:00:00+08:00'),
        point('fresh', checkedAt: '2026-11-07T11:00:00+08:00'),
      ]);

      expect(ids(found), ['fresh']);
    });

    test('the allowed age is configurable', () {
      final points = [point('p', checkedAt: '2026-11-07T10:00:00+08:00')];

      expect(find(points), isEmpty);
      expect(find(points, maxAge: const Duration(hours: 2)), hasLength(1));
    });

    test('a check time in the future is dropped', () {
      expect(
        find([point('future', checkedAt: '2026-11-07T13:00:00+08:00')]),
        isEmpty,
      );
    });

    test('requireOpenNow false lists unknown points too', () {
      final found = find([
        point('unknown', availability: 'unknown', checkedAt: null),
        point('closed', availability: 'closed'),
      ], requireOpenNow: false);

      expect(ids(found), containsAll(['unknown', 'closed']));
    });
  });

  group('limits', () {
    final points = [
      point('a', lat: 25.048),
      point('b', lat: 25.05),
      point('c', lat: 25.06),
    ];

    test('limit keeps the closest', () {
      expect(ids(find(points, limit: 2)), ['a', 'b']);
      expect(find(points, limit: 0), isEmpty);
      expect(find(points, limit: 10), hasLength(3));
    });

    test('maxDistanceMeters drops farther points', () {
      expect(ids(find(points, maxDistanceMeters: 100)), ['a']);
    });

    test('nothing known is an empty list, not a made-up store', () {
      expect(find(const []), isEmpty);
      expect(find([point('far', lat: 26.0)], maxDistanceMeters: 100), isEmpty);
    });

    test('the returned list cannot be modified', () {
      expect(
        () => find(points).add(find(points).first),
        throwsUnsupportedError,
      );
    });
  });

  group('data quality', () {
    test('a point failing the shared semantic checks is skipped', () {
      // open without a check time is rejected by pointProblems().
      final broken = point('no-time', checkedAt: null);

      expect(find([broken, point('ok')], requireOpenNow: false), hasLength(1));
    });

    test('demo points keep their mock source so the UI can label them', () {
      final found = find([point('demo')]);

      expect(found.single.point.source.dataMode, sw.DataMode.mock);
    });
  });
}
