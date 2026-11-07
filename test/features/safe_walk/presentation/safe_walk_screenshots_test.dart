// M3 設計截圖：只在設定 M3_SCREENSHOTS=1 時執行，產出各畫面 PNG 給設計校對；CI 預設略過（字型渲染依平台不同）。
// 執行：M3_SCREENSHOTS=1 flutter test test/features/safe_walk/presentation/safe_walk_screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

final _skip = Platform.environment['M3_SCREENSHOTS'] == null;

Future<void> _fonts() async {
  final ping = FontLoader('PingFangTC');
  for (final w in ['Regular', 'Medium', 'Semibold']) {
    ping.addFont(File('fonts/PingFangTC-$w.otf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await ping.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = FontLoader('MaterialIcons')..addFont(File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await icons.load();
}

class _Speaking implements SafeWalkSpeaker {
  @override
  bool get available => true;
  @override
  void speak(String text, {void Function()? onDone}) {}
  @override
  void stop() {}
}

Future<void> _app(WidgetTester t, {SafeWalkSpeaker speaker = const UnavailableSpeaker()}) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'PingFangTC'),
    home: SafeWalkFlow(speaker: speaker, onExit: () {}),
  ));
  await t.pumpAndSettle();
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.pumpAndSettle(const Duration(milliseconds: 50));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
}

Future<void> _tap(WidgetTester t, String text) async {
  await t.tap(find.text(text).first);
  await t.pump(const Duration(milliseconds: 300));
  await t.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
}

void main() {
  setUpAll(() async {
    if (!_skip) await _fonts();
  });

  testWidgets('01 首頁', (t) async {
    await _app(t);
    await _shot(t, '01-home');
  }, skip: _skip);

  testWidgets('02 地圖：回家路線', (t) async {
    await _app(t);
    await _tap(t, '安心回家');
    await _shot(t, '02-map-home');
    await _tap(t, '文字路線');
    await t.drag(find.byType(SingleChildScrollView).last, const Offset(0, -400));
    await t.pumpAndSettle();
    await _shot(t, '03-route-steps');
  }, skip: _skip);

  testWidgets('04 最近求助地點與收合資訊框', (t) async {
    await _app(t);
    await _tap(t, '安心回家');
    await _tap(t, '最近求助地點');
    await _shot(t, '04-nearest-point');
    await t.tap(find.bySemanticsLabel('收合資訊框'));
    await t.pumpAndSettle();
    await _shot(t, '04b-sheet-collapsed');
    await t.tap(find.bySemanticsLabel(RegExp('展開資訊框')));
    await t.pumpAndSettle();
    await t.fling(find.bySemanticsLabel('收合資訊框'), const Offset(0, -200), 1000);
    await t.pumpAndSettle();
    await _shot(t, '04c-sheet-full');
  }, skip: _skip);

  testWidgets('10 求助地點載入失敗', (t) async {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'PingFangTC'), home: SafeWalkFlow(pointsError: '網路連線中斷，請稍後再試。', onRetryPoints: () {})));
    await t.pumpAndSettle();
    await _tap(t, '附近求助地點');
    await _shot(t, '10-points-error');
  }, skip: _skip);

  testWidgets('11 目的地選單', (t) async {
    await _app(t);
    await _tap(t, '安心回家');
    await t.tap(find.textContaining('→ 家'));
    await t.pumpAndSettle();
    await _shot(t, '11-places');
  }, skip: _skip);

  testWidgets('05 附近求助地點', (t) async {
    await _app(t);
    await _tap(t, '附近求助地點');
    await _shot(t, '05-points');
  }, skip: _skip);

  testWidgets('06 回報狀況', (t) async {
    await _app(t);
    await _tap(t, '回報狀況');
    await _tap(t, '用我目前的位置');
    await _shot(t, '06-report-form');
  }, skip: _skip);

  testWidgets('07 異常詳情', (t) async {
    await _app(t);
    await _tap(t, '安心回家');
    await t.tap(find.bySemanticsLabel(RegExp('打架衝突')).first);
    await t.pumpAndSettle();
    await _shot(t, '07-anomaly-detail');
  }, skip: _skip);

  testWidgets('08 模擬來電（朗讀中）', (t) async {
    await _app(t, speaker: _Speaking());
    await t.tap(find.text('模擬來電').first);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('結束通話'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/08-call.png'));
  }, skip: _skip);

  testWidgets('09 緊急求助頁', (t) async {
    await _app(t);
    await _tap(t, '緊急求助');
    await _shot(t, '09-emergency');
  }, skip: _skip);
}
