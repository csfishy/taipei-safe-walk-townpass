import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/google_maps_link.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  final store = sw.Coordinates(lat: 25.0485, lng: 121.5175);

  group('googleMapsWalkingUri', () {
    test('is a Google Maps directions link for walking with navigation', () {
      final uri = googleMapsWalkingUri(destination: store);

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters, {
        'api': '1',
        'destination': '25.048500,121.517500',
        'travelmode': 'walking',
        'dir_action': 'navigate',
      });
    });

    test('has no origin by default, so it never carries the user location', () {
      final uri = googleMapsWalkingUri(destination: store);

      expect(uri.queryParameters.containsKey('origin'), isFalse);
      expect(uri.toString(), isNot(contains('origin')));
    });

    test('puts latitude before longitude, as Google expects', () {
      final uri = googleMapsWalkingUri(destination: store);

      final parts = uri.queryParameters['destination']!.split(',');
      expect(double.parse(parts[0]), 25.0485);
      expect(double.parse(parts[1]), 121.5175);
    });

    test('an explicit origin is added', () {
      final uri = googleMapsWalkingUri(
        destination: store,
        origin: sw.Coordinates(lat: 25.0339, lng: 121.5645),
      );

      expect(uri.queryParameters['origin'], '25.033900,121.564500');
    });

    test('navigation can be turned off for a route preview', () {
      final uri = googleMapsWalkingUri(
        destination: store,
        startNavigation: false,
      );

      expect(uri.queryParameters.containsKey('dir_action'), isFalse);
      expect(uri.queryParameters['travelmode'], 'walking');
    });

    test('negative and long coordinates are formatted without exponents', () {
      final uri = googleMapsWalkingUri(
        destination: sw.Coordinates(lat: -33.8568, lng: -0.0000004),
      );

      expect(uri.queryParameters['destination'], '-33.856800,-0.000000');
    });

    test('the string form round-trips through Uri.parse', () {
      final uri = googleMapsWalkingUri(destination: store);

      expect(Uri.parse(uri.toString()), uri);
    });
  });
}
