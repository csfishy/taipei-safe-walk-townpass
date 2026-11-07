// 求助頁的「線上報案（臺北通）」：只在有注入時顯示；點了只是開啟官方服務，
// 文字不聲稱已報案或已受理。沒有網路、沒有真實操作。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';

const _forbidden = ['已報警', '已通報', '已派遣', '警方已', '已受理並', '報案成功'];

Future<void> _openEmergency(
  WidgetTester t,
  VoidCallback? onOfficialReport,
) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: SafeWalkFlow(key: UniqueKey(), onOfficialReport: onOfficialReport),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('緊急求助').first);
  await t.pumpAndSettle();
}

Finder _t(String s) => find.text(s, skipOffstage: false);

void main() {
  testWidgets('without an injected opener the button is not shown', (t) async {
    await _openEmergency(t, null);
    expect(_t('線上報案（臺北通）'), findsNothing);
    expect(_t('撥打 110 報警'), findsOneWidget);
  });

  testWidgets('shown with an opener; tapping opens it exactly once', (t) async {
    var opened = 0;
    await _openEmergency(t, () => opened++);
    expect(_t('線上報案（臺北通）'), findsOneWidget);
    expect(
      find.textContaining('開啟不代表已受理', skipOffstage: false),
      findsOneWidget,
    );
    expect(opened, 0);
    await t.tap(_t('線上報案（臺北通）'));
    await t.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('110 and 119 stay available next to it', (t) async {
    await _openEmergency(t, () {});
    expect(_t('撥打 110 報警'), findsOneWidget);
    expect(_t('撥打 119'), findsOneWidget);
  });

  testWidgets('nothing on the page claims a report or dispatch', (t) async {
    await _openEmergency(t, () {});
    final text = t
        .widgetList<Text>(find.byType(Text, skipOffstage: false))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .join('\n');
    for (final phrase in _forbidden) {
      expect(text, isNot(contains(phrase)), reason: phrase);
    }
  });

  testWidgets('the button meets accessibility guidelines', (t) async {
    final handle = t.ensureSemantics();
    await _openEmergency(t, () {});
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
