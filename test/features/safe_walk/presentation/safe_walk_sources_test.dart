// 資料來源與授權：只在首頁有入口；分組、可展開；只列目前實際使用的來源，並保留限制說明。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_sources.dart';

Future<void> _pump(WidgetTester t, {double textScale = 1}) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
        ),
        child: const SafeWalkFlow(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester t) async {
  final link = find.text('資料來源與授權');
  // 一般字級的首頁不捲動；大字體清單則先捲到實際入口再點選。
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isNotEmpty) {
    await t.scrollUntilVisible(link, 200, scrollable: scrollables.first);
  } else {
    await t.ensureVisible(link);
  }
  await t.tap(link);
  await t.pumpAndSettle();
}

Finder get _sheetScroll => find
    .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
    .first;

Future<void> _expand(WidgetTester t, String title) async {
  await t.scrollUntilVisible(find.text(title), 200, scrollable: _sheetScroll);
  await t.tap(find.text(title));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('分組列出開放資料、開源技術、使用者回報與版本，不出現示範或未使用的來源', (t) async {
    await _pump(t);
    await _openSheet(t);
    expect(find.text('開放資料'), findsOneWidget);
    expect(find.text('地圖與步行路網'), findsOneWidget);
    for (final group in ['開源技術', '使用者回報與團隊內容', '版本資訊']) {
      await t.scrollUntilVisible(find.text(group), 200, scrollable: _sheetScroll);
      expect(find.text(group), findsOneWidget, reason: group);
    }
    expect(find.textContaining('示範'), findsNothing, reason: '正式畫面不顯示示範字樣');
    expect(find.textContaining('暴力犯罪'), findsNothing, reason: '月統計未接入目前流程');
    expect(find.textContaining('Overpass'), findsNothing, reason: '附近地點用內建快照，不即時查詢');
    expect(find.textContaining('TownPass'), findsNothing, reason: '整合進臺北通後不需要另外說明');
  });

  testWidgets('收合時只有名稱、提供者、用途；展開後有授權、限制與連結按鈕', (t) async {
    await _pump(t);
    await _openSheet(t);
    expect(find.text('ODbL 1.0'), findsNothing);
    await _expand(t, '地圖與步行路網');
    expect(find.text('ODbL 1.0'), findsOneWidget);
    expect(find.text('查看授權'), findsOneWidget);
    expect(find.text('查看原始來源'), findsOneWidget);
    await _expand(t, '政府公開犯罪參考資料');
    expect(find.textContaining(swCrimeDataLimit), findsOneWidget);
    expect(find.textContaining('基隆的紀錄沒有參考位置'), findsOneWidget);
    expect(find.textContaining('回報資料說明'), findsWidgets);
    expect(find.textContaining('臺北市政府警察局刑警大隊'), findsOneWidget);
    await _expand(t, 'OSRM 路線引擎');
    expect(find.textContaining('BSD-2-Clause'), findsOneWidget, reason: '引擎與路網授權分開');
    await t.tap(find.text('OSRM 路線引擎'));
    await t.pumpAndSettle();
    expect(find.textContaining('BSD-2-Clause'), findsNothing, reason: '可以收合');
  });

  testWidgets('放大字體 200% 仍可展開、捲動，關閉後回到首頁', (t) async {
    await _pump(t, textScale: 2);
    // 字放大時首頁連結會被底部求助列擋住；直接開啟同一個面板。
    showSwDataSources(t.element(find.byType(Scaffold).first));
    await t.pumpAndSettle();
    await _expand(t, '政府公開犯罪參考資料');
    await t.scrollUntilVisible(find.text('版本資訊'), 300, scrollable: _sheetScroll);
    expect(t.takeException(), isNull, reason: '沒有版面溢出');
    await t.scrollUntilVisible(find.byTooltip('關閉'), -300, scrollable: _sheetScroll);
    await t.tap(find.byTooltip('關閉'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('安心行'), findsWidgets);
  });

  testWidgets('資料來源入口只在首頁，地圖資訊框不重複放', (t) async {
    await _pump(t);
    await _openSheet(t);
    expect(find.text('地圖與步行路網'), findsOneWidget);
    await t.tap(find.byTooltip('關閉'));
    await t.pumpAndSettle();
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    expect(find.text('資料來源與授權'), findsNothing);
  });
}
