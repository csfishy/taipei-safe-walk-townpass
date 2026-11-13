import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_models.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const reportPickRadiusMeters = 500.0;
const reportDetailRadiusMeters = 100.0;
const reportGpsAccuracyMeters = 30.0;

/// A real, recent GPS fix is required; a manually picked route origin is not GPS.
LatLng? reportGpsCenter(sw.Position? position, {DateTime? now}) {
  if (position == null ||
      position.source != sw.PositionSource.gps ||
      position.accuracyMeters == null ||
      !position.accuracyMeters!.isFinite ||
      position.accuracyMeters! < 0 ||
      position.accuracyMeters! > reportGpsAccuracyMeters ||
      positionProblems(position, now: now).isNotEmpty) {
    return null;
  }
  final p = position.coordinates;
  if (!p.lat.isFinite ||
      !p.lng.isFinite ||
      p.lat.abs() > 90 ||
      p.lng.abs() > 180) {
    return null;
  }
  return LatLng(p.lat, p.lng);
}

double reportDistanceMeters(LatLng a, LatLng b) {
  const radians = math.pi / 180;
  final dLat = (b.lat - a.lat) * radians;
  final dLng = (b.lng - a.lng) * radians;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.lat * radians) *
          math.cos(b.lat * radians) *
          math.pow(math.sin(dLng / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
}

bool withinReportRange(LatLng? center, LatLng at, double radius) =>
    center != null &&
    at.lat.isFinite &&
    at.lng.isFinite &&
    at.lat.abs() <= 90 &&
    at.lng.abs() <= 180 &&
    reportDistanceMeters(center, at) <= radius + 0.000001;
