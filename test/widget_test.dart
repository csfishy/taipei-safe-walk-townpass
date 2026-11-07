import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/page/app_home_page/app_home_page_controller.dart';
import 'package:town_pass/page/app_home_page/app_home_page_view.dart';
import 'package:town_pass/page/main/main_view_controller.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

void main() {
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesService().init();
  });

  tearDown(() => Get.reset());

  test('first launch opens Home', () {
    expect(MainViewController().currentIndex.value, 1);
  });

  test('saved start page survives a new controller', () async {
    await SharedPreferencesService().instance.setInt('home_index', 3);
    expect(MainViewController().currentIndex.value, 3);
  });

  testWidgets('choosing a start page persists the actual preference', (tester) async {
    final controller = Get.put(AppHomePageController());
    await tester.pumpWidget(const GetMaterialApp(home: AppHomePageView()));
    expect(find.text('首頁偏好設定'), findsOneWidget);
    await tester.tap(find.text('帳務'));
    await tester.pump();
    expect(controller.currentIndex.value, 3);
    expect(SharedPreferencesService().instance.getInt('home_index'), 3);
    expect(MainViewController().currentIndex.value, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
