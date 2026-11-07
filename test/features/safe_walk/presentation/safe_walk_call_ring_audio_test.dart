// 模擬來電鈴聲：響鈴開始、接聽／拒絕／SOS／背景都要停止；畫面仍標示模擬。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

class _RingSpy implements SafeWalkSpeaker, SafeWalkRinger {
  int starts = 0, stops = 0;
  bool get ringing => starts > 0 && lastWasStart;
  bool lastWasStart = false;
  @override
  bool get available => true;
  @override
  void speak(String text, {void Function()? onDone}) {}
  @override
  void stop() {}
  @override
  void startRing() {
    starts++;
    lastWasStart = true;
  }

  @override
  void stopRing() {
    stops++;
    lastWasStart = false;
  }
}

Future<void> _open(WidgetTester t, _RingSpy speaker) async {
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
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
  testWidgets('進入響鈴會開始鈴聲，接聽後停止，畫面保留模擬標示', (t) async {
    final s = _RingSpy();
    await _open(t, s);
    expect(s.ringing, isTrue);
    expect(find.textContaining('模擬'), findsWidgets);
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    expect(s.ringing, isFalse);
    expect(find.text('模擬通話，未聯絡任何人'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('返回'));
    await t.pumpAndSettle();
  });

  testWidgets('拒絕：鈴聲停止', (t) async {
    final s = _RingSpy();
    await _open(t, s);
    await t.tap(find.text('拒絕'));
    await t.pumpAndSettle();
    expect(s.ringing, isFalse);
    expect(s.stops, greaterThan(0));
  });

  testWidgets('響鈴中 SOS：鈴聲停止', (t) async {
    final s = _RingSpy();
    await _open(t, s);
    await t.tap(find.textContaining('緊急求助').last);
    await t.pumpAndSettle();
    expect(s.ringing, isFalse);
  });

  testWidgets('響鈴中進背景：鈴聲停止，回前景不自動重響', (t) async {
    final s = _RingSpy();
    await _open(t, s);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(s.ringing, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(s.ringing, isFalse);
    expect(s.starts, 1);
    await t.tap(find.text('拒絕'));
    await t.pumpAndSettle();
  });

  testWidgets('整頁關閉：鈴聲停止', (t) async {
    final s = _RingSpy();
    await _open(t, s);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(s.ringing, isFalse);
  });
}
