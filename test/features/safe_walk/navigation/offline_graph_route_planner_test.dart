import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_graph_route_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_walk_graph.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_route_worker.dart';
import 'package:town_pass/features/safe_walk/navigation/route_preference.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/features/safe_walk/shared/route_instructions.dart';

sw.Coordinates at(double lat, double lng) => sw.Coordinates(lat: lat, lng: lng);
final origin = at(25, 121.5), destination = at(25, 121.502);
final area = AvoidArea(
  id: 'unit-circle',
  center: at(25, 121.501),
  radiusMeters: 50,
  source: 'unit-fixture',
);

/// Artificial graph ONLY for algorithm tests; never selected by the app.
OfflineGraphAsset unitAsset({bool oneway = false, bool disconnected = false}) {
  final nodes = [
    origin,
    at(25, 121.501),
    destination,
    at(25.0003, 121.5),
    at(25.0003, 121.502),
    at(25.001, 121.5),
    at(25.001, 121.502),
  ];
  final edges = <(int, int)>[];
  for (final path
      in disconnected
          ? [
              [0, 1],
              [3, 4],
              [5, 6],
            ]
          : [
              [0, 1, 2],
              [0, 3, 4, 2],
              [0, 5, 6, 2],
            ]) {
    for (var i = 1; i < path.length; i++) {
      edges.add((path[i - 1], path[i]));
      if (!oneway) edges.add((path[i], path[i - 1]));
    }
  }
  edges.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  final strings = utf8.encode(jsonEncode(['測試步道']));
  final bytes = Uint8List(
    24 +
        nodes.length * 8 +
        (nodes.length + 1) * 4 +
        edges.length * 16 +
        strings.length,
  );
  bytes.setAll(0, ascii.encode('SWWALK01'));
  final view = ByteData.sublistView(bytes);
  void u32(int p, int n) => view.setUint32(p, n, Endian.little);
  u32(8, nodes.length);
  u32(12, edges.length);
  u32(16, 1);
  u32(20, strings.length);
  for (var i = 0; i < nodes.length; i++) {
    view.setInt32(24 + i * 8, (nodes[i].lat * 1e7).round(), Endian.little);
    view.setInt32(28 + i * 8, (nodes[i].lng * 1e7).round(), Endian.little);
    u32(24 + nodes.length * 8 + i * 4, edges.where((e) => e.$1 < i).length);
  }
  u32(24 + nodes.length * 8 + nodes.length * 4, edges.length);
  final edgeStart = 24 + nodes.length * 8 + (nodes.length + 1) * 4;
  for (var i = 0; i < edges.length; i++) {
    u32(edgeStart + i * 16, edges[i].$2);
    u32(
      edgeStart + i * 16 + 4,
      (distanceMeters(nodes[edges[i].$1], nodes[edges[i].$2]) * 1000).ceil(),
    );
  }
  bytes.setAll(bytes.length - strings.length, strings);
  return (
    bytes: bytes,
    meta: {
      'format': 'SWWALK01',
      'nodes': nodes.length,
      'edges': edges.length,
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'sourceDate': '2026-01-01',
      'bbox': [24.9, 121.4, 25.2, 121.7],
      'license': 'ODbL-1.0',
    },
  );
}

