import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Builds the SMS body for the preset contact, with coordinates to six decimals.
/// [sentAt] is the message creation time, not a sending or delivery receipt.
/// No external map URL or photo is included.
String buildEmergencyMessage({
  required sw.Coordinates location,
  required DateTime sentAt,
  double? accuracyMeters,
}) {
  final lat = location.lat.toStringAsFixed(6);
  final lng = location.lng.toStringAsFixed(6);
  final utc = sentAt.toUtc();
  final time =
      '${utc.year}-${_two(utc.month)}-${_two(utc.day)} '
      '${_two(utc.hour)}:${_two(utc.minute)} UTC';
  final accuracy =
      accuracyMeters != null && accuracyMeters.isFinite && accuracyMeters >= 0
      ? '定位精度約 ${accuracyMeters.round()} 公尺'
      : '定位精度未提供';
  return '【臺北安心行 緊急求助】我可能需要協助。\n'
      '訊息建立時間：$time\n'
      '座標：$lat, $lng（$accuracy）\n'
      '請直接聯絡我確認情況；此訊息不代表警方或救護單位已受理。';
}

String _two(int value) => value.toString().padLeft(2, '0');
