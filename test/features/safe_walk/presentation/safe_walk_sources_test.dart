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
  testWidgets('首頁：資料來源與授權列出 OSM、政府開放資料授權，並標示示範項目', (t) async {
    await _pump(t);
    final link = find.text('資料來源與授權');
    await t.ensureVisible(link);
    await t.tap(link);
    await t.pumpAndSettle();
    expect(find.textContaining('OpenStreetMap'), findsWidgets);
    expect(find.textContaining('政府資料開放授權條款'), findsOneWidget);
    await t.scrollUntilVisible(find.text('示範資料（非真實機關）'), 200, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    await t.pumpAndSettle();
    expect(find.text('示範'), findsWidgets, reason: '示範資料要標出來');
  });

  testWidgets('地圖路線資訊框也有資料來源入口', (t) async {
    await _pump(t);
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    final link = find.text('資料來源與授權');
    await t.ensureVisible(link);
    await t.tap(link);
    await t.pumpAndSettle();
    expect(find.text('步行路線'), findsOneWidget);
  });
}
