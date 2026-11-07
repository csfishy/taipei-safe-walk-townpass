// 模擬來電的離開清理：響鈴（震動）、對方回覆計時、朗讀，在拒絕／緊急求助／返回／整頁關閉後都要停。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

class _Spy implements SafeWalkSpeaker {
  _Spy({this.enabled = true});

  bool enabled;
  final spoken = <String>[];
  @override
  bool get available => enabled;
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

  testWidgets('語音延遲準備完成後，既有來電畫面會改用真實 speaker', (t) async {
    final speaker = _Spy(enabled: false);
    await _open(t, speaker);

    speaker.enabled = true;
    await t.pumpWidget(MaterialApp(home: SafeWalkFlow(speaker: speaker)));
    await t.pump();
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));

    expect(speaker.spoken, hasLength(1));
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
    await t.tap(find.text('我正在回家路上，已經吃過了。'));
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

  testWidgets('通話中去地圖看路再回來：不再響鈴，對話接續，對方補上回覆', (t) async {
    final speaker = _Spy();
    await _open(t, speaker);
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('我正在回家路上，已經吃過了。'));
    await t.pump(const Duration(milliseconds: 100));
    // 點上方「下一步」導航條到地圖
    await t.tap(find.bySemanticsLabel(RegExp('點一下打開地圖')));
    await t.pumpAndSettle();
    expect(find.text('結束通話'), findsNothing);
    await t.tap(find.text('模擬來電').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('接聽'), findsNothing, reason: '已接聽的通話回來不再響鈴');
    expect(find.text('喂，你走到哪裡啦？晚餐吃了沒？'), findsOneWidget, reason: '對話保留，不會從頭再來一次');
    expect(find.text('我正在回家路上，已經吃過了。'), findsNWidgets(2), reason: '我的回覆泡泡還在（另一個是仍顯示的快速回覆）');
    await t.pump(const Duration(seconds: 1));
    expect(speaker.spoken, hasLength(2), reason: '離開前回覆過，回來後對方補上回答');
    await t.tap(find.text('結束通話'));
    await t.pumpAndSettle();
    await t.tap(find.text('模擬來電'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('接聽'), findsOneWidget, reason: '結束後再打來是新的一通');
    await t.tap(find.text('拒絕'));
    await t.pumpAndSettle();
  });
}
