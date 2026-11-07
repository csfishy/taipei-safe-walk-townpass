// 模擬來電的離開清理：響鈴（震動）、對方回覆計時、朗讀，在拒絕／緊急求助／返回／整頁關閉後都要停。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_dialogues.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_scenarios.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

class _Spy implements SafeWalkSpeaker {
  final spoken = <String>[];
  @override
  bool get available => true;
  @override
  void speak(String text, {void Function()? onDone}) => spoken.add(text);
  @override
  void stop() {}
}

/// 計算 HapticFeedback.vibrate 次數。
int _buzzes = 0;

Future<void> _open(WidgetTester t, _Spy speaker) async {
  _buzzes = 0;
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') _buzzes++;
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: SafeWalkFlow(speaker: speaker)));
  await t.pumpAndSettle();
  await t.tap(find.text('模擬來電'));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('響鈴會持續震動、還沒接聽不朗讀', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    final first = _buzzes;
    expect(first, greaterThan(0));
    await t.pump(const Duration(seconds: 3));
    expect(_buzzes, greaterThan(first));
    expect(speaker.spoken, isEmpty);
    await t.tap(find.text('拒絕'));
    await t.pumpAndSettle();
  });

  testWidgets('拒絕：回到首頁，之後不再震動也不朗讀', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    await t.tap(find.text('拒絕'));
    await t.pumpAndSettle();
    expect(find.text('安心行'), findsOneWidget);
    final after = _buzzes;
    await t.pump(const Duration(seconds: 5));
    expect(_buzzes, after);
    expect(speaker.spoken, isEmpty);
  });

  testWidgets('響鈴中按緊急求助：進求助頁，震動停止', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    await t.tap(find.textContaining('緊急求助').last);
    await t.pumpAndSettle();
    expect(find.text('撥打 110 報警'), findsOneWidget);
    final after = _buzzes;
    await t.pump(const Duration(seconds: 5));
    expect(_buzzes, after);
    expect(speaker.spoken, isEmpty);
  });

  testWidgets('接聽後回覆倒數中按返回：對方不會再開口', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    expect(speaker.spoken, hasLength(1));
    await t.tap(find.text('我在大馬路上，快到了。'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.bySemanticsLabel('返回'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    expect(speaker.spoken, hasLength(1), reason: '離開後不能再朗讀對方的回覆');
  });

  testWidgets('響鈴中整個安心行被關掉：計時器全部釋放', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    final after = _buzzes;
    await t.pump(const Duration(seconds: 5));
    expect(_buzzes, after);
  });

  testWidgets('系統返回鍵在響鈴中：等同拒絕', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('安心行'), findsOneWidget);
    final after = _buzzes;
    await t.pump(const Duration(seconds: 5));
    expect(_buzzes, after);
  });

  testWidgets('M5 劇本一問一答：對方不會自己一直講；你回一句它才接下一句；說完會提示', (t) async {
    final speaker = _Spy();
    final ride = m5CompanionScenarios.firstWhere((c) => c.id == 'scenario-rideshare');
    await _open(t, speaker);
    await t.tap(find.textContaining('情境：'));
    await t.pumpAndSettle();
    await t.tap(find.text(ride.label));
    await t.pumpAndSettle();
    expect(find.text('情境：${ride.label}'), findsOneWidget);
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    expect(speaker.spoken, [ride.steps[0].text]);
    expect(find.text('模擬通話，未聯絡任何人'), findsOneWidget, reason: '用 M5 的揭露文字');

    await t.pump(const Duration(seconds: 20));
    expect(speaker.spoken, hasLength(1), reason: '沒回覆時對方不會自己一直說下去');

    for (var i = 0; i < ride.steps.length; i++) {
      await t.tap(find.text(companionReplies[ride.id]![i].first).last);
      await t.pump(const Duration(seconds: 1));
    }
    expect(speaker.spoken, ride.steps.map((s) => s.text).toList(), reason: '每回一句，對方照劇本接下一句');
    expect(find.textContaining('對方說完了'), findsOneWidget);

    await t.tap(find.text('結束通話'));
    await t.pumpAndSettle();
  });

  testWidgets('回覆區可以收合與展開', (t) async {
    await _open(t, _Spy());
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    final reply = companionReplies['walk-home-night']!.first.first;
    expect(find.text(reply), findsOneWidget);
    await t.tap(find.byTooltip('收合回覆區'));
    await t.pumpAndSettle();
    expect(find.text(reply), findsNothing);
    await t.tap(find.text('快速回覆'));
    await t.pumpAndSettle();
    expect(find.text(reply), findsOneWidget);
    await t.tap(find.text('結束通話'));
    await t.pumpAndSettle();
  });
}
