import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/json_post.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Three walking routes (best / not through report centres / never inside a
/// report circle) from Valhalla's `pedestrian` costing with `exclude_polygons`.
///
/// Valhalla (MIT License, https://github.com/valhalla/valhalla) runs on the
/// FOSSGIS public server by default; routing data © OpenStreetMap
/// contributors (ODbL). The server allows at most one request per second and
/// guarantees no availability, so requests are sent one at a time and a
/// self-hosted [endpoint] is needed for production.
final class ValhallaAvoidingRoutePlanner implements AvoidingRoutePlanner {
  ValhallaAvoidingRoutePlanner({
    required this.hasConsent,
    Future<(int, String)> Function(Uri url, String body)? post,
    Uri? endpoint,
    this.minInterval = const Duration(milliseconds: 1100),
    Future<void> Function(Duration)? wait,
  }) : endpoint = endpoint ?? Uri.parse(defaultEndpoint),
       _wait = wait ?? Future<void>.delayed,
       _post = post ?? postJsonText;

  /// Valhalla rejects exclusions whose total circumference exceeds 10 km.
  static const maxExcludeCircumferenceMeters = 9500.0;

  /// Only areas this close to the shortest route are sent for exclusion.
  static const corridorMeters = 300.0;

  static const defaultEndpoint = 'https://valhalla1.openstreetmap.de/route';
  static const providerId = 'valhalla-pedestrian';

  /// POSTs the JSON request (a long GET URL is rejected with 414).
  final Future<(int, String)> Function(Uri url, String body) _post;
  final bool Function() hasConsent;
  final Uri endpoint;

  /// FOSSGIS terms: at most one request per second.
  final Duration minInterval;
  final Future<void> Function(Duration) _wait;
  DateTime? _lastRequest;
  Future<void> _queue = Future.value();

  @override
  Future<AvoidRoutePlan> plan({
    required sw.Coordinates origin,
    required sw.Coordinates destination,
    required List<AvoidArea> areas,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (!hasConsent()) throw const WalkingRouteProviderUnavailable();

    bool inside(AvoidArea a, sw.Coordinates p, double r) =>
        distanceMeters(a.center, p) <= r;
    final originInside = [
      for (final a in areas)
        if (inside(a, origin, a.radiusMeters)) a.id,
    ];
    final destinationInside = [
      for (final a in areas)
        if (inside(a, destination, a.radiusMeters)) a.id,
    ];

    // A circle holding the start or end cannot be avoided; leave it out.
    bool avoidable(AvoidArea a, double r) =>
        !inside(a, origin, r) && !inside(a, destination, r);

    final options = <AvoidRouteOption>[];
    AvoidRouteOption option(AvoidLevel level, _Line line) => AvoidRouteOption(
      level: level,
      route: _candidate(level, line, areas),
      passedAreaIds: [
        for (final a in areas)
          if (_minDistance(line.coordinates, a.center) < a.radiusMeters) a.id,
      ],
    );

    final shortest = await _route(origin, destination, const [], cancellation);
    if (shortest == null) {
      return AvoidRoutePlan(
        options: const [],
        originInsideAreaIds: originInside,
        destinationInsideAreaIds: destinationInside,
      );
    }
    options.add(option(AvoidLevel.none, shortest));

    // Nearest areas to the shortest route first, within Valhalla's limit.
    final near = [
      for (final a in areas)
        if (_minDistance(shortest.coordinates, a.center) <
            a.radiusMeters + corridorMeters)
          a,
    ]..sort((x, y) => _minDistance(shortest.coordinates, x.center)
        .compareTo(_minDistance(shortest.coordinates, y.center)));
    final chosen = <AvoidArea>[];
    var budget = maxExcludeCircumferenceMeters;
    for (final a in near) {
      final perimeter = 2 * math.pi * (a.radiusMeters / math.cos(math.pi / 8) + 2);
      if (perimeter > budget) break;
      budget -= perimeter;
      chosen.add(a);
    }

    List<List<double>> previous = shortest.coordinates;
    for (final (level, radius) in <(AvoidLevel, double Function(AvoidArea))>[
      (AvoidLevel.center, (_) => AvoidArea.centerRadiusMeters),
      (AvoidLevel.full, (a) => a.radiusMeters),
    ]) {
      final excluded = [
        for (final a in chosen)
          if (avoidable(a, radius(a))) _circle(a.center, radius(a)),
      ];
      if (excluded.isEmpty) continue;
      final line = await _route(origin, destination, excluded, cancellation);
      if (line == null || _sameLine(previous, line.coordinates)) continue;
      previous = line.coordinates;
      options.add(option(level, line));
    }
    return AvoidRoutePlan(
      options: options,
      originInsideAreaIds: originInside,
      destinationInsideAreaIds: destinationInside,
    );
  }

  /// Returns null when Valhalla finds no path; throws when it is unreachable.
  Future<_Line?> _route(
    sw.Coordinates origin,
    sw.Coordinates destination,
    List<List<List<double>>> excluded,
    SafeWalkCancellation? cancellation,
  ) {
    final run = _queue.then((_) async {
      final last = _lastRequest;
      if (last != null) {
        final gap = minInterval - DateTime.now().difference(last);
        if (gap > Duration.zero) await _wait(gap);
      }
      cancellation?.throwIfCancelled();
      if (!hasConsent()) throw const WalkingRouteProviderUnavailable();
      _lastRequest = DateTime.now();
      final body = {
        'locations': [
          {'lat': origin.lat, 'lon': origin.lng},
          {'lat': destination.lat, 'lon': destination.lng},
        ],
        'costing': 'pedestrian',
        'directions_type': 'none',
        if (excluded.isNotEmpty) 'exclude_polygons': excluded,
      };
      final Object? json;
      try {
        final (status, text) = await _post(endpoint, jsonEncode(body));
        // Valhalla answers "no path" (and other request problems) with 400.
        if (status == 400) return null;
        if (status != 200) throw const WalkingRouteProviderUnavailable();
        json = jsonDecode(text);
      } on WalkingRouteProviderUnavailable {
        rethrow;
      } on SafeWalkCancelledException {
        rethrow;
      } catch (_) {
        // Any other transport fault must not leave the plan hanging.
        throw const WalkingRouteProviderUnavailable();
      }
      cancellation?.throwIfCancelled();
      try {
        return _parse(json);
      } on WalkingRouteProviderUnavailable {
        rethrow;
      } catch (_) {
        throw const WalkingRouteProviderUnavailable();
      }
    });
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  static _Line? _parse(Object? json) {
    if (json is! Map) throw const WalkingRouteProviderUnavailable();
    final trip = json['trip'];
    if (trip is! Map || trip['status'] != 0) return null;
    final legs = trip['legs'];
    final summary = trip['summary'];
    if (legs is! List || legs.isEmpty || summary is! Map) {
      throw const WalkingRouteProviderUnavailable();
    }
    final coordinates = <List<double>>[];
    for (final leg in legs) {
      final shape = leg is Map ? leg['shape'] : null;
      if (shape is! String) throw const WalkingRouteProviderUnavailable();
      final points = decodePolyline6(shape);
      coordinates.addAll(coordinates.isEmpty ? points : points.skip(1));
    }
    if (coordinates.length < 2) throw const WalkingRouteProviderUnavailable();
    final time = summary['time'];
    return _Line(coordinates, time is num ? time.toDouble() : null);
  }

  sw.RouteCandidate _candidate(
    AvoidLevel level,
    _Line line,
    List<AvoidArea> areas,
  ) {
    final avoided = level == AvoidLevel.none
        ? 0
        : areas
              .where(
                (a) =>
                    _minDistance(line.coordinates, a.center) >= a.radiusMeters,
              )
              .length;
    return sw.RouteCandidate(
      id: 'valhalla-${level.name}',
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: [
          for (final c in line.coordinates) (longitude: c[0], latitude: c[1]),
        ],
      ),
      distanceMeters: polylineLengthMeters([
        for (final c in line.coordinates) (longitude: c[0], latitude: c[1]),
      ]),
      durationSeconds: line.seconds,
      viaPointIds: const [],
      provider: providerId,
      walkingNetworkVerified: true,
      explanations: [
        switch (level) {
          AvoidLevel.none => '最快路線',
          AvoidLevel.center => '不經過回報點中心',
          AvoidLevel.full => '完全避開 $avoided 個範圍',
        },
      ],
      warnings: const ['依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行'],
    );
  }

  /// Regular octagon in GeoJSON `[lng, lat]` order, closed.
  static List<List<double>> _circle(sw.Coordinates c, double radiusMeters) {
    // Circumscribed octagon (edges never cut into the circle) plus 2 m.
    final r = radiusMeters / math.cos(math.pi / 8) + 2;
    final dLat = r / 110540;
    final dLng = r / (111320 * math.cos(c.lat * math.pi / 180));
    return [
      for (var k = 0; k <= 8; k++)
        [
          _round6(c.lng + dLng * math.sin(2 * math.pi * k / 8)),
          _round6(c.lat + dLat * math.cos(2 * math.pi * k / 8)),
        ],
    ];
  }

  static bool _sameLine(List<List<double>> a, List<List<double>> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every(
        (i) =>
            (a[i][0] - b[i][0]).abs() < 1e-6 &&
            (a[i][1] - b[i][1]).abs() < 1e-6,
      );
}

/// Shortest distance in metres from [p] to the polyline ([lng, lat] pairs).
double _minDistance(List<List<double>> line, sw.Coordinates p) {
  final k = 111320 * math.cos(p.lat * math.pi / 180);
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    final ax = (line[i][0] - p.lng) * k, ay = (line[i][1] - p.lat) * 110540;
    final bx = (line[i + 1][0] - p.lng) * k,
        by = (line[i + 1][1] - p.lat) * 110540;
    final dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
    final t = len == 0 ? 0.0 : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
    best = math.min(
      best,
      math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)),
    );
  }
  return best;
}

/// Decodes a Google-style encoded polyline with 6 decimals (Valhalla's
/// `shape`) into GeoJSON `[lng, lat]` pairs.
List<List<double>> decodePolyline6(String encoded) {
  final out = <List<double>>[];
  var index = 0, lat = 0, lng = 0;
  int next() {
    var shift = 0, result = 0, byte = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    // Not `~`: on web, bitwise results are unsigned 32-bit, which turns a
    // negative step into a huge number.
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (index < encoded.length) {
    lat += next();
    lng += next();
    out.add([lng / 1e6, lat / 1e6]);
  }
  return out;
}

final class _Line {
  const _Line(this.coordinates, this.seconds);
  final List<List<double>> coordinates;
  final double? seconds;
}

double _round6(double v) => (v * 1e6).roundToDouble() / 1e6;
