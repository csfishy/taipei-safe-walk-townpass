import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:town_pass/bean/message.dart';
import 'package:town_pass/page/basic_info/basic_info_view.dart';
import 'package:town_pass/page/basic_info/basic_info_view_controller.dart';
import 'package:town_pass/page/home/widget/activity_info/activity_banner_widget.dart';
import 'package:town_pass/page/home/widget/news/news_banner_widget.dart';
import 'package:town_pass/page/message/message_view_controller.dart';
import 'package:town_pass/service/account_service.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  test('startup does not create an authenticated sample account', () async {
    final service = await AccountService().init();
    expect(service.account, isNull);
  });

  test('unconfigured messages do not create unread notifications', () async {
    final controller = MessageViewController();
    await controller.fetch();
    for (final type in MessageType.values) {
      expect(controller.messageList(type: type), isEmpty);
      expect(controller.unreadCount(type: type), 0);
    }
    expect(controller.isLoading, isFalse);
  });

  test('editing without an account cannot create a placeholder identity', () {
    final service = Get.put(AccountService());
    final controller = BasicInfoViewController();
    controller.updateAccount(email: 'test@example.invalid');
    expect(service.account, isNull);
  });

  testWidgets('profile editing explains an unconfigured account', (
    tester,
  ) async {
    Get.put(AccountService());
    Get.put(BasicInfoViewController());
    await tester.pumpWidget(const MaterialApp(home: BasicInfoView()));
    expect(find.text('帳戶服務尚未配置，無法查看或編輯個人資料。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured news renders without an empty carousel error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NewsBannerWidget())),
    );
    await tester.pumpAndSettle();
    expect(find.text('最新消息服務尚未配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured activities render without a null list error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActivityBannerWidget())),
    );
    await tester.pumpAndSettle();
    expect(find.text('活動資訊服務尚未配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
