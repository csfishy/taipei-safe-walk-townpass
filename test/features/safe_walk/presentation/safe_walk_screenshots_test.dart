// M3 設計截圖：只在設定 M3_SCREENSHOTS=1 時執行，產出各畫面 PNG 給設計校對；CI 預設略過（字型渲染依平台不同）。
// 執行：M3_SCREENSHOTS=1 flutter test test/features/safe_walk/presentation/safe_walk_screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

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
  // 測試環境的 'Roboto' 預設是方塊字型；載入真的 Roboto，英數才會跟臺北通（TPText）一樣。
  final roboto = FontLoader('Roboto');
  for (final w in ['regular', 'medium', 'bold']) {
    roboto.addFont(File('$root/bin/cache/artifacts/material_fonts/roboto-$w.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await roboto.load();
}

class _Speaking implements SafeWalkSpeaker {
  @override
  bool get available => true;
  @override
  void speak(String text, {void Function()? onDone}) {}
  @override
  void stop() {}
}

Future<void> _app(WidgetTester t, {SafeWalkSpeaker speaker = const UnavailableSpeaker(), sw.RouteResult? route}) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'PingFangTC'),
      home: SafeWalkFlow(speaker: speaker, onExit: () {}, route: route),
    ),
  );
  // 首頁卡片的 SVG（含內嵌 101 圖片）在測試時脈之外解碼；截圖前先等它載完。
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
  await t.pump();
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
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

  testWidgets('12 避讓：三條路線可選', (t) async {
    sw.RouteCandidate r(String id, String why, List<(double, double)> pts) => sw.RouteCandidate(
      id: id,
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(coordinates: [for (final (lat, lng) in pts) (longitude: lng, latitude: lat)]),
      distanceMeters: id == 'full' ? 560 : 330,
      durationSeconds: id == 'full' ? 430 : 250,
      viaPointIds: const [],
      provider: 'valhalla-pedestrian',
      walkingNetworkVerified: true,
      explanations: [why],
      warnings: const ['依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行'],
    );
    final route = sw.RouteSuccess(
      requestId: 'shot',
      mode: sw.DataMode.live,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      routes: [
        r('full', '避開 2 個回報點範圍', [(24.9995, 121.5003), (24.9995, 121.5015), (25.0015, 121.5015), (25.0015, 121.5009)]),
        r('none', '最短步行路線', [(24.9995, 121.5003), (24.9995, 121.5), (25.0015, 121.5), (25.0015, 121.5009)]),
      ],
      warnings: const ['依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行'],
    );
    await _app(t, route: route);
    await _tap(t, '安心行');
    await _shot(t, '12-avoid-routes');
  }, skip: _skip);

  testWidgets('01 首頁', (t) async {
    await _app(t);
    await _shot(t, '01-home');
  }, skip: _skip);

  testWidgets('01b 安心行卡片按下', (t) async {
    await _app(t);
    final g = await t.startGesture(t.getCenter(find.text('點擊開始')));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/01b-home-card-pressed.png'));
    await g.cancel();
    await t.pumpAndSettle();
  }, skip: _skip);

  testWidgets('02 地圖：回家路線', (t) async {
    await _app(t);
    await _tap(t, '安心行');
    await _shot(t, '02-map-home');
    await _tap(t, '文字路線');
    await t.drag(find.byType(SingleChildScrollView).last, const Offset(0, -400));
    await t.pumpAndSettle();
    await _shot(t, '03-route-steps');
  }, skip: _skip);

  testWidgets('04 最近求助地點與收合資訊框', (t) async {
    await _app(t);
    await _tap(t, '安心行');
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
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'PingFangTC'),
        home: SafeWalkFlow(pointsError: '網路連線中斷，請稍後再試。', onRetryPoints: () {}),
      ),
    );
    await t.pumpAndSettle();
    await _tap(t, '附近求助地點');
    await _shot(t, '10-points-error');
  }, skip: _skip);

  testWidgets('11 目的地選單', (t) async {
    await _app(t);
    await _tap(t, '安心行');
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
    await _tap(t, '安心行');
    await t.tap(find.bySemanticsLabel(RegExp('打架衝突')).first);
    await t.pumpAndSettle();
    await _shot(t, '07-anomaly-detail');
  }, skip: _skip);

  testWidgets('08a 模擬來電響鈴', (t) async {
    await _app(t);
    await t.tap(find.text('模擬來電').first);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/08a-incoming.png'));
  }, skip: _skip);

  testWidgets('08c 選擇通話情境（M5 劇本）', (t) async {
    await _app(t);
    await t.tap(find.text('模擬來電').first);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.textContaining('情境：'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/08c-scenario-picker.png'));
  }, skip: _skip);

  testWidgets('08b 模擬來電（臺北通內：語音未配置）', (t) async {
    await _app(t);
    await t.tap(find.text('模擬來電').first);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('接聽'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.tap(find.text('我在大馬路上，快到了。'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/08b-call-no-voice.png'));
  }, skip: _skip);

  testWidgets('08 模擬來電（朗讀中）', (t) async {
    await _app(t, speaker: _Speaking());
    await t.tap(find.text('模擬來電').first);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('接聽'));
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
