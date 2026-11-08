import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('首頁不捲動，家的設定不在首頁而在安心行設定', (t) async {
    await _pump(
      t,
      SafeWalkFlow(
        homeLocation: sw.Coordinates(lat: 0.5, lng: 0.5),
        onHomeChanged: (_) async {},
      ),
    );
    expect(find.byType(Scrollable), findsNothing);
    expect(find.text('編輯「家」'), findsNothing);
    expect(find.text('設定「家」'), findsNothing);
    // 安心行主卡在模擬來電上方，SOS 仍在最底。
    final card = t.getTopLeft(find.text('點擊開始')).dy;
    final call = t.getTopLeft(find.text('模擬來電')).dy;
    final sos = t.getTopLeft(find.text('緊急求助')).dy;
    expect(card, lessThan(call));
    expect(call, lessThan(sos));

    await t.tap(find.byTooltip('安心行設定'));
    await t.pumpAndSettle();
    expect(find.text('安心行設定'), findsOneWidget);
    expect(find.text('編輯「家」'), findsOneWidget);

    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();
    expect(find.text('點擊開始'), findsOneWidget);
  });

  testWidgets('沒有可設定的項目時，設定頁說明而不是空白', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.byTooltip('安心行設定'));
    await t.pumpAndSettle();
    expect(find.text('目前沒有可調整的設定。'), findsOneWidget);
  });
}