void main() {
  test('cancelling running CPU work kills its isolate', () async {
    final token = ManualCancellation();
    final future = runOfflineWorker<int>(() {
      var x = 0;
      while (true) {
        x++;
        if (x < 0) return x;
      }
    }, token);
    Timer(const Duration(milliseconds: 20), token.cancel);
    await expectLater(future, throwsA(isA<SafeWalkCancelledException>()));
  });
  test('CSR validation, exact segment snap, corruption and bounds', () {
    final asset = unitAsset(),
        graph = OfflineWalkGraph.parse(unitAsset().bytes, unitAsset().meta);
    final snap = graph.nearestSegment(at(25.00001, 121.5005));
    expect(snap.point.lng, closeTo(121.5005, 1e-8));
    expect(snap.point.lat, 25);
    expect(snap.fraction, closeTo(0.5, 1e-5));
    final bad = Uint8List.fromList(asset.bytes)..[30] ^= 1;
    expect(
      () => OfflineWalkGraph.parse(bad, asset.meta),
      throwsFormatException,
    );
    final structure = Uint8List.fromList(asset.bytes);
    ByteData.sublistView(structure).setUint32(24 + 7 * 8, 9999, Endian.little);
    expect(
      () => OfflineWalkGraph.parse(structure, {
        ...asset.meta,
        'sha256': sha256.convert(structure).toString(),
      }),
      throwsFormatException,
    );
    expect(
      () => OfflineWalkGraph.parse(Uint8List(4), asset.meta),
      throwsFormatException,
    );
  });

  test('A* shortest, centre and full paths use exact circle geometry', () {
    final result = computeOfflineRoute(unitAsset(), origin, destination, [
      area,
    ], RoutePreferenceKind.shade);
    final plan = result.plan;
    expect(plan.options.map((o) => o.level), AvoidLevel.values);
    expect(plan[AvoidLevel.none]!.passedAreaIds, ['unit-circle']);
    expect(plan[AvoidLevel.center]!.passedAreaIds, ['unit-circle']);
    expect(plan[AvoidLevel.full]!.passedAreaIds, isEmpty);
    expect(
      plan[AvoidLevel.none]!.route.distanceMeters,
      closeTo(distanceMeters(origin, destination), 0.05),
    );
    expect(
      plan[AvoidLevel.center]!.route.distanceMeters,
      lessThan(plan[AvoidLevel.full]!.route.distanceMeters),
    );
    for (final option in plan.options) {
      expect(option.route.provider, 'offline-osm-graph');
      expect(option.route.walkingNetworkVerified, isTrue);
      expect(option.route.durationSeconds, isNull);
      expect(option.route.warnings.join(), contains('2026-01-01'));
      expect(result.instructions[plan.options.indexOf(option)], isNotEmpty);
    }
  });

  test(
    'inside endpoint exempts its circle and warns; duplicates keep strongest',
    () {
      final inside = AvoidArea(
        id: 'inside',
        center: origin,
        radiusMeters: 50,
        source: 'unit',
      );
      final plan = computeOfflineRoute(unitAsset(), origin, destination, [
        inside,
      ], RoutePreferenceKind.lit).plan;
      expect(plan.originInsideAreaIds, ['inside']);
      expect(plan.options.single.level, AvoidLevel.full);
      expect(plan.options.single.route.warnings.join(), contains('無法完整避開'));
      expect(plan.preference.applied, isFalse);
    },
  );

  test('same-segment partial paths honour foot direction', () {
    final asset = unitAsset(oneway: true);
    final a = at(25, 121.5002), b = at(25, 121.5008);
    final forward = computeOfflineRoute(
      asset,
      a,
      b,
      [],
      RoutePreferenceKind.shade,
    ).plan;
    expect(
      forward.options.single.route.distanceMeters,
      closeTo(distanceMeters(a, b), 0.01),
    );
    final back = computeOfflineRoute(
      asset,
      b,
      a,
      [],
      RoutePreferenceKind.shade,
    ).plan;
    expect(back.options, isEmpty);
  });

  test('disconnected graph, endpoint snap limit, invalid areas', () {
    expect(
      computeOfflineRoute(
        unitAsset(disconnected: true),
        origin,
        at(25.001, 121.502),
        [],
        RoutePreferenceKind.shade,
      ).plan.options,
      isEmpty,
    );
    expect(
      () => computeOfflineRoute(
        unitAsset(),
        at(26, 121.5),
        destination,
        [],
        RoutePreferenceKind.shade,
      ),
      throwsA(isA<WalkingRouteProviderUnavailable>()),
    );
    expect(
      () => computeOfflineRoute(unitAsset(), origin, destination, [
        AvoidArea(id: 'bad', center: origin, radiusMeters: -1, source: 'unit'),
      ], RoutePreferenceKind.shade),
      throwsA(isA<WalkingRouteProviderUnavailable>()),
    );
  });

  test('turn thresholds, names, straight merging and unnamed streets', () {
    for (final (degrees, turn) in [
      (19.9, TurnKind.straight),
      (20.0, TurnKind.slightRight),
      (-20.0, TurnKind.slightLeft),
      (45.0, TurnKind.right),
      (-45.0, TurnKind.left),
      (120.0, TurnKind.sharpRight),
      (-120.0, TurnKind.sharpLeft),
      (165.0, TurnKind.uTurn),
    ]) {
      expect(offlineTurnKind(degrees), turn);
    }
    final steps = offlineInstructions(
      [origin, at(25, 121.501), destination, at(25.001, 121.502)],
      ['同名路', '同名路', null],
    );
    expect(steps.length, 2);
    expect(steps.first.shapeIndex, 0);
    expect(steps.last.turn, TurnKind.left);
    expect(steps.last.street, isNull);
    expect(
      offlineInstructions(
        [origin, at(25, 121.501), destination],
        ['A', 'B'],
      ).length,
      2,
    );
  });

  test('native isolate returns instructions, navigation gate, loading cancellation', () async {
    var active = true;
    final planner = OfflineGraphRoutePlanner(
      loadAsset: () async => unitAsset(),
      isNavigationActive: () => active,
    );
    final plan = await planner.plan(
      origin: origin,
      destination: destination,
      areas: [area],
      preference: RoutePreferenceKind.shade,
    );
    expect(routeInstructions[plan.options.first.route], isNotEmpty);
    active = false;
    await expectLater(
      planner.plan(
        origin: origin,
        destination: destination,
        areas: [],
        preference: RoutePreferenceKind.shade,
      ),
      throwsA(isA<WalkingRouteProviderUnavailable>()),
    );
    final token = ManualCancellation();
    final pending = OfflineGraphRoutePlanner(
      loadAsset: () => Completer<OfflineGraphAsset>().future,
      isNavigationActive: () => true,
    );
    final future = pending.plan(
      origin: origin,
      destination: destination,
      areas: [],
      preference: RoutePreferenceKind.shade,
      cancellation: token,
    );
    token.cancel();
    await expectLater(future, throwsA(isA<SafeWalkCancelledException>()));
  });

  test(
    'ten public landmark comparisons: real asset and full buffer exclusion',
    () {
      final asset = (
        bytes: File('assets/safe_walk/route/taipei_walk_graph.bin')
            .readAsBytesSync(),
        meta: jsonDecode(
          File('assets/safe_walk/route/taipei_walk_graph.meta.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final graph = OfflineWalkGraph.parse(asset.bytes, asset.meta);
      final pairs =
          jsonDecode(
                File('test/fixtures/offline_route/taipei_pairs.json')
                    .readAsStringSync(),
              )['pairs']
              as List;
      final refs =
          jsonDecode(
                File('test/fixtures/offline_route/valhalla_reference.json')
                    .readAsStringSync(),
              )['pairs']
              as List;
      expect(pairs.length, 10);
      for (final pair in pairs) {
        sw.Coordinates c(List<dynamic> p) =>
            at((p[0] as num).toDouble(), (p[1] as num).toDouble());
        final a = c(pair['origin']), b = c(pair['destination']);
        final circle = AvoidArea(
          id: 'public-test',
          center: at((a.lat + b.lat) / 2, (a.lng + b.lng) / 2),
          radiusMeters: 50,
          source: 'unit-public-landmark',
        );
        final plain = planOnOfflineGraph(
          graph,
          a,
          b,
          [],
          RoutePreferenceKind.shade,
        ).plan.options.single.route;
        final reference = refs.singleWhere((r) => r['id'] == pair['id']);
        expect(reference['status'], 'ok');
        final ratio =
            plain.distanceMeters / (reference['distanceMeters'] as num);
        expect(
          ratio,
          inInclusiveRange(0.75, 1.25),
          reason: '${pair['id']}: $ratio',
        );
        final full = planOnOfflineGraph(graph, a, b, [
          circle,
        ], RoutePreferenceKind.shade).plan[AvoidLevel.full];
        expect(full, isNotNull, reason: pair['id']);
        expect(full!.passedAreaIds, isEmpty);
        final line = full.route.geometry.coordinates;
        for (var i = 1; i < line.length; i++) {
          expect(
            projectToSegment(
              circle.center,
              fromGeoJson(line[i - 1]),
              fromGeoJson(line[i]),
            ).distance,
            greaterThan(50),
            reason: pair['id'],
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
