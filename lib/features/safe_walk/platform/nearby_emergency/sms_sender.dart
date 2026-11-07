import 'package:flutter/services.dart';

/// Submission outcomes only. No value confirms sending or delivery.
enum SmsHandoffStatus {
  /// The native submission call returned without a synchronous exception.
  handedToSystem,

  /// SMS permission was missing; this attempt did not submit a message.
  /// The OS may require a new permission decision or a change in Settings.
  permissionRequired,

  /// The recipient or body was rejected before native submission.
  invalidRequest,

  /// No native SMS handler is available on this platform.
  unavailable,

  /// No reliable submission result was received. Side effects are unknown.
  outcomeUnknown,
}

/// Requests a text message without opening the user's messaging app.
abstract interface class SmsSender {
  Future<SmsHandoffStatus> send({required String number, required String body});
}

/// Android: native SmsManager through the `safe_walk/sms` channel (MainActivity.kt).
/// Platforms without this native handler return [SmsHandoffStatus.unavailable].
final class ChannelSmsSender implements SmsSender {
  static const _channel = MethodChannel('safe_walk/sms');

  @override
  Future<SmsHandoffStatus> send({
    required String number,
    required String body,
  }) async {
    final destination = number.trim();
    if (destination.isEmpty || body.trim().isEmpty) {
      return SmsHandoffStatus.invalidRequest;
    }
    try {
      final code = await _channel.invokeMethod<Object?>('send', {
        'number': destination,
        'body': body,
      });
      // Old boolean replies, malformed responses and absent responses do not
      // establish an outcome under this typed channel contract.
      return switch (code) {
        'handed' => SmsHandoffStatus.handedToSystem,
        'no_permission' => SmsHandoffStatus.permissionRequired,
        'invalid' => SmsHandoffStatus.invalidRequest,
        'failed' => SmsHandoffStatus.outcomeUnknown,
        _ => SmsHandoffStatus.outcomeUnknown,
      };
    } on MissingPluginException {
      return SmsHandoffStatus.unavailable;
    } on Object {
      // A platform/codec error does not prove that no SMS was submitted.
      return SmsHandoffStatus.outcomeUnknown;
    }
  }
}
