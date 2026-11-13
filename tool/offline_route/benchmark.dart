import 'dart:convert';
import 'dart:io';

import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_walk_graph.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_graph_route_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_route_worker.dart';
import 'package:town_pass/features/safe_walk/navigation/route_preference.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

sw.Coordinates coordinate(List<dynamic> p) => sw.Coordinates(
  lat: (p[0] as num).toDouble(),
  lng: (p[1] as num).toDouble(),
);
Future<void> main() async {
  final watch = Stopwatch()..start();
  final asset = (
    bytes: File('assets/safe_walk/route/taipei_walk_graph.bin')
        .readAsBytesSync(),
    meta: jsonDecode(
      File('assets/safe_walk/route/taipei_walk_graph.meta.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>,
  );
  final graph = OfflineWalkGraph.parse(asset.bytes, asset.meta);
  final load = watch.elapsedMicroseconds / 1000;
  final pairs =
      jsonDecode(
            File('test/fixtures/offline_route/taipei_pairs.json')
                .readAsStringSync(),
          )['pairs']
          as List;
  final referenceFile = File(
    'test/fixtures/offline_route/valhalla_reference.json',
  );
  final references = referenceFile.existsSync()
      ? jsonDecode(referenceFile.readAsStringSync())['pairs'] as List
      : [];
  final results = <Map<String, dynamic>>[];
  for (final pair in [
    ...pairs,
    {
      'id': 'three-km-main-daan',
      'origin': [25.0478, 121.5170],
      'destination': [25.0325, 121.5340],
    },
  ]) {
    final origin = coordinate(pair['origin']),
        destination = coordinate(pair['destination']);
    final area = AvoidArea(
      id: 'public-test-buffer',
      center: sw.Coordinates(
        lat: (origin.lat + destination.lat) / 2,
        lng: (origin.lng + destination.lng) / 2,
      ),
      radiusMeters: 50,
      source: 'synthetic-validation',
    );
    watch.reset();
    final result = planOnOfflineGraph(graph, origin, destination, [
      area,
    ], RoutePreferenceKind.shade);
    final elapsed = watch.elapsedMicroseconds / 1000;
    final shortest = result.plan.options.first.route;
    final reference = references
        .where((r) => r['id'] == pair['id'] && r['status'] == 'ok')
        .firstOrNull;
    final refMeters = reference?['distanceMeters'] as num?;
    final full = result.plan[AvoidLevel.full];
    final minFull = full == null
        ? null
        : [
            for (var i = 1; i < full.route.geometry.coordinates.length; i++)
              projectToSegment(
                area.center,
                fromGeoJson(full.route.geometry.coordinates[i - 1]),
                fromGeoJson(full.route.geometry.coordinates[i]),
              ).distance,
          ].reduce((a, b) => a < b ? a : b);
    results.add({
      'id': pair['id'],
      'milliseconds': elapsed,
      'distanceMeters': shortest.distanceMeters,
      'valhallaMeters': refMeters,
      'differencePercent': refMeters == null
          ? null
          : (shortest.distanceMeters / refMeters - 1) * 100,
      'levels': [for (final o in result.plan.options) o.level.name],
      'fullMinimumBufferDistanceMeters': minFull,
      'fullPassedAreaIds': full?.passedAreaIds,
    });
  }
  watch.reset();
  await runOfflineWorker(
    () => computeOfflineRoute(
      asset,
      sw.Coordinates(lat: 25.0478, lng: 121.517),
      sw.Coordinates(lat: 25.0325, lng: 121.534),
      [],
      RoutePreferenceKind.shade,
    ),
    null,
  );
  final isolateMs = watch.elapsedMicroseconds / 1000;
  final report = {
    'coldIsolateParseAndRoute3kmMs': isolateMs,
    'platform': '${Platform.operatingSystem} ${Platform.version}',
    'measurement': 'desktop CLI; not a phone acceptance',
    'assetBytes': asset.bytes.length,
    'loadReadValidateMs': load,
    'results': results,
  };
  File('test/fixtures/offline_route/desktop_results.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report));
}
