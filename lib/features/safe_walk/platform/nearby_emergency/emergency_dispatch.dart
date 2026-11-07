import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_message.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final class EmergencyDispatchResult {
  const EmergencyDispatchResult({
    required this.message,
    required this.nearbyRecipients,
    required this.smsSent,
    required this.located,
  });

  /// Human-readable summary for the screen.
  final String message;

  /// Null when no nearby alert was attempted.
  final int? nearbyRecipients;
  final bool smsSent;
  final bool located;
}

/// One SOS tap: read location once, notify opted-in nearby helpers, and send
/// the exact location to the preset contact. Each part is reported separately.
final class EmergencyDispatch {
  EmergencyDispatch({
    required this._platform,
    required this._transport,
    required this._sms,
    required this._contacts,
    this.radiusMeters = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PlatformService _platform;
  final NearbyAlertTransport _transport;
  final SmsSender _sms;
  final EmergencyContactStore _contacts;
  final int radiusMeters;
  final DateTime Function() _clock;

  Future<EmergencyDispatchResult> sos({
    required sw.DataMode mode,
    required String senderId,
    SafeWalkCancellation? cancellation,
  }) async {
    if (mode == sw.DataMode.mock) {
      return const EmergencyDispatchResult(
        message: '示範模式不傳送任何訊息。',
        nearbyRecipients: null,
        smsSent: false,
        located: false,
      );
    }

    final sw.LocationResult location;
    try {
      location = await _platform.getCurrentPosition(
        mode: mode,
        userInitiated: true,
        cancellation: cancellation,
      );
    } on SafeWalkCancelledException {
      return const EmergencyDispatchResult(
        message: '已取消，未傳送任何訊息。',
        nearbyRecipients: null,
        smsSent: false,
        located: false,
      );
    }
    if (location is! sw.LocationSuccess) {
      return EmergencyDispatchResult(
        message: '無法取得位置，未傳送任何訊息：${(location as sw.LocationFailure).message}',
        nearbyRecipients: null,
        smsSent: false,
        located: false,
      );
    }

    final coords = location.position.coordinates;
    int? recipients;
    String? nearbyError;
    try {
      recipients = await _transport.sendEmergencyAlert(
        senderId: senderId,
        location: coords,
        radiusMeters: radiusMeters,
      );
    } on Object {
      nearbyError = '附近求助者通知失敗';
    }

    final body = buildEmergencyMessage(
      location: coords,
      sentAt: _clock(),
      accuracyMeters: location.position.accuracyMeters,
    );
    final contact = await _contacts.read();
    bool smsSent = false;
    String smsNote;
    if (contact == null) {
      smsNote = '尚未設定緊急聯絡人，未傳簡訊';
    } else {
      smsSent = await _sms.send(number: contact, body: body);
      smsNote = smsSent ? '已送簡訊給緊急聯絡人' : '簡訊未送出（此裝置無法自動傳送）';
    }

    final nearbyNote = nearbyError ??
        (recipients == null ? '' : '已通知 $recipients 位附近的求助者');
    return EmergencyDispatchResult(
      message: [nearbyNote, smsNote].where((s) => s.isNotEmpty).join('；'),
      nearbyRecipients: recipients,
      smsSent: smsSent,
      located: true,
    );
  }
}
