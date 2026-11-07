import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

enum FollowStatus {
  /// Within the allowed distance of the route.
  onRoute,

  /// Farther from the route than the GPS error can explain. See
  /// [FollowUpdate.shouldReroute].
  offRoute,

  /// Within the arrival radius of the destination. Stays set until [RouteFollower.reset].
  arrived,

  /// The fix was not used (stale, inaccurate, or otherwise invalid); the
  /// other fields repeat the last accepted update.
  positionRejected,
}

/// Where the user is on a route. All distances are metres.
final class FollowUpdate {
  const FollowUpdate({
    required this.status,
    required this.snapped,
    required this.cameraCenter,
    required this.distanceFromRouteMeters,
    required this.distanceAlongMeters,
    required this.remainingMeters,
    required this.remainingSeconds,
    required this.bearingDegrees,
    required this.progress,
    required this.rejectedReason,
  });

  final FollowStatus status;

  /// The nearest point on the route to the user.
  final sw.Coordinates snapped;

  /// Where a map should centre: the user's real position, not the snapped
  /// point, so a wrong route is never drawn as if the user were on it.
  final sw.Coordinates cameraCenter;

  /// Straight-line distance from the user to [snapped].
  final double distanceFromRouteMeters;
  final double distanceAlongMeters;
  final double remainingMeters;

  /// The route's duration scaled by the share of distance left, or null when
  /// the provider gave no duration. An estimate, not a promise.
  final double? remainingSeconds;

  /// Direction of travel along the route at [snapped], degrees clockwise
  /// from north in [0, 360). Use it for a heading-up camera.
  final double bearingDegrees;

  /// 0 at the start, 1 at the end.
  final double progress;

  /// Why the fix was ignored; only set for [FollowStatus.positionRejected].
  final String? rejectedReason;

  /// True when the user left the route and a new `planRoute()` is needed.
  bool get shouldReroute => status == FollowStatus.offRoute;
}

