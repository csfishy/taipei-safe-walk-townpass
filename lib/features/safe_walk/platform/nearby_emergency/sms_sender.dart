import 'package:flutter/services.dart';

/// Requests a text message without opening the user's messaging app.
abstract interface class SmsSender {
  /// True only when the platform accepted the submission request.
  /// This does not confirm that the message was sent or delivered.
  Future<bool> send({required String number, required String body});
}

/// Android: native SmsManager through the `safe_walk/sms` channel (MainActivity.kt).
/// Other platforms return false, because they cannot send SMS silently.
final class ChannelSmsSender implements SmsSender {
  static const _channel = MethodChannel('safe_walk/sms');

  @override
  Future<bool> send({required String number, required String body}) async {
    final destination = number.trim();
    if (destination.isEmpty || body.trim().isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<Object?>('send', {
        'number': destination,
        'body': body,
      });
      // Malformed or absent native responses cannot establish submission.
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
