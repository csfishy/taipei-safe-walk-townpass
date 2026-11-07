import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
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
    required this.transport,
    required this.hasConsent,
    Uri? endpoint,
    this.minInterval = const Duration(milliseconds: 1100),
    Future<void> Function(Duration)? wait,
  }) : endpoint = endpoint ?? Uri.parse(defaultEndpoint),
       _wait = wait ?? Future<void>.delayed;

  static const defaultEndpoint = 'https://valhalla1.openstreetmap.de/route';
  static const providerId = 'valhalla-pedestrian';

  final JsonTransport transport;
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
    if (!isValidLatLng(origin.lat, origin.lng) ||
        !isValidLatLng(destination.lat, destination.lng) ||
        areas.any((a) => !a.radiusMeters.isFinite || a.radiusMeters <= 0)) {
      throw const WalkingRouteProviderUnavailable();
    }

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
    List<List<List<double>>> polygons(double Function(AvoidArea) radius) => [
      for (final a in areas)
        if (!inside(a, origin, radius(a)) && !inside(a, destination, radius(a)))
          _circle(a.center, radius(a)),
    ];

    final levels = <(AvoidLevel, List<List<List<double>>>)>[
      (AvoidLevel.none, const []),
      if (areas.isNotEmpty) ...[
        (AvoidLevel.center, polygons((_) => AvoidArea.centerRadiusMeters)),
        (AvoidLevel.full, polygons((a) => a.radiusMeters)),
      ],
    ];

    final options = <AvoidRouteOption>[];
    List<List<double>>? previous;
    String? previousExcluded;
    for (final (level, excluded) in levels) {
      // Same exclusions as the level before give the same route; skip the call.
      final key = jsonEncode(excluded);
      if (key == previousExcluded && options.isNotEmpty) continue;
      previousExcluded = key;
      final line = await _route(origin, destination, excluded, cancellation);
      if (line == null) continue;
      // Some providers may ignore exclusions or snap onto an excluded road.
      // Verify their original geometry before describing it as avoidance.
      final requiredRadius = switch (level) {
        AvoidLevel.none => null,
        AvoidLevel.center => (AvoidArea a) => AvoidArea.centerRadiusMeters,
        AvoidLevel.full => (AvoidArea a) => a.radiusMeters,
      };
      if (requiredRadius != null &&
          areas.any((a) {
            final radius = requiredRadius(a);
            return !inside(a, origin, radius) &&
                !inside(a, destination, radius) &&
                _minDistance(line.coordinates, a.center) < radius;
          })) {
        continue;
      }
      if (previous != null && _sameLine(previous, line.coordinates)) {
        // Keep one card, with the strongest verified avoidance level. A full
        // 50 m detour must not lose that label just because the 15 m request
        // happened to return the same road.
        options.removeLast();
      }
      previous = line.coordinates;
      options.add(
        AvoidRouteOption(
          level: level,
          route: _candidate(level, line, areas),
          passedAreaIds: [
            for (final a in areas)
              if (_minDistance(line.coordinates, a.center) < a.radiusMeters)
                a.id,
          ],
        ),
      );
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
        json = await transport.getJson(
          endpoint.replace(queryParameters: {'json': jsonEncode(body)}),
          cancellation: cancellation,
        );
      } on JsonTransportException {
        // This transport does not expose the HTTP status/body. A server or
        // rate-limit failure must not be reported as proof of no path.
        throw const WalkingRouteProviderUnavailable();
      } on SafeWalkCancelledException {
        rethrow;
      } catch (_) {
        // Any other transport fault must not leave the plan hanging.
        throw const WalkingRouteProviderUnavailable();
      }
      cancellation?.throwIfCancelled();
      if (!hasConsent()) throw const WalkingRouteProviderUnavailable();
      try {
        final line = _parse(json);
        if (line == null) return null;
        if (distanceMeters(origin, _coordinate(line.coordinates.first)) >
                maxEndpointSnapMeters ||
            distanceMeters(destination, _coordinate(line.coordinates.last)) >
                maxEndpointSnapMeters) {
          throw const WalkingRouteProviderUnavailable();
        }
        return line;
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
    if (trip is! Map || trip['status'] is! num) {
      throw const WalkingRouteProviderUnavailable();
    }
    if (trip['status'] != 0) return null;
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
      if (points.length < 2 || points.any((p) => !isValidLatLng(p[1], p[0]))) {
        throw const WalkingRouteProviderUnavailable();
      }
      coordinates.addAll(coordinates.isEmpty ? points : points.skip(1));
    }
    if (coordinates.length < 2) throw const WalkingRouteProviderUnavailable();
    final time = summary['time'];
    if (time != null && (time is! num || !time.isFinite || time < 0)) {
      throw const WalkingRouteProviderUnavailable();
    }
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
          AvoidLevel.none => '最短步行路線',
          AvoidLevel.center => '避開參考點中心 15 公尺',
          AvoidLevel.full => '避開 $avoided 個避讓緩衝區',
        },
      ],
      warnings: const ['依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行'],
    );
  }

  /// Regular 16-gon in GeoJSON `[lng, lat]` order, closed.
  static List<List<double>> _circle(sw.Coordinates c, double radiusMeters) {
    final r = radiusMeters + 2; // edges just outside still count as clear
    final dLat = r / 110540;
    final dLng = r / (111320 * math.cos(c.lat * math.pi / 180));
    return [
      for (var k = 0; k <= 16; k++)
        [
          c.lng + dLng * math.sin(2 * math.pi * k / 16),
          c.lat + dLat * math.cos(2 * math.pi * k / 16),
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

sw.Coordinates _coordinate(List<double> point) =>
    sw.Coordinates(lat: point[1], lng: point[0]);

/// Shortest distance in metres from [p] to the polyline ([lng, lat] pairs).
double _minDistance(List<List<double>> line, sw.Coordinates p) {
  final metresPerDegree = earthRadiusMeters * math.pi / 180;
  final k = metresPerDegree * math.cos(p.lat * math.pi / 180);
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    final ax = (line[i][0] - p.lng) * k,
        ay = (line[i][1] - p.lat) * metresPerDegree;
    final bx = (line[i + 1][0] - p.lng) * k,
        by = (line[i + 1][1] - p.lat) * metresPerDegree;
    final dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
    final t = len == 0 ? 0.0 : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
    best = math.min(
      best,
      distanceMeters(
        p,
        sw.Coordinates(
          lng: line[i][0] + t * (line[i + 1][0] - line[i][0]),
          lat: line[i][1] + t * (line[i + 1][1] - line[i][1]),
        ),
      ),
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
