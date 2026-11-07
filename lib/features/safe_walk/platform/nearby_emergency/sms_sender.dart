import 'package:flutter/services.dart';

/// What the platform reported for one SMS attempt. None of these values means
/// the message was delivered: Android only confirms the hand-off to SmsManager.
enum SmsHandoffStatus {
  /// SmsManager accepted the message. Sent and delivery are not confirmed.
  handedToSystem,

  /// SEND_SMS was missing. The permission was requested and nothing was sent.
  permissionRequested,

  /// The platform rejected the request or threw. Nothing was sent.
  failed,

  /// This platform cannot send SMS silently (or the channel is missing).
  unavailable,
}

/// Sends a text message without opening the user's messaging app.
abstract interface class SmsSender {
  Future<SmsHandoffStatus> send({required String number, required String body});
}

/// Android: native SmsManager through the `safe_walk/sms` channel (MainActivity.kt).
/// Other platforms return [SmsHandoffStatus.unavailable], because they cannot
/// send SMS silently.
final class ChannelSmsSender implements SmsSender {
  static const _channel = MethodChannel('safe_walk/sms');

  @override
  Future<SmsHandoffStatus> send({
    required String number,
    required String body,
  }) async {
    try {
      final code = await _channel.invokeMethod<String>('send', {
        'number': number,
        'body': body,
      });
      return switch (code) {
        'handed' => SmsHandoffStatus.handedToSystem,
        'no_permission' => SmsHandoffStatus.permissionRequested,
        _ => SmsHandoffStatus.failed,
      };
    } on MissingPluginException {
      return SmsHandoffStatus.unavailable;
    } on PlatformException {
      return SmsHandoffStatus.failed;
    }
  }
}
