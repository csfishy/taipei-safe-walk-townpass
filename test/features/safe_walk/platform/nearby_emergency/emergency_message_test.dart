import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_message.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  // Artificial offshore coordinates, never a real user's location.
  final location = sw.Coordinates(lat: 0.123456, lng: -0.654321);
  final createdAt = DateTime.parse('2026-11-07T20:30:00+08:00');

  test(
    'labels coordinates, creation time and precision without an external link',
    () {
      final message = buildEmergencyMessage(
        location: location,
        sentAt: createdAt,
        accuracyMeters: 8.4,
      );

      expect(message, contains('座標：0.123456, -0.654321'));
      expect(message, contains('訊息建立時間：2026-11-07 12:30 UTC'));
      expect(message, contains('定位精度約 8 公尺'));
      expect(message, contains('此訊息不代表警方或救護單位已受理'));
      expect(message, isNot(contains('http')));
      expect(message.toLowerCase(), isNot(contains('google')));
      expect(message, isNot(contains('已送達')));
    },
  );

  for (final accuracy in <double?>[null, double.nan, double.infinity, -1]) {
    test('does not invent precision for unavailable accuracy $accuracy', () {
      final message = buildEmergencyMessage(
        location: location,
        sentAt: createdAt,
        accuracyMeters: accuracy,
      );
      expect(message, contains('定位精度未提供'));
      expect(message, isNot(contains('精度約')));
    });
  }
}
