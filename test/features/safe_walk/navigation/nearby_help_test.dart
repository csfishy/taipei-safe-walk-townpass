import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/nearby_help.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

sw.AssistancePoint store(
  String id, {
  double lat = 25.001,
  String kind = 'public_facility',
  String availability = 'unknown',
}) => sw.AssistancePoint.fromJson(
  (jsonDecode(
      File('test/fixtures/safe_walk/valid/03-AssistancePoint.json')
          .readAsStringSync(),
    ) as Map).cast<String, Object?>()
    ..['id'] = id
    ..['kind'] = kind
    ..['coordinates'] = {'lat': lat, 'lng': 121.501}
    ..['availability'] = availability
    ..['availabilityCheckedAt'] = availability == 'unknown'
        ? null
        : '2026-11-08T00:00:00Z',
);

/// A straight east-west route along latitude 25.05.
sw.RouteCandidate line(double seconds, {double lat = 25.05}) =>
    sw.RouteCandidate(
      id: 'r',
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: [
          (longitude: 121.50, latitude: lat),
          (longitude: 121.51, latitude: lat),
        ],
      ),
      distanceMeters: 1000,
      durationSeconds: seconds,
      viaPointIds: const [],
      provider: 'test',
      walkingNetworkVerified: true,
      explanations: const ['測試'],
      warnings: const ['測試'],
    );

NearbyHelpOption option(String id, List<sw.RouteCandidate> routes) =>
    NearbyHelpOption(
      point: store(id),
      route: sw.RouteSuccess(
        requestId: id,
        mode: sw.DataMode.live,
        generatedAt: '2026-11-08T00:00:00Z',
        routes: routes,
        warnings: const ['測試'],
      ),
    );

void main() {
  // An area right on the 25.05 line; routes at 25.06 stay clear of it.
  final areas = [
    AvoidArea(
      id: 'a',
      center: sw.Coordinates(lat: 25.05, lng: 121.505),
      radiusMeters: 50,
      source: 'report',
    ),
  ];

  test('counts the areas a route comes within', () {
    expect(areasPassed(line(60), areas), 1);
    expect(areasPassed(line(60, lat: 25.06), areas), 0);
  });

  test('safest store first, then fastest', () {
    final ranked = rankNearbyHelp([
      option('fast-but-passes', [line(100)]),
      option('slow-clear', [line(600, lat: 25.06)]),
      option('quick-clear', [line(900), line(300, lat: 25.06)]),
    ], areas);
    expect(ranked.map((o) => o.point.id), [
      'quick-clear',
      'slow-clear',
      'fast-but-passes',
    ]);
  });

  test('picks the nearest open places, drops closed, at most one unknown', () {
    final origin = sw.Coordinates(lat: 25.0, lng: 121.501);
    final picked = pickNearbyCandidates(origin, [
      store(
        'closed',
        lat: 25.0005,
        kind: 'convenience_store',
        availability: 'closed',
      ),
      store('unknown-1', lat: 25.0010, kind: 'police'),
      store('unknown-2', lat: 25.0011, kind: 'convenience_store'),
      store(
        'open-1',
        lat: 25.0020,
        kind: 'convenience_store',
        availability: 'open',
      ),
      store('open-2', lat: 25.0030, kind: 'police', availability: 'open'),
      store(
        'open-3',
        lat: 25.0040,
        kind: 'convenience_store',
        availability: 'open',
      ),
      store('other-kind', lat: 25.0001, availability: 'open'),
    ], count: 3);
    expect(picked.map((p) => p.id), ['unknown-1', 'open-1', 'open-2']);
  });
}
