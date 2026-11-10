// 模擬來電的離開清理：響鈴（震動）、對方回覆計時、朗讀，在拒絕／緊急求助／返回／整頁關閉後都要停。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/companion_dialogues.dart';
import 'package:town_pass/features/safe_walk/presentation/companion_scenarios.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

class _Spy implements SafeWalkSpeaker {
  final spoken = <String>[];
  final completions = <void Function()?>[];
  bool ready = true;
  @override
  bool get available => ready;
  @override
  void speak(String text, {void Function()? onDone}) {
    spoken.add(text);
    completions.add(onDone);
  }

  void finish() => completions.last?.call();
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

  testWidgets('一直不接：震動約 18 秒後停止', (t) async {
    await _open(t, _Spy());
    await t.pump(const Duration(seconds: 20));
    final after = _buzzes;
    expect(after, 12, reason: '一開始 1 次＋每 1.5 秒 1 次，共 12 次');
    await t.pump(const Duration(seconds: 10));
    expect(_buzzes, after);
    await t.tap(find.text('拒絕'));
    await t.pumpAndSettle();
  });

  testWidgets('拒絕：回到首頁，之後不再震動也不朗讀', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    await t.tap(find.text('拒絕'));
    await t.pumpAndSettle();
    expect(find.text('點擊開始'), findsOneWidget);
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
    await t.tap(find.text('我快到了啦，還在路上，再幾分鐘。'));
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
    expect(find.text('點擊開始'), findsOneWidget);
    final after = _buzzes;
    await t.pump(const Duration(seconds: 5));
    expect(_buzzes, after);
  });

  testWidgets('單一嚇阻劇本依序完成三段男性 TTS 與兩段女性照讀稿', (t) async {
    final speaker = _Spy();
    final ride = m5CompanionScenarios.single;
    await _open(t, speaker);
    await t.tap(find.textContaining('情境：'));
    await t.pumpAndSettle();
    await t.tap(find.text(ride.label));
    await t.pumpAndSettle();
    expect(find.text('情境：${ride.label}'), findsOneWidget);
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    expect(speaker.spoken, [ride.steps[0].text]);
    expect(find.text('模擬通話，未聯絡任何人'), findsOneWidget, reason: '模擬陪伴揭露需持續顯示（見 companion README）');

    await t.pump(const Duration(seconds: 20));
    expect(speaker.spoken, hasLength(1), reason: '沒回覆時對方不會自己一直說下去');

    for (var i = 0; i < companionReplies[ride.id]!.length; i++) {
      await t.tap(find.text(companionReplies[ride.id]![i].first).last);
      await t.pump(const Duration(seconds: 1));
    }
    expect(speaker.spoken, ride.steps.map((s) => s.text).toList(), reason: '四段繁中照讀稿之間依序播放五段英文台詞');
    // The fake has not completed its final utterance: do not claim playback
    // finished just because the final line was queued.
    expect(find.textContaining('對方說完了'), findsOneWidget);
    expect(find.textContaining('已播放完畢'), findsNothing);

    await t.tap(find.text('結束通話'));
    await t.pumpAndSettle();
  });

  testWidgets('回覆區可以收合與展開', (t) async {
    await _open(t, _Spy());
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    final reply = companionReplies['stalker-deterrence']!.first.first;
    expect(find.text(reply), findsOneWidget);
    await t.tap(find.byTooltip('收合回覆區'));
    await t.pumpAndSettle();
    expect(find.text(reply), findsNothing);
    await t.tap(find.text('照讀台詞'));
    await t.pumpAndSettle();
    expect(find.text(reply), findsOneWidget);
    await t.tap(find.text('結束通話'));
    await t.pumpAndSettle();
  });

  testWidgets('響鈴期間語音準備完成：接聽第一句使用真正的 speaker', (t) async {
    final speaker = _Spy()..ready = false;
    await _open(t, speaker);
    expect(speaker.spoken, isEmpty);

    speaker.ready = true;
    t.element(find.byType(SafeWalkFlow)).markNeedsBuild();
    await t.pump();
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    final spoken = [...speaker.spoken];
    await t.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(spoken, [m5CompanionScenarios.first.steps.first.text]);
  });

  testWidgets('語音準備晚到：手動重播使用真正的 speaker', (t) async {
    final speaker = _Spy()..ready = false;
    await _open(t, speaker);
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    speaker.ready = true;
    t.element(find.byType(SafeWalkFlow)).markNeedsBuild();
    await t.pump();
    await t.tap(find.text(m5CompanionScenarios.first.steps.first.text));
    await t.pump();
    final spoken = [...speaker.spoken];
    await t.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(spoken, [m5CompanionScenarios.first.steps.first.text]);
  });

  testWidgets('背景取消待回覆；回前景不自動朗讀，仍可手動重播', (t) async {
    final speaker = _Spy();
    addTearDown(() => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await _open(t, speaker);
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text(companionReplies['stalker-deterrence']!.first.first));
    await t.pump(const Duration(milliseconds: 100));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(seconds: 2));
    final inBackground = [...speaker.spoken];
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(seconds: 2));
    final afterResume = [...speaker.spoken];
    await t.tap(find.text(m5CompanionScenarios.first.steps.first.text));
    await t.pump();
    final afterReplay = [...speaker.spoken];
    await t.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(inBackground, [m5CompanionScenarios.first.steps.first.text]);
    expect(afterResume, inBackground);
    expect(afterReplay, [...inBackground, m5CompanionScenarios.first.steps.first.text]);
  });
}
