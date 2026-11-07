import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget_controller.dart';
import 'package:town_pass/page/city_service_edit/city_service_edit_view_controller.dart';
import 'package:town_pass/util/tp_route.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  test(
    'Safe Walk has one service entry in both the default and edit lists',
    () {
      final item = MyServiceItemId.safeWalk.item;
      final pinned = PinnedServiceWidgetController();
      final catalog = CityServiceEditViewController();

      expect(item.title, '臺北安心行');
      expect(item.category, MyServiceCategory.cityService);
      expect(
        MyServiceItemId.values.where((id) => id.item.title == item.title),
        [MyServiceItemId.safeWalk],
      );
      expect(pinned.pinnedList.where((id) => id == MyServiceItemId.safeWalk), [
        MyServiceItemId.safeWalk,
      ]);
      expect(
        catalog.categoryMap[MyServiceCategory.cityService],
        contains(MyServiceItemId.safeWalk),
      );
    },
  );

  test('the official local URI contract uses the host, not a path', () {
    final uri = Uri.parse(MyServiceItemId.safeWalk.item.destinationUrl);

    expect(uri.scheme, 'local');
    expect(uri.host, 'safe_walk');
    expect(uri.path, isEmpty);
    expect('/${uri.host}', TPRoute.safeWalk);
    expect(Uri.parse('local:///safe_walk').host, isEmpty);
  });

  test('the native named route builds the M1 composition root', () {
    final registrations = TPRoute.page.where(
      (page) => page.name == TPRoute.safeWalk,
    );

    expect(registrations, hasLength(1));
    // Constructing the widget does not mount it or request native capabilities.
    expect(registrations.single.page(), isA<SafeWalkCompositionRoot>());
  });

  testWidgets('the visible default service opens the native route', (
    tester,
  ) async {
    Get.put(PinnedServiceWidgetController());
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: PinnedServiceWidget()),
        getPages: [
          GetPage(
            name: TPRoute.safeWalk,
            page: () => const Scaffold(body: Text('safe-walk-native-target')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('臺北安心行'), findsOneWidget);
    await tester.tap(find.text('臺北安心行'));
    await tester.pumpAndSettle();

    expect(find.text('safe-walk-native-target'), findsOneWidget);
    // openUri forwards the URI host. GetX normalizes it while resolving pages.
    expect(
      Get.routeTree.matchRoute(Get.currentRoute).route?.name,
      TPRoute.safeWalk,
    );
    expect(tester.takeException(), isNull);
  });
}
