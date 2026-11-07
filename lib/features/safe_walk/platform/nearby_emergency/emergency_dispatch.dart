import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
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
    required this.smsStatus,
    required this.located,
    this.cancelled = false,
  });

  /// Human-readable summary for the screen.
  final String message;

  /// Null when no nearby alert was confirmed by the backend.
  final int? nearbyRecipients;

  /// Null when no SMS attempt was made (no contact, cancelled, or not located).
  final SmsHandoffStatus? smsStatus;
  final bool located;

  /// True when the user cancelled (leave, background, revoke) before the flow ended.
  final bool cancelled;
}

/// One SOS tap: read location once, notify opted-in nearby helpers, and send
/// the exact location to the preset contact. Each part is reported separately.
///
/// Every external side effect (backend RPC, contact read, SMS) is preceded by a
/// cancellation check. A late location, RPC or contact result after cancellation
/// is discarded and nothing further is sent. An RPC already on the wire cannot be
/// recalled, and the message says so.
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
        smsStatus: null,
        located: false,
      );
    }
    bool cancelled() => cancellation?.isCancelled ?? false;
    EmergencyDispatchResult stopped({
      bool located = false,
      int? recipients,
      bool rpcStarted = false,
    }) {
      final String message;
      if (recipients != null) {
        message = '已取消；附近已通知 $recipients 位，未傳簡訊。';
      } else if (rpcStarted) {
        message = '已取消；附近通知可能已送出，未傳簡訊。';
      } else {
        message = '已取消，未傳送任何訊息。';
      }
      return EmergencyDispatchResult(
        message: message,
        nearbyRecipients: recipients,
        smsStatus: null,
        located: located,
        cancelled: true,
      );
    }

    if (cancelled()) return stopped();

    final sw.LocationResult location;
    try {
      location = await raceCancellation(
        _platform.getCurrentPosition(
          mode: mode,
          userInitiated: true,
          cancellation: cancellation,
        ),
        cancellation,
      );
    } on SafeWalkCancelledException {
      return stopped();
    }
    // A location that arrives after cancellation is dropped, not shared.
    if (cancelled()) return stopped();
    if (location is! sw.LocationSuccess) {
      return EmergencyDispatchResult(
        message: '無法取得位置，未傳送任何訊息：${(location as sw.LocationFailure).message}',
        nearbyRecipients: null,
        smsStatus: null,
        located: false,
      );
    }

    final coords = location.position.coordinates;
    int? recipients;
    String? nearbyError;
    var rpcStarted = false;
    try {
      rpcStarted = true;
      recipients = await raceCancellation(
        _transport.sendEmergencyAlert(
          senderId: senderId,
          location: coords,
          radiusMeters: radiusMeters,
        ),
        cancellation,
      );
    } on SafeWalkCancelledException {
      return stopped(located: true, rpcStarted: true);
    } on Object {
      nearbyError = '附近求助者通知失敗';
    }
    if (cancelled()) {
      return stopped(located: true, recipients: recipients, rpcStarted: rpcStarted);
    }

    final body = buildEmergencyMessage(
      location: coords,
      sentAt: _clock(),
      accuracyMeters: location.position.accuracyMeters,
    );
    final String? contact;
    try {
      contact = await raceCancellation(_contacts.read(), cancellation);
    } on SafeWalkCancelledException {
      return stopped(located: true, recipients: recipients, rpcStarted: rpcStarted);
    }
    if (cancelled()) {
      return stopped(located: true, recipients: recipients, rpcStarted: rpcStarted);
    }

    SmsHandoffStatus? smsStatus;
    String smsNote;
    if (contact == null) {
      smsNote = '尚未設定緊急聯絡人，未傳簡訊';
    } else {
      final status = await _sms.send(number: contact, body: body);
      smsStatus = status;
      smsNote = switch (status) {
        SmsHandoffStatus.handedToSystem => '已交給系統發送簡訊（尚未確認送達）',
        SmsHandoffStatus.permissionRequested =>
          '簡訊權限尚未授權，已要求權限，簡訊未送出；請再按一次 SOS',
        SmsHandoffStatus.failed => '簡訊傳送失敗，請改用電話求助',
        SmsHandoffStatus.unavailable => '此裝置無法自動傳送簡訊，請改用電話求助',
      };
    }

    final nearbyNote = nearbyError ??
        (recipients == null ? '' : '已通知 $recipients 位附近的求助者');
    return EmergencyDispatchResult(
      message: [nearbyNote, smsNote].where((s) => s.isNotEmpty).join('；'),
      nearbyRecipients: recipients,
      smsStatus: smsStatus,
      located: true,
    );
  }
}
