import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/nearby_help.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

sw.AssistancePoint store(String id) => sw.AssistancePoint.fromJson(
  (jsonDecode(
    File('test/fixtures/safe_walk/valid/03-AssistancePoint.json')
        .readAsStringSync(),
  ) as Map).cast<String, Object?>()..['id'] = id,
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
}
