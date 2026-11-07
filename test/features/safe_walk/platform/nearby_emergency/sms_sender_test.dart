import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('safe_walk/sms');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final sender = ChannelSmsSender();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'handed records only a native submission request with the given body',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'handed';
      });

      expect(
        await sender.send(number: ' 0000000000 ', body: 'synthetic test body'),
        SmsHandoffStatus.handedToSystem,
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'send');
      expect(calls.single.arguments, {
        'number': '0000000000',
        'body': 'synthetic test body',
      });
    },
  );

  for (final response in {
    'no_permission': SmsHandoffStatus.permissionRequired,
    'invalid': SmsHandoffStatus.invalidRequest,
    'failed': SmsHandoffStatus.outcomeUnknown,
  }.entries) {
    test('maps native ${response.key} without claiming delivery', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => response.key);
      expect(
        await sender.send(number: '0000000000', body: 'synthetic test body'),
        response.value,
      );
    });
  }

  for (final response in <Object?>[
    true,
    false,
    null,
    'true',
    'unexpected-status',
    1,
    <String, bool>{'sent': true},
  ]) {
    test('does not infer submission from native response $response', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      expect(
        await sender.send(number: '0000000000', body: 'synthetic test body'),
        SmsHandoffStatus.outcomeUnknown,
      );
    });
  }

  test(
    'platform error leaves the result unknown without exposing it',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'denied',
          message: 'synthetic private detail',
        );
      });
      expect(
        await sender.send(number: '0000000000', body: 'synthetic test body'),
        SmsHandoffStatus.outcomeUnknown,
      );
    },
  );

  test('a malformed platform envelope leaves the result unknown', () async {
    messenger.setMockMessageHandler(channel.name, (_) async => ByteData(1));
    expect(
      await sender.send(number: '0000000000', body: 'synthetic test body'),
      SmsHandoffStatus.outcomeUnknown,
    );
  });

  test('an unsupported platform reports unavailable', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(
      await sender.send(number: '0000000000', body: 'synthetic test body'),
      SmsHandoffStatus.unavailable,
    );
  });

  test('blank recipients or bodies never invoke the platform', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return 'handed';
    });
    expect(
      await sender.send(number: '  ', body: 'synthetic test body'),
      SmsHandoffStatus.invalidRequest,
    );
    expect(
      await sender.send(number: '0000000000', body: '\n  '),
      SmsHandoffStatus.invalidRequest,
    );
    expect(calls, 0);
  });
}
