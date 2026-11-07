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