/// Tracks a user along one walking route from positions M1 provides.
///
/// This class never reads GPS or starts a listener: M1 owns location, starts
/// it only after an explicit user action and stops it when navigation ends.
/// Feed each fix to [update] or pass M1's stream to [follow]. It is pure and
/// does no I/O, logging or storage of positions beyond the last progress.
///
/// Forward progress is preferred: when the route overlaps itself (an
/// out-and-back, a loop), a fix that fits several legs is matched to the one
/// ahead of where the user already got to, so progress does not jump back.
final class RouteFollower {
  RouteFollower(
    this.route, {
    this.offRouteMeters = 40,
    this.arrivalMeters = 30,
    this.maxAccuracyMeters = 100,
    this.backtrackToleranceMeters = 50,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    final line = route.geometry.coordinates;
    if (line.length < 2) {
      throw ArgumentError('A route needs at least two coordinates');
    }
    _points = [for (final c in line) fromGeoJson(c)];
    var total = 0.0;
    _cumulative.add(0);
    for (var i = 1; i < _points.length; i++) {
      final length = distanceMeters(_points[i - 1], _points[i]);
      _segmentLengths.add(length);
      total += length;
      _cumulative.add(total);
    }
    _totalMeters = total;
    if (_totalMeters <= 0) {
      throw ArgumentError('A route needs a length greater than zero');
    }
  }

  final sw.RouteCandidate route;

  /// A fix this far from the route is off route, unless the GPS error is
  /// larger: then twice the fix's accuracy is the limit instead.
  final double offRouteMeters;
  final double arrivalMeters;

  /// Fixes with a worse accuracy than this are ignored.
  final double maxAccuracyMeters;
  final double backtrackToleranceMeters;
  final DateTime Function() _clock;

  late final List<sw.Coordinates> _points;
  final List<double> _segmentLengths = [];
  final List<double> _cumulative = [];
  late final double _totalMeters;

  double _lastAlong = 0;
  FollowUpdate? _last;
  bool _arrived = false;

  double get totalMeters => _totalMeters;

  /// Forget progress, e.g. to start the same route again.
  void reset() {
    _lastAlong = 0;
    _last = null;
    _arrived = false;
  }

  /// One update per fix from M1, in order.
  Stream<FollowUpdate> follow(Stream<sw.Position> positions) =>
      positions.map(update);

  FollowUpdate update(sw.Position position) {
    final problems = positionProblems(position, now: _clock());
    if (problems.isNotEmpty) {
      return _rejected(position, problems.join('；'));
    }
    final accuracy = position.accuracyMeters;
    if (accuracy != null && accuracy > maxAccuracyMeters) {
      return _rejected(position, 'GPS 精度太差（約 ${accuracy.round()} 公尺）');
    }

    final here = position.coordinates;
    final match = _match(here);
    final remaining = math.max(0.0, _totalMeters - match.along);
    final toEnd = distanceMeters(here, _points.last);
    final limit = math.max(offRouteMeters, 2 * (accuracy ?? 0));
    if (toEnd <= arrivalMeters) _arrived = true;

    final status = _arrived
        ? FollowStatus.arrived
        : match.crossTrack > limit
        ? FollowStatus.offRoute
        : FollowStatus.onRoute;
    // Progress only moves forward on the route while the user is on it; an
    // off-route fix must not drag the progress to a far-away leg.
    if (status == FollowStatus.onRoute) _lastAlong = match.along;

    final duration = route.durationSeconds;
    final update = FollowUpdate(
      status: status,
      snapped: match.point,
      cameraCenter: here,
      distanceFromRouteMeters: match.crossTrack,
      distanceAlongMeters: match.along,
      remainingMeters: remaining,
      remainingSeconds: duration == null
          ? null
          : duration * remaining / _totalMeters,
      bearingDegrees: match.bearing,
      progress: (match.along / _totalMeters).clamp(0.0, 1.0),
      rejectedReason: null,
    );
    return _last = update;
  }

  FollowUpdate _rejected(sw.Position position, String reason) {
    final last = _last;
    return FollowUpdate(
      status: FollowStatus.positionRejected,
      snapped: last?.snapped ?? _points.first,
      cameraCenter: last?.cameraCenter ?? _points.first,
      distanceFromRouteMeters: last?.distanceFromRouteMeters ?? 0,
      distanceAlongMeters: last?.distanceAlongMeters ?? 0,
      remainingMeters: last?.remainingMeters ?? _totalMeters,
      remainingSeconds: last == null
          ? route.durationSeconds
          : last.remainingSeconds,
      bearingDegrees: last?.bearingDegrees ?? _bearing(0),
      progress: last?.progress ?? 0,
      rejectedReason: reason,
    );
  }

  _Match _match(sw.Coordinates here) {
    _Match? best;
    var bestScore = double.infinity;
    for (var i = 0; i < _segmentLengths.length; i++) {
      if (_segmentLengths[i] <= 0) continue;
      final candidate = _project(here, i);
      // Prefer not to jump back along the route: a leg far behind the
      // progress already made only wins if it is clearly closer.
      final behind = candidate.along < _lastAlong - backtrackToleranceMeters;
      final score = candidate.crossTrack + (behind ? 50 : 0);
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best!;
  }

  _Match _project(sw.Coordinates p, int i) {
    final a = _points[i];
    final b = _points[i + 1];
    // Local flat projection in metres around A; fine over a street segment.
    final metersPerDegLat = earthRadiusMeters * math.pi / 180;
    final metersPerDegLng = metersPerDegLat * math.cos(a.lat * math.pi / 180);
    final bx = (b.lng - a.lng) * metersPerDegLng;
    final by = (b.lat - a.lat) * metersPerDegLat;
    final px = (p.lng - a.lng) * metersPerDegLng;
    final py = (p.lat - a.lat) * metersPerDegLat;
    final lengthSquared = bx * bx + by * by;
    final t = lengthSquared == 0
        ? 0.0
        : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
    final point = sw.Coordinates(
      lat: a.lat + (b.lat - a.lat) * t,
      lng: a.lng + (b.lng - a.lng) * t,
    );
    return _Match(
      point: point,
      crossTrack: distanceMeters(p, point),
      along: _cumulative[i] + _segmentLengths[i] * t,
      bearing: _bearing(i),
    );
  }

  double _bearing(int segment) {
    final a = _points[segment];
    final b = _points[segment + 1];
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

final class _Match {
  const _Match({
    required this.point,
    required this.crossTrack,
    required this.along,
    required this.bearing,
  });

  final sw.Coordinates point;
  final double crossTrack;
  final double along;
  final double bearing;
}
