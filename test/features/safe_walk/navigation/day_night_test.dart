import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/day_night.dart';
import 'package:town_pass/features/safe_walk/navigation/route_preference.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Taipei Main Station area.
const _lat = 25.0330, _lng = 121.5654;

/// First minute at or after [from] where night flips to [toNight].
DateTime _transition(DateTime from, {required bool toNight}) {
  var t = from;
  for (var i = 0; i < 24 * 60; i++) {
    if (isNightAt(t, _lat, _lng) == toNight) return t;
    t = t.add(const Duration(minutes: 1));
  }
  fail('no transition found');
}

void main() {
  // Reference values from the independent sunrise-sunset.org API (UTC),
  // fetched for these coordinates: sunrise/sunset on the dates below.
  final cases = {
    'winter 2026-12-21': (
      sunrise: DateTime.utc(2026, 12, 20, 22, 34, 9),
      sunset: DateTime.utc(2026, 12, 21, 9, 9, 6),
    ),
    'summer 2026-06-21': (
      sunrise: DateTime.utc(2026, 6, 20, 21, 4, 36),
      sunset: DateTime.utc(2026, 6, 21, 10, 46, 22),
    ),
  };

  for (final MapEntry(:key, :value) in cases.entries) {
    test('Taipei $key: sunrise and sunset within 3 minutes', () {
      const tolerance = Duration(minutes: 3);
      final rise = _transition(
        value.sunrise.subtract(const Duration(hours: 1)),
        toNight: false,
      );
      final set = _transition(
        value.sunset.subtract(const Duration(hours: 1)),
        toNight: true,
      );
      expect(
        rise.difference(value.sunrise).abs(),
        lessThanOrEqualTo(tolerance),
      );
      expect(set.difference(value.sunset).abs(), lessThanOrEqualTo(tolerance));
      expect(
        isNightAt(
          value.sunrise.subtract(const Duration(minutes: 6)),
          _lat,
          _lng,
        ),
        isTrue,
      );
      expect(
        isNightAt(value.sunrise.add(const Duration(minutes: 6)), _lat, _lng),
        isFalse,
      );
      expect(
        isNightAt(
          value.sunset.subtract(const Duration(minutes: 6)),
          _lat,
          _lng,
        ),
        isFalse,
      );
      expect(
        isNightAt(value.sunset.add(const Duration(minutes: 6)), _lat, _lng),
        isTrue,
      );
    });
  }

  test('local time zone of the input does not matter', () {
    final utc = DateTime.utc(2026, 12, 21, 14);
    expect(isNightAt(utc, _lat, _lng), isTrue);
    expect(isNightAt(utc.toLocal(), _lat, _lng), isTrue);
  });

  test('polar day and night and invalid input do not crash', () {
    // Tromso: midnight sun in June, polar night in December.
    expect(isNightAt(DateTime.utc(2026, 6, 21, 22), 69.65, 18.96), isFalse);
    expect(isNightAt(DateTime.utc(2026, 12, 21, 11), 69.65, 18.96), isTrue);
    expect(isNightAt(DateTime.utc(2026, 6, 21), double.nan, 0), isFalse);
    expect(isNightAt(DateTime.utc(2026, 6, 21), 95, 0), isFalse);
  });

  test('preference follows the start position and the clock', () {
    final origin = sw.Coordinates(lat: _lat, lng: _lng);
    expect(
      routePreferenceAt(origin, DateTime.utc(2026, 12, 21, 4)),
      RoutePreferenceKind.shade,
    );
    expect(
      routePreferenceAt(origin, DateTime.utc(2026, 12, 21, 14)),
      RoutePreferenceKind.lit,
    );
  });
}
