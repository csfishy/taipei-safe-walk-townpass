import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Builds the SMS body sent to the preset contact. Coordinates are written
/// exactly, with a Google Maps link. No photos are included.
String buildEmergencyMessage({
  required sw.Coordinates location,
  required DateTime sentAt,
  double? accuracyMeters,
}) {
  final lat = location.lat.toStringAsFixed(6);
  final lng = location.lng.toStringAsFixed(6);
  final local = sentAt.toLocal();
  final time =
      '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
  final accuracy = accuracyMeters == null
      ? ''
      : '（精度約 ${accuracyMeters.round()} 公尺）';
  return '【臺北安心行 緊急求助】我可能需要協助。\n'
      '時間：$time\n'
      '座標：$lat, $lng$accuracy\n'
      '地圖：https://maps.google.com/?q=$lat,$lng';
}

String _two(int value) => value.toString().padLeft(2, '0');
