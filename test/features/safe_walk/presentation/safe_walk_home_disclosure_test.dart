import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';

void main() {
  // 11/7 使用者決定：正式畫面不出現「示範／Mock／未連線」字樣；改由「資料來源與授權」說明資料來源。
  testWidgets('首頁不出現示範字樣，保留資料來源與授權入口', (t) async {
    final semantics = t.ensureSemantics();
    try {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: SafeWalkHomeView(onOpen: (_) {}, onEmergency: () {}, avoided: 2),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('示範'), findsNothing);
      expect(find.textContaining('Mock'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^安心行，')), findsOneWidget);
      final link = find.text('資料來源與授權');
      await t.ensureVisible(link);
      expect(link, findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
