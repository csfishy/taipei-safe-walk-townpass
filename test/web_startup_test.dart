@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/account/account_view_controller.dart';
import 'package:town_pass/service/account_service.dart';
import 'package:town_pass/service/device_service.dart';
import 'package:town_pass/service/notification_service.dart';
import 'package:town_pass/service/package_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const deviceChannel = MethodChannel('dev.fluttercommunity.plus/device_info');
  final deviceCalls = <String>[];
  setUp(() {
    deviceCalls.clear();
    // Flutter web unit tests do not auto-register app plugins. Stub only the
    // device plugin boundary; exercise the real browser guards in the service.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(deviceChannel, (call) async {
      deviceCalls.add(call.method);
      return <String, dynamic>{'userAgent': 'Chrome test', 'languages': <String>['zh-TW']};
    });
  });
  tearDown(() => Get.reset());

  test('browser startup avoids native device and notification APIs', () async {
    final device = await DeviceService().init();
    expect(device.baseDeviceInfo, isNotNull);
    expect(device.androidDeviceInfo, isNull);
    expect(device.iosDeviceInfo, isNull);
    expect(deviceCalls, ['getDeviceInfo']);
    await NotificationService().init();
    await NotificationService.requestPermission();
    await expectLater(
      NotificationService.showNotification(title: 'test'),
      throwsUnsupportedError,
    );
  });

  test('account feedback can be composed in a browser without sending it', () {
    Get.put(AccountService());
    Get.put(DeviceService());
    Get.put(PackageService());
    final query = AccountViewController().mailQuery();
    expect(Uri.splitQueryString(query)['subject'], '城市通相關事宜');
    expect(Uri.splitQueryString(query)['body'], contains('APP版本：'));
  });
}
