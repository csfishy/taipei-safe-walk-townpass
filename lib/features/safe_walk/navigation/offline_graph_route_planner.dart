import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_route_worker.dart';
import 'package:town_pass/features/safe_walk/navigation/offline_walk_graph.dart';
import 'package:town_pass/features/safe_walk/navigation/route_preference.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/features/safe_walk/shared/route_instructions.dart';

typedef OfflineGraphAsset = ({Uint8List bytes, Map<String, dynamic> meta});

/// Native-only graph parsing, SHA validation, snapping and A* run in a request
/// isolate. Only the bundled public OSM asset is cached; areas stay in memory.
final class OfflineGraphRoutePlanner implements AvoidingRoutePlanner {
  OfflineGraphRoutePlanner({
    required this.loadAsset,
    required this.isNavigationActive,
  });
  static const providerId = 'offline-osm-graph';
  static const unavailableMessage = '離線路網範圍外或附近無步行路段，或離線資料無法載入';
  final Future<OfflineGraphAsset> Function() loadAsset;
  final bool Function() isNavigationActive;
  Future<OfflineGraphAsset>? _asset;

  @override
  Future<AvoidRoutePlan> plan({
    required sw.Coordinates origin,
    required sw.Coordinates destination,
    required List<AvoidArea> areas,
    required RoutePreferenceKind preference,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (!isNavigationActive()) throw const WalkingRouteProviderUnavailable();
    try {
      final asset = await raceCancellation(
        _asset ??= loadAsset().timeout(const Duration(seconds: 15)),
        cancellation,
      );
      if (!isNavigationActive()) throw const SafeWalkCancelledException();
      final result = await runOfflineWorker(
        () =>
            computeOfflineRoute(asset, origin, destination, areas, preference),
        cancellation,
      );
      cancellation?.throwIfCancelled();
      if (!isNavigationActive()) throw const SafeWalkCancelledException();
      // Expando attachments do not cross isolates. Restore on UI-isolate objects.
      for (var i = 0; i < result.plan.options.length; i++) {
        routeInstructions[result.plan.options[i].route] =
            result.instructions[i];
      }
      return result.plan;
    } on SafeWalkCancelledException {
      rethrow;
    } catch (_) {
      _asset = null;
      throw const WalkingRouteProviderUnavailable();
    }
  }
}

typedef OfflineRouteOutput = ({
  AvoidRoutePlan plan,
  List<List<RouteInstruction>> instructions,
});

/// Public for deterministic graph/algorithm tests and benchmark tooling.
OfflineRouteOutput computeOfflineRoute(
  OfflineGraphAsset asset,
  sw.Coordinates origin,
  sw.Coordinates destination,
  List<AvoidArea> areas,
  RoutePreferenceKind preference,
) {
  final graph = OfflineWalkGraph.parse(asset.bytes, asset.meta);
  return planOnOfflineGraph(graph, origin, destination, areas, preference);
}

OfflineRouteOutput planOnOfflineGraph(
  OfflineWalkGraph graph,
  sw.Coordinates origin,
  sw.Coordinates destination,
  List<AvoidArea> areas,
  RoutePreferenceKind preference,
) {
  if (!isValidLatLng(origin.lat, origin.lng) ||
      !isValidLatLng(destination.lat, destination.lng) ||
      areas.any(
        (a) =>
            !isValidLatLng(a.center.lat, a.center.lng) ||
            !a.radiusMeters.isFinite ||
            a.radiusMeters <= 0,
      )) {
    throw const WalkingRouteProviderUnavailable();
  }
  final start = graph.nearestSegment(origin),
      end = graph.nearestSegment(destination);
  if (start.distance > maxEndpointSnapMeters ||
      end.distance > maxEndpointSnapMeters) {
    throw const WalkingRouteProviderUnavailable();
  }
  final originInside = [
    for (final a in areas)
      if (distanceMeters(origin, a.center) <= a.radiusMeters) a.id,
  ];
  final destinationInside = [
    for (final a in areas)
      if (distanceMeters(destination, a.center) <= a.radiusMeters) a.id,
  ];
  final options = <AvoidRouteOption>[];
  final instructions = <List<RouteInstruction>>[];
  List<sw.GeoJsonCoordinate>? previous;
  for (final level in AvoidLevel.values) {
    final radius = level == AvoidLevel.full
        ? (AvoidArea a) => a.radiusMeters
        : (AvoidArea _) => AvoidArea.centerRadiusMeters;
    final excluded = level == AvoidLevel.none
        ? <AvoidArea>[]
        : [
            for (final a in areas)
              if (distanceMeters(origin, a.center) > radius(a) &&
                  distanceMeters(destination, a.center) > radius(a))
                a,
          ];
    final path = _aStar(graph, start, end, excluded, radius);
    if (path == null || path.points.length < 2) continue;
    final line = [for (final p in path.points) toGeoJson(p)];
    final passed = [
      for (final a in areas)
        if (_lineDistance(path.points, a.center) <= a.radiusMeters) a.id,
    ];
    if (previous != null &&
        const ListEquality<sw.GeoJsonCoordinate>().equals(previous, line)) {
      options.removeLast();
      instructions.removeLast();
    }
    previous = line;
    final candidate = sw.RouteCandidate(
      id: 'offline-${level.name}',
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(coordinates: line),
      distanceMeters: polylineLengthMeters(line),
      durationSeconds: null,
      viaPointIds: const [],
      provider: OfflineGraphRoutePlanner.providerId,
      walkingNetworkVerified: true,
      explanations: [
        switch (level) {
          AvoidLevel.none => '最快路線',
          AvoidLevel.center => '不經過回報點中心',
          AvoidLevel.full => '完全避開',
        },
      ],
      warnings: [
        '離線路網資料：${graph.snapshotDate} 快照，可能與現況不同',
        '© OpenStreetMap contributors · ODbL 1.0',
        '依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行',
        if (originInside.isNotEmpty || destinationInside.isNotEmpty)
          '起點或目的地位於避讓緩衝區內，無法完整避開該區域',
      ],
    );
    options.add(
      AvoidRouteOption(level: level, route: candidate, passedAreaIds: passed),
    );
    instructions.add(offlineInstructions(path.points, path.streets));
  }
  return (
    plan: AvoidRoutePlan(
      options: options,
      originInsideAreaIds: originInside,
      destinationInsideAreaIds: destinationInside,
      preference: RoutePreference(kind: preference, applied: false),
    ),
    instructions: instructions,
  );
}

double _lineDistance(List<sw.Coordinates> points, sw.Coordinates p) {
  var best = double.infinity;
  for (var i = 1; i < points.length; i++) {
    best = math.min(
      best,
      projectToSegment(p, points[i - 1], points[i]).distance,
    );
  }
  return best;
}

typedef _Arc = ({int to, double meters, String? street});
typedef _Path = ({List<sw.Coordinates> points, List<String?> streets});

_Path? _aStar(
  OfflineWalkGraph g,
  GraphSnap start,
  GraphSnap end,
  List<AvoidArea> excluded,
  double Function(AvoidArea) radius,
) {
  final source = g.nodeCount, goal = source + 1;
  sw.GeoJsonCoordinate point(int n) => n == source
      ? toGeoJson(start.point)
      : n == goal
      ? toGeoJson(end.point)
      : g.geoCoordinate(n);
  bool reverse(GraphSnap s) {
    for (var e = g.begin(s.to); e < g.begin(s.to + 1); e++) {
      if (g.target(e) == s.from) return true;
    }
    return false;
  }

  final startReverse = reverse(start), endReverse = reverse(end);
  _Arc arc(int to, double length, int e) =>
      (to: to, meters: length, street: g.street(e));
  Iterable<_Arc> neighbors(int n) sync* {
    if (n == source) {
      yield arc(
        start.to,
        (1 - start.fraction) * g.length(start.edge),
        start.edge,
      );
      if (startReverse || start.fraction == 0) {
        yield arc(
          start.from,
          start.fraction * g.length(start.edge),
          start.edge,
        );
      }
      // Direct partial traversal of the same directed or reverse segment.
      double? endFraction;
      if (start.from == end.from && start.to == end.to) {
        endFraction = end.fraction;
      }
      if (start.from == end.to && start.to == end.from) {
        endFraction = 1 - end.fraction;
      }
      if (endFraction != null &&
          (endFraction >= start.fraction || startReverse)) {
        yield arc(
          goal,
          (endFraction - start.fraction).abs() * g.length(start.edge),
          start.edge,
        );
      }
      return;
    }
    for (var e = g.begin(n); e < g.begin(n + 1); e++) {
      yield arc(g.target(e), g.length(e), e);
    }
    if (n == end.from) {
      yield arc(goal, end.fraction * g.length(end.edge), end.edge);
    }
    if (n == end.to && (endReverse || end.fraction == 1)) {
      yield arc(goal, (1 - end.fraction) * g.length(end.edge), end.edge);
    }
  }

  final costs = Float64List(g.nodeCount + 2)
    ..fillRange(0, g.nodeCount + 2, double.infinity);
  final parent = Int32List(g.nodeCount + 2)..fillRange(0, g.nodeCount + 2, -1);
  final streets = <int, String?>{};
  final queue = HeapPriorityQueue<({int node, double cost, double score})>(
    (a, b) => a.score.compareTo(b.score),
  );
  costs[source] = 0;
  queue.add((
    node: source,
    cost: 0,
    score: distanceMeters(start.point, end.point),
  ));
  while (queue.isNotEmpty) {
    final current = queue.removeFirst(), n = current.node;
    if (current.cost > costs[n]) continue;
    if (n == goal) {
      final nodes = <int>[goal];
      while (nodes.last != source) {
        nodes.add(parent[nodes.last]);
      }
      final forward = nodes.reversed.toList();
      return (
        points: [for (final v in forward) fromGeoJson(point(v))],
        streets: [for (final v in forward.skip(1)) streets[v]],
      );
    }
    final a = point(n);
    for (final edge in neighbors(n)) {
      final b = point(edge.to);
      if (excluded.any((area) {
        final d = projectToGeoJsonSegment(
          toGeoJson(area.center),
          a,
          b,
        ).distance;
        // Full excludes touching; centre excludes strictly less than 15m.
        return radius(area) == AvoidArea.centerRadiusMeters
            ? d < radius(area)
            : d <= radius(area);
      })) {
        continue;
      }
      final cost = costs[n] + edge.meters;
      if (cost >= costs[edge.to]) continue;
      costs[edge.to] = cost;
      parent[edge.to] = n;
      streets[edge.to] = edge.street;
      queue.add((
        node: edge.to,
        cost: cost,
        score: cost + geoJsonDistanceMeters(b, toGeoJson(end.point)),
      ));
    }
  }
  return null;
}

const offlineStraightDegrees = 20.0;
const offlineSlightDegrees = 45.0;
const offlineSharpDegrees = 120.0;
const offlineUTurnDegrees = 165.0;

TurnKind offlineTurnKind(double delta) {
  final angle = delta.abs();
  if (angle < offlineStraightDegrees) return TurnKind.straight;
  if (angle >= offlineUTurnDegrees) return TurnKind.uTurn;
  if (angle >= offlineSharpDegrees) {
    return delta < 0 ? TurnKind.sharpLeft : TurnKind.sharpRight;
  }
  if (angle >= offlineSlightDegrees) {
    return delta < 0 ? TurnKind.left : TurnKind.right;
  }
  return delta < 0 ? TurnKind.slightLeft : TurnKind.slightRight;
}

double _bearing(sw.Coordinates a, sw.Coordinates b) {
  final lat1 = a.lat * math.pi / 180, lat2 = b.lat * math.pi / 180;
  final lon = (b.lng - a.lng) * math.pi / 180;
  return math.atan2(
        math.sin(lon) * math.cos(lat2),
        math.cos(lat1) * math.sin(lat2) -
            math.sin(lat1) * math.cos(lat2) * math.cos(lon),
      ) *
      180 /
      math.pi;
}

List<RouteInstruction> offlineInstructions(
  List<sw.Coordinates> points,
  List<String?> streets,
) {
  final output = <RouteInstruction>[];
  for (var i = 0; i < streets.length; i++) {
    final length = distanceMeters(points[i], points[i + 1]);
    if (length < 0.01) {
      continue; // snapped endpoint coincides with an OSM vertex
    }
    final turn = output.isEmpty
        ? TurnKind.start
        : offlineTurnKind(
            (_bearing(points[i], points[i + 1]) -
                        _bearing(points[i - 1], points[i]) +
                        540) %
                    360 -
                180,
          );
    final previous = output.lastOrNull;
    if (previous != null &&
        previous.street == streets[i] &&
        turn == TurnKind.straight) {
      output[output.length - 1] = RouteInstruction(
        turn: previous.turn,
        street: previous.street,
        meters: previous.meters + length.round(),
        shapeIndex: previous.shapeIndex,
      );
    } else {
      output.add(
        RouteInstruction(
          turn: turn,
          street: streets[i],
          meters: length.round(),
          shapeIndex: i,
        ),
      );
    }
  }
  return output;
}
