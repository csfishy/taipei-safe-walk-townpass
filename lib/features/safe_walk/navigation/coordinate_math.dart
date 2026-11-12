import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Mean Earth radius used for great-circle distances (metres).
const double earthRadiusMeters = 6371008.8;

/// Pure coordinate helpers. Named coordinates are lat/lng; GeoJSON is
/// `[longitude, latitude]`. Conversions live here so the order is never
/// swapped by hand elsewhere.
bool isValidLatLng(double lat, double lng) =>
    lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

sw.GeoJsonCoordinate toGeoJson(sw.Coordinates coordinates) =>
    (longitude: coordinates.lng, latitude: coordinates.lat);

sw.Coordinates fromGeoJson(sw.GeoJsonCoordinate coordinate) =>
    sw.Coordinates(lat: coordinate.latitude, lng: coordinate.longitude);

/// Great-circle (haversine) distance in metres. This is a straight-line
/// distance, not walking distance.
double distanceMeters(sw.Coordinates a, sw.Coordinates b) =>
    _haversine(a.lat, a.lng, b.lat, b.lng);

double geoJsonDistanceMeters(sw.GeoJsonCoordinate a, sw.GeoJsonCoordinate b) =>
    _haversine(a.latitude, a.longitude, b.latitude, b.longitude);

/// Sum of the great-circle segments; 0 for fewer than two points.
double polylineLengthMeters(List<sw.GeoJsonCoordinate> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += geoJsonDistanceMeters(points[i - 1], points[i]);
  }
  return total;
}

/// Local equirectangular projection onto a walking-scale segment, followed
/// by great-circle distance. Shared by offline snapping and circular avoidance.
({sw.Coordinates point, double fraction, double distance}) projectToSegment(
  sw.Coordinates p,
  sw.Coordinates a,
  sw.Coordinates b,
) {
  final result = projectToGeoJsonSegment(
    toGeoJson(p),
    toGeoJson(a),
    toGeoJson(b),
  );
  return (
    point: fromGeoJson(result.point),
    fraction: result.fraction,
    distance: result.distance,
  );
}

/// Geometry-only variant for hot graph loops. Avoids re-validating the JSON
/// Schema for millions of temporary Coordinates while using identical math.
({sw.GeoJsonCoordinate point, double fraction, double distance})
projectToGeoJsonSegment(
  sw.GeoJsonCoordinate p,
  sw.GeoJsonCoordinate a,
  sw.GeoJsonCoordinate b,
) {
  final k = math.cos(p.latitude * math.pi / 180);
  final ax = (a.longitude - p.longitude) * k, ay = a.latitude - p.latitude;
  final dx = (b.longitude - a.longitude) * k, dy = b.latitude - a.latitude;
  final squared = dx * dx + dy * dy;
  final t = squared == 0
      ? 0.0
      : (-(ax * dx + ay * dy) / squared).clamp(0.0, 1.0);
  final point = (
    latitude: a.latitude + t * (b.latitude - a.latitude),
    longitude: a.longitude + t * (b.longitude - a.longitude),
  );
  return (point: point, fraction: t, distance: geoJsonDistanceMeters(p, point));
}

double _haversine(double lat1, double lng1, double lat2, double lng2) {
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1.0, math.sqrt(h)));
}
