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
    'true records only a native submission request with the given body',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      expect(
        await sender.send(number: ' 0000000000 ', body: 'synthetic test body'),
        isTrue,
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'send');
      expect(calls.single.arguments, {
        'number': '0000000000',
        'body': 'synthetic test body',
      });
    },
  );

  for (final response in <Object?>[
    false,
    null,
    'true',
    1,
    <String, bool>{'sent': true},
  ]) {
    test('does not infer submission from native response $response', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      expect(
        await sender.send(number: '0000000000', body: 'synthetic test body'),
        isFalse,
      );
    });
  }

  test('platform rejection returns false without exposing the error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'denied',
        message: 'synthetic private detail',
      );
    });
    expect(
      await sender.send(number: '0000000000', body: 'synthetic test body'),
      isFalse,
    );
  });

  test('an unsupported platform returns false', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(
      await sender.send(number: '0000000000', body: 'synthetic test body'),
      isFalse,
    );
  });

  test('blank recipients or bodies never invoke the platform', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return true;
    });
    expect(
      await sender.send(number: '  ', body: 'synthetic test body'),
      isFalse,
    );
    expect(await sender.send(number: '0000000000', body: '\n  '), isFalse);
    expect(calls, 0);
  });
}
