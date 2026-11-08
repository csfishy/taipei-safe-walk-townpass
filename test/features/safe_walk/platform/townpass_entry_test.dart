import 'package:carousel_slider/carousel_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:town_pass/bean/activity.dart';
import 'package:town_pass/bean/home_banner.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_emergency_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget_controller.dart';
import 'package:town_pass/page/city_service_edit/city_service_edit_view_controller.dart';
import 'package:town_pass/page/home/home_view.dart';
import 'package:town_pass/page/home/widget/activity_info/activity_banner_widget_controller.dart';
import 'package:town_pass/page/home/widget/news/news_banner_widget.dart';
import 'package:town_pass/page/home/widget/news/news_banner_widget_controller.dart';
import 'package:town_pass/service/subscription_service.dart';
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
    // The official entry is Live and turns on the phone dialer (the person's own
    // tap opens it; nothing is dialled by the app) and TownPass's own online
    // reporting service.
    final root = registrations.single.page() as SafeWalkCompositionRoot;
    expect(root.liveRoutes, isTrue);
    expect(root.allowEmergencyDialer, isTrue);
    expect(root.onOpenOfficialReport, isNotNull);
    // Tests carry no Supabase configuration, so nearby notification is absent
    // (shown as unavailable) rather than half-configured.
    expect(root.nearbyAlerts, isNull);
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

  testWidgets(
    'the official emergency page offers the dialer and online reporting',
    (tester) async {
      await _homeApp(tester);
      final item = MyServiceItemId.safeWalk.item;
      await tester.tap(
        find.ancestor(
          of: find.text(item.title),
          matching: find.byType(ListTile),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('緊急求助').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final view = tester.widget<SafeWalkEmergencyView>(
        find.byType(SafeWalkEmergencyView),
      );
      expect(view.allowRealCalls, isTrue);
      expect(view.onOfficialReport, isNotNull);
      expect(find.text('線上報案（臺北通）', skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining('按下後由手機開啟撥號，不代表已接通或已受理', skipOffstage: false),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'the homepage card precedes news and opens the real Safe Walk flow',
    (tester) async {
      await _homeApp(tester);
      final item = MyServiceItemId.safeWalk.item;
      final entry = find.ancestor(
        of: find.text(item.title),
        matching: find.byType(ListTile),
      );

      expect(entry, findsOneWidget);
      expect(find.text(item.description), findsOneWidget);
      expect(
        tester.getBottomLeft(entry).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(NewsBannerWidget)).dy),
      );
      expect(find.byType(SafeWalkCompositionRoot), findsNothing);

      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SafeWalkCompositionRoot), findsOneWidget);
      expect(find.byType(SafeWalkFlow), findsOneWidget);
      expect(
        Get.routeTree.matchRoute(Get.currentRoute).route?.name,
        TPRoute.safeWalk,
      );
      final flow = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      // Deliberate (was false): the official entry hands 110/119 to the phone.
      expect(flow.allowRealCalls, isTrue);
      expect(flow.onOfficialReport, isNotNull);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SafeWalkCompositionRoot), findsNothing);
      expect(find.byType(HomeView), findsOneWidget);
      expect(find.text(item.title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'the homepage card stays visible and tappable at 320px with large text',
    (tester) async {
      await _homeApp(
        tester,
        width: 320,
        height: 400,
        textScale: 2,
        useRealRoute: false,
      );
      final item = MyServiceItemId.safeWalk.item;
      final entry = find.ancestor(
        of: find.text(item.title),
        matching: find.byType(ListTile),
      );
      final bounds = tester.getRect(entry);

      expect(entry, findsOneWidget);
      expect(find.text(item.description), findsOneWidget);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.bottom, lessThan(400));
      expect(tester.takeException(), isNull);

      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('safe-walk-large-text-target'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<void> _homeApp(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool useRealRoute = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.put<NewsBannerWidgetController>(_NewsWithoutTimer());
  Get.put<ActivityBannerWidgetController>(_ActivityWithoutTimer());
  Get.put(SubscriptionService()..addSubscription(title: '測試訂閱'));
  await tester.pumpWidget(
    GetMaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const HomeView(),
      getPages: [
        useRealRoute
            ? TPRoute.page.singleWhere((page) => page.name == TPRoute.safeWalk)
            : GetPage(
                name: TPRoute.safeWalk,
                page: () =>
                    const Scaffold(body: Text('safe-walk-large-text-target')),
              ),
      ],
    ),
  );
  // Home's loading placeholders animate continuously. Pump a finite frame;
  // neither test needs to initialize the official app or load remote banners.
  await tester.pump();
}

class _NewsWithoutTimer extends GetxController
    implements NewsBannerWidgetController {
  @override
  final controller = CarouselSliderController();

  @override
  int carouselIndex = 0;

  @override
  bool isLoading = true;

  @override
  HomeBannerList? list;
}

class _ActivityWithoutTimer extends GetxController
    implements ActivityBannerWidgetController {
  @override
  bool isLoading = true;

  @override
  ActivityList? list;
}
