import 'package:flutter/services.dart';

/// Sends a text message without opening the user's messaging app.
abstract interface class SmsSender {
  /// True only when the platform accepted the message for sending.
  Future<bool> send({required String number, required String body});
}

/// Android: native SmsManager through the `safe_walk/sms` channel (MainActivity.kt).
/// Other platforms return false, because they cannot send SMS silently.
final class ChannelSmsSender implements SmsSender {
  static const _channel = MethodChannel('safe_walk/sms');

  @override
  Future<bool> send({required String number, required String body}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('send', {
        'number': number,
        'body': body,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
