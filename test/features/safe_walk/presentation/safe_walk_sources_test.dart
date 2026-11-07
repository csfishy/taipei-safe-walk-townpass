// 資料來源與授權：首頁與地圖都找得到入口，說明列出開放資料與授權，並標出示範資料。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(const MaterialApp(home: SafeWalkFlow()));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('首頁：資料來源與授權列出 OSM、政府開放資料授權，不出現示範字樣', (t) async {
    await _pump(t);
    final link = find.text('資料來源與授權');
    await t.ensureVisible(link);
    await t.tap(link);
    await t.pumpAndSettle();
    expect(find.textContaining('OpenStreetMap'), findsWidgets);
    expect(find.textContaining('MIT License'), findsOneWidget, reason: 'Valhalla 路線引擎授權');
    await t.scrollUntilVisible(
      find.textContaining('政府資料開放授權條款'),
      200,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    expect(find.textContaining('政府資料開放授權條款'), findsOneWidget);
    expect(find.textContaining('示範'), findsNothing, reason: '正式畫面不顯示示範字樣');
  });

  testWidgets('資料來源入口只在首頁，地圖資訊框不重複放', (t) async {
    await _pump(t);
    final link = find.text('資料來源與授權');
    await t.ensureVisible(link);
    await t.tap(link);
    await t.pumpAndSettle();
    expect(find.text('步行路線'), findsOneWidget);
    Navigator.of(t.element(find.text('步行路線'))).pop();
    await t.pumpAndSettle();
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    expect(find.text('資料來源與授權'), findsNothing);
  });
}
