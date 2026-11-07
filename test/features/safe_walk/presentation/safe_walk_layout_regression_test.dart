import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';

void main() {
  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('390x844 home shows the mock disclosure before any scrolling', (
    tester,
  ) async {
    await open(
      tester,
      SafeWalkHomeView(
        onOpen: (_) {},
        onEmergency: () {},
        homeMinutes: 3,
        avoided: 2,
        now: DateTime(2026, 11, 7, 20),
      ),
    );

    expect(
      find.text('示範模式（Mock）').hitTestable(),
      findsOneWidget,
      reason: 'The demo disclosure must be visible before entering a feature.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('many saved places remain scrollable above the keyboard', (
    tester,
  ) async {
    final places = [
      const SavedPlace('home', '家', DemoGeo.home),
      for (var i = 0; i < 6; i++)
        SavedPlace('place-$i', '常用地點$i', DemoGeo.home),
    ];
    await open(
      tester,
      SafeWalkMapView(
        position: null,
        pointsState: const PointsState(),
        anomalies: [],
        onAnomaliesChanged: () {},
        onBack: () {},
        onCall: () {},
        onEmergency: () {},
        places: places,
        placeId: 'home',
        onSelectPlace: (_) {},
        onAddPlace: (_, _) {},
        onDeletePlace: (_) {},
      ),
    );
    await tester.tap(find.textContaining('→ 家'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增地點'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '學校');
    await tester.pumpAndSettle();
    final confirm = find.text('在地圖上選位置');
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    expect(confirm.hitTestable(), findsOneWidget);
    await tester.tap(confirm);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('新增「學校」'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
