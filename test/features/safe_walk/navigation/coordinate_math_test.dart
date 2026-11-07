import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  group('GeoJSON order', () {
    test('toGeoJson puts longitude first and latitude second', () {
      final geo = toGeoJson(sw.Coordinates(lat: 25.0339, lng: 121.5645));

      expect(geo.longitude, 121.5645);
      expect(geo.latitude, 25.0339);
    });

    test('round trip keeps lat and lng in place', () {
      final back = fromGeoJson(
        toGeoJson(sw.Coordinates(lat: 25.0339, lng: 121.5645)),
      );

      expect(back.lat, 25.0339);
      expect(back.lng, 121.5645);
    });

    test('LineString serializes as [longitude, latitude]', () {
      final line = sw.LineString(
        coordinates: [
          toGeoJson(sw.Coordinates(lat: 25.0, lng: 121.5)),
          toGeoJson(sw.Coordinates(lat: 25.001, lng: 121.501)),
        ],
      );

      expect(line.toJson()['coordinates'], [
        [121.5, 25.0],
        [121.501, 25.001],
      ]);
    });
  });

  group('distanceMeters', () {
    test('is zero for the same point and symmetric', () {
      final a = sw.Coordinates(lat: 25.0339, lng: 121.5645);
      final b = sw.Coordinates(lat: 25.0478, lng: 121.5170);

      expect(distanceMeters(a, a), 0);
      expect(distanceMeters(a, b), closeTo(distanceMeters(b, a), 1e-6));
    });

    test('one degree of latitude is about 111.2 km', () {
      final d = distanceMeters(
        sw.Coordinates(lat: 25, lng: 121.5),
        sw.Coordinates(lat: 26, lng: 121.5),
      );

      expect(d, closeTo(111195, 100));
    });

    test('Taipei 101 to Taipei Main Station is about 5 km', () {
      final d = distanceMeters(
        sw.Coordinates(lat: 25.0339, lng: 121.5645),
        sw.Coordinates(lat: 25.0478, lng: 121.5170),
      );

      expect(d, closeTo(5030, 100));
    });

    test('a degree of longitude is shorter than a degree of latitude here', () {
      final lng = distanceMeters(
        sw.Coordinates(lat: 25, lng: 121),
        sw.Coordinates(lat: 25, lng: 122),
      );

      expect(lng, lessThan(111195));
      expect(lng, closeTo(100780, 200));
    });
  });

  group('polylineLengthMeters', () {
    test('sums the segments', () {
      final a = (longitude: 121.5, latitude: 25.0);
      final b = (longitude: 121.5005, latitude: 25.0004);
      final c = (longitude: 121.501, latitude: 25.001);

      expect(
        polylineLengthMeters([a, b, c]),
        closeTo(
          geoJsonDistanceMeters(a, b) + geoJsonDistanceMeters(b, c),
          1e-6,
        ),
      );
    });

    test('is zero for fewer than two points', () {
      expect(polylineLengthMeters(const []), 0);
      expect(polylineLengthMeters([(longitude: 121.5, latitude: 25.0)]), 0);
    });
  });

  group('isValidLatLng', () {
    test('accepts real coordinates and the extremes', () {
      expect(isValidLatLng(25.0, 121.5), isTrue);
      expect(isValidLatLng(90, 180), isTrue);
      expect(isValidLatLng(-90, -180), isTrue);
    });

    test('rejects out of range, NaN and infinity', () {
      expect(isValidLatLng(91, 0), isFalse);
      expect(isValidLatLng(0, 181), isFalse);
      expect(isValidLatLng(double.nan, 0), isFalse);
      expect(isValidLatLng(0, double.infinity), isFalse);
    });
  });
}
