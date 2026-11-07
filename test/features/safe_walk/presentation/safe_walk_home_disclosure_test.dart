import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';

void main() {
  testWidgets('首頁以小字與主卡讀屏揭露示範資料，不放回 Mock 標籤', (t) async {
    final semantics = t.ensureSemantics();
    try {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: SafeWalkHomeView(
            onOpen: (_) {},
            onEmergency: () {},
            avoided: 2,
          ),
        ),
      );
      await t.pumpAndSettle();
      final disclosure = find.text('目前為示範資料，未連線真實服務');
      await t.ensureVisible(disclosure);
      expect(disclosure, findsOneWidget);
      final card = find.bySemanticsLabel(RegExp(r'^示範：安心行，'));
      expect(card, findsOneWidget);
      expect(t.getSemantics(card).label, startsWith('示範：安心行，'));
      expect(find.text('示範模式（Mock）'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
