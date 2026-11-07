// 無障礙自動檢查（Flutter 內建 guideline）：點擊區域、可點元件有讀屏名稱、文字對比。
// 這不等於讀屏實測；TalkBack／VoiceOver 仍需在實機上操作驗收。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';

Future<void> _open(WidgetTester t, String? entry) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: SafeWalkFlow(key: UniqueKey())));
  await t.pumpAndSettle();
  if (entry == '附近求助地點') {
    // 首頁不再有這個入口；清單畫面仍保留，直接開啟檢查。
    t.widget<SafeWalkHomeView>(find.byType(SafeWalkHomeView)).onOpen(SafeWalkEntry.points);
    await t.pump(const Duration(milliseconds: 500));
  } else if (entry != null) {
    await t.tap(find.text(entry).first);
    await t.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  for (final entry in [null, '安心行', '附近求助地點', '模擬來電', '緊急求助']) {
    final name = entry ?? '首頁';
    testWidgets('$name：點擊區域 ≥ 48、可點元件都有讀屏名稱、文字對比足夠', (t) async {
      final handle = t.ensureSemantics();
      await _open(t, entry);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}
