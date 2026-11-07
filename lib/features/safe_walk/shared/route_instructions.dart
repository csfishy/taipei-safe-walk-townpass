import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Turn-by-turn text for a route, like 「在士東路口右轉，沿士東路直行 300 公尺」.
enum TurnKind {
  start,
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
}

const turnKindLabel = {
  TurnKind.start: '出發',
  TurnKind.straight: '直行',
  TurnKind.slightLeft: '靠左',
  TurnKind.left: '左轉',
  TurnKind.sharpLeft: '向左急轉',
  TurnKind.slightRight: '靠右',
  TurnKind.right: '右轉',
  TurnKind.sharpRight: '向右急轉',
  TurnKind.uTurn: '迴轉',
};

final class RouteInstruction {
  const RouteInstruction({
    required this.turn,
    required this.street,
    required this.meters,
    required this.shapeIndex,
  });

  final TurnKind turn;

  /// The road walked after this point; null when the map has no name.
  final String? street;

  /// Length walked until the next instruction.
  final int meters;

  /// Index into the route geometry where this instruction starts.
  final int shapeIndex;

  /// 「在士東路口右轉」／「沿士東路出發」／「直行」.
  String get action {
    final s = street;
    return switch (turn) {
      TurnKind.start => s == null ? '出發' : '沿$s出發',
      TurnKind.straight => s == null ? '繼續直行' : '沿$s繼續直行',
      _ =>
        s == null
            ? turnKindLabel[turn]!
            : '在${_junction(s)}${turnKindLabel[turn]}',
    };
  }

  /// 「沿士東路直行 300 公尺」.
  String get follow => '${street == null ? '' : '沿$street'}直行 $meters 公尺';

  /// 「在士東路口右轉，沿士東路直行 300 公尺」.
  String get text => switch (turn) {
    TurnKind.start => '$action，直行 $meters 公尺',
    TurnKind.straight => '$action $meters 公尺',
    _ => '$action，$follow',
  };
}

/// 士東路 → 士東路口；士東路91巷 → 士東路91巷口；中山北路六段 → 中山北路六段路口.
String _junction(String street) =>
    RegExp(r'[路街巷弄道]$').hasMatch(street) ? '$street口' : '$street路口';

/// Instructions attached to a route candidate by the provider that planned it
/// (the shared route contract has no field for them).
final routeInstructions = Expando<List<RouteInstruction>>('routeInstructions');

/// Valhalla `maneuvers` (with `units: kilometers`) → instructions. Arrival
/// is left out; the UI adds 「抵達…」. Unknown maneuver types read as straight.
List<RouteInstruction> instructionsFromValhalla(Object? maneuvers) {
  if (maneuvers is! List) return const [];
  final out = <RouteInstruction>[];
  for (final m in maneuvers) {
    if (m is! Map) continue;
    final type = m['type'];
    if (type is! int || type == 4 || type == 5 || type == 6) continue;
    final names = m['street_names'];
    final street = names is List && names.isNotEmpty && names.first is String
        ? (names.first as String).trim()
        : null;
    final length = m['length'];
    final index = m['begin_shape_index'];
    final meters = length is num ? (length * 1000).round() : 0;
    out.add(
      RouteInstruction(
        turn: switch (type) {
          1 || 2 || 3 => TurnKind.start,
          9 || 18 || 20 || 23 => TurnKind.slightRight,
          10 => TurnKind.right,
          11 => TurnKind.sharpRight,
          12 || 13 => TurnKind.uTurn,
          14 => TurnKind.sharpLeft,
          15 => TurnKind.left,
          16 || 19 || 21 || 24 => TurnKind.slightLeft,
          _ => TurnKind.straight,
        },
        street: street == null || street.isEmpty ? null : street,
        meters: meters < 100 ? meters : (meters / 10).round() * 10,
        shapeIndex: index is int ? index : 0,
      ),
    );
  }
  return out;
}

/// Where the walker is along a route: the next instruction ahead (null when
/// only the arrival is left), metres to it, and metres to the end.
typedef RouteProgress = ({
  RouteInstruction? next,
  double toNextMeters,
  double remainingMeters,
});

/// Projects [at] onto the closest route segment and measures ahead along it.
/// Distances exclude the sideways distance from the fix to the route. Reaching
/// a vertex advances its instruction; approaching it does not.
RouteProgress routeProgress(
  List<sw.GeoJsonCoordinate> line,
  List<RouteInstruction> steps,
  sw.Coordinates at,
) {
  if (line.length < 2) {
    return (next: null, toNextMeters: 0, remainingMeters: 0);
  }
  final cumulative = <double>[0];
  for (var i = 1; i < line.length; i++) {
    cumulative.add(
      cumulative.last +
          _meters(
            line[i - 1].latitude,
            line[i - 1].longitude,
            line[i].latitude,
            line[i].longitude,
          ),
    );
  }
  if (cumulative.last == 0) {
    return (next: null, toNextMeters: 0, remainingMeters: 0);
  }

  // A local equirectangular plane preserves the fraction along each short
  // walking-route segment; cumulative lengths remain great-circle metres.
  final longitudeScale = math.cos(at.lat * math.pi / 180);
  var progress = 0.0;
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    final ax = (line[i].longitude - at.lng) * longitudeScale;
    final ay = line[i].latitude - at.lat;
    final dx = (line[i + 1].longitude - line[i].longitude) * longitudeScale;
    final dy = line[i + 1].latitude - line[i].latitude;
    final lengthSquared = dx * dx + dy * dy;
    final fraction = lengthSquared == 0
        ? 0.0
        : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0);
    final x = ax + fraction * dx;
    final y = ay + fraction * dy;
    final distanceSquared = x * x + y * y;
    if (distanceSquared < best) {
      best = distanceSquared;
      progress = cumulative[i] + fraction * (cumulative[i + 1] - cumulative[i]);
    }
  }

  RouteInstruction? next;
  for (final s in steps) {
    final index = s.shapeIndex;
    if (index >= 0 &&
        index < cumulative.length &&
        cumulative[index] > progress + 0.001) {
      next = s;
      break;
    }
  }

  return (
    next: next,
    toNextMeters:
        (next == null ? cumulative.last : cumulative[next.shapeIndex]) -
        progress,
    remainingMeters: cumulative.last - progress,
  );
}

/// Great-circle distance (haversine), metres; `shared` may not depend on
/// navigation's helpers.
double _meters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
