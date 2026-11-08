import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_post.dart';
import 'package:town_pass/features/safe_walk/navigation/route_preference.dart';
import 'package:town_pass/features/safe_walk/shared/route_instructions.dart';
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
///
/// Preference: at night (`RoutePreferenceKind.lit`) every request carries
/// pedestrian `use_lit` (0..1; 1 = avoid unlit streets, based on OSM `lit`
/// tags; documented as no guarantee). By day nothing is sent: Valhalla's
/// pedestrian costing has no shade/tree option, so the shade preference is
/// reported as not applied instead of being approximated.
final class ValhallaAvoidingRoutePlanner implements AvoidingRoutePlanner {
  ValhallaAvoidingRoutePlanner({
    required this.hasConsent,
    JsonPoster? post,
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

  /// Strongest lit-street preference (Valhalla range 0..1).
  static const litPreference = 1.0;

  /// POSTs the JSON request: a long GET URL with many polygons is rejected
  /// with HTTP 414, which silently removed both avoiding routes.
  final JsonPoster _post;
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
    required RoutePreferenceKind preference,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final outcome = RoutePreference(
      kind: preference,
      applied: preference == RoutePreferenceKind.lit,
    );
    if (!hasConsent()) throw const WalkingRouteProviderUnavailable();
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

    AvoidRouteOption option(AvoidLevel level, _Line line) => AvoidRouteOption(
      level: level,
      route: _candidate(level, line, areas),
      passedAreaIds: [
        for (final a in areas)
          if (_minDistance(line.coordinates, a.center) < a.radiusMeters) a.id,
      ],
    );

    final options = <AvoidRouteOption>[];
    final shortest = await _route(
      origin,
      destination,
      const [],
      preference,
      cancellation,
    );
    if (shortest == null) {
      return AvoidRoutePlan(
        options: const [],
        originInsideAreaIds: originInside,
        destinationInsideAreaIds: destinationInside,
        preference: outcome,
      );
    }
    options.add(option(AvoidLevel.none, shortest));

    // Nearest areas to the shortest route first, within Valhalla's 10 km
    // exclusion-circumference limit. A detour can reach areas outside this
    // corridor, so every returned route is still checked against all areas.
    final near =
        [
          for (final a in areas)
            if (_minDistance(shortest.coordinates, a.center) <
                a.radiusMeters + corridorMeters)
              a,
        ]..sort(
          (x, y) => _minDistance(
            shortest.coordinates,
            x.center,
          ).compareTo(_minDistance(shortest.coordinates, y.center)),
        );
    final chosen = <AvoidArea>[];
    var budget = maxExcludeCircumferenceMeters;
    for (final a in near) {
      final perimeter = 2 * math.pi * _octagonRadius(a.radiusMeters);
      if (perimeter > budget) break;
      budget -= perimeter;
      chosen.add(a);
    }

    var previous = shortest.coordinates;
    for (final (level, radius) in <(AvoidLevel, double Function(AvoidArea))>[
      (AvoidLevel.center, (_) => AvoidArea.centerRadiusMeters),
      (AvoidLevel.full, (a) => a.radiusMeters),
    ]) {
      final excluded = [
        for (final a in chosen)
          if (avoidable(a, radius(a))) _circle(a.center, radius(a)),
      ];
      if (excluded.isEmpty) continue;
      final line = await _route(
        origin,
        destination,
        excluded,
        preference,
        cancellation,
      );
      if (line == null) continue;
      // Some providers may ignore exclusions or snap onto an excluded road.
      // The request budget is not the product's safety boundary. A response
      // must clear every applicable area, including ones we could not send.
      if (areas.any(
        (a) =>
            avoidable(a, radius(a)) &&
            _minDistance(line.coordinates, a.center) < radius(a),
      )) {
        continue;
      }
      if (_sameLine(previous, line.coordinates)) {
        // Keep one card with the strongest verified avoidance level.
        options.removeLast();
      }
      previous = line.coordinates;
      options.add(option(level, line));
    }
    return AvoidRoutePlan(
      options: options,
      originInsideAreaIds: originInside,
      destinationInsideAreaIds: destinationInside,
      preference: outcome,
    );
  }

  /// Returns null when Valhalla finds no path; throws when it is unreachable.
  Future<_Line?> _route(
    sw.Coordinates origin,
    sw.Coordinates destination,
    List<List<List<double>>> excluded,
    RoutePreferenceKind preference,
    SafeWalkCancellation? cancellation,
  ) {
    final run = _queue.then((_) async {
      final last = _lastRequest;
      if (last != null) {
        final gap = minInterval - DateTime.now().difference(last);
        if (gap > Duration.zero) {
          await raceCancellation(_wait(gap), cancellation);
        }
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
        if (preference == RoutePreferenceKind.lit)
          'costing_options': {
            'pedestrian': {'use_lit': litPreference},
          },
        // Maneuvers give street names for turn-by-turn text (no narrative).
        'directions_type': 'maneuvers',
        'units': 'kilometers',
        if (excluded.isNotEmpty) 'exclude_polygons': excluded,
      };
      final Object? json;
      try {
        final (status, text) = await raceCancellation(
          _post(
            endpoint,
            jsonEncode(body),
            cancellation: cancellation,
            hasConsent: hasConsent,
          ),
          cancellation,
        ).timeout(const Duration(seconds: 12));
        if (status == 400 && _isNoPath(text)) return null;
        // Server, rate-limit or request errors are never proof of no path.
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
    // A queued caller can leave immediately while the preceding request keeps
    // its own lifetime. The queued operation still checks cancellation before
    // it could send anything.
    return raceCancellation(run, cancellation);
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
    final first = legs.first;
    return _Line(
      coordinates,
      time is num ? time.toDouble() : null,
      // Shape indices are per leg; a single leg is all this planner sends.
      legs.length == 1 && first is Map ? first['maneuvers'] : null,
    );
  }

  sw.RouteCandidate _candidate(
    AvoidLevel level,
    _Line line,
    List<AvoidArea> areas,
  ) {
    final candidate = sw.RouteCandidate(
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
          AvoidLevel.full => '完全避開',
        },
      ],
      warnings: const ['依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行'],
    );
    routeInstructions[candidate] = instructionsFromValhalla(line.maneuvers);
    return candidate;
  }

  /// Circumscribed regular octagon (edges never cut into the circle) plus
  /// 2 m, in GeoJSON `[lng, lat]` order, closed, rounded to 6 decimals.
  static double _octagonRadius(double radiusMeters) =>
      radiusMeters / math.cos(math.pi / 8) + 2;

  static List<List<double>> _circle(sw.Coordinates c, double radiusMeters) {
    final r = _octagonRadius(radiusMeters);
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
  const _Line(this.coordinates, this.seconds, [this.maneuvers]);
  final List<List<double>> coordinates;
  final double? seconds;
  final Object? maneuvers;
}

double _round6(double v) => (v * 1e6).roundToDouble() / 1e6;

/// Valhalla error 442 / 443: no path between the locations.
bool _isNoPath(String body) {
  try {
    final code = (jsonDecode(body) as Map)['error_code'];
    return code == 442 || code == 443;
  } catch (_) {
    return false;
  }
}
