import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_tts.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(TtsSafeWalkSpeaker, _Engine)> ready({bool voice = true}) async {
    final engine = _Engine(voice: voice);
    final speaker = TtsSafeWalkSpeaker(CompanionTtsSpeaker(engine));
    await speaker.prepare();
    return (speaker, engine);
  }

  test('is a route speaker the composition root can own', () async {
    final (speaker, _) = await ready();
    expect(speaker, isA<SafeWalkRouteSpeaker>());
  });

  test('stays text-only when the device has no Chinese voice', () async {
    final (speaker, engine) = await ready(voice: false);
    expect(speaker.available, isFalse);
    var done = 0;
    speaker.speak('喂，你到哪了？', onDone: () => done++);
    expect(done, 1);
    expect(engine.spoken, isEmpty);
  });

  test('speaks once a voice is confirmed', () async {
    final (speaker, engine) = await ready();
    expect(speaker.available, isTrue);
    speaker.speak('走大路，走亮的地方。');
    await pumpEventQueue();
    expect(engine.spoken, ['走大路，走亮的地方。']);
  });

  test('an emergency stop silences the route for good', () async {
    final (speaker, engine) = await ready();
    var done = 0;
    speaker.speak('第一句', onDone: () => done++);
    await pumpEventQueue();

    await speaker.stopForEmergency();
    expect(speaker.available, isFalse);
    expect(engine.stopCalls, greaterThanOrEqualTo(2));
    engine.finishAll();
    await pumpEventQueue();
    expect(done, 0, reason: 'the interrupted line must not report done');

    speaker.speak('求助後不會再唸', onDone: () => done++);
    await pumpEventQueue();
    expect(done, 1);
    expect(engine.spoken, ['第一句']);
  });

  test('dispose is repeatable', () async {
    final (speaker, _) = await ready();
    await speaker.dispose();
    await speaker.dispose();
    expect(speaker.available, isFalse);
  });

  testWidgets('background blocks delayed speech without replay on resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final (speaker, engine) = await ready();
    await tester.pumpWidget(
      MaterialApp(home: SafeWalkCompositionRoot(speaker: speaker)),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    speaker.speak('背景中才到的回覆');
    await tester.pump();
    expect(engine.spoken, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(engine.spoken, isEmpty, reason: 'resume must not replay old speech');
    speaker.speak('使用者回來後的新要求');
    await tester.pump();
    expect(engine.spoken, ['使用者回來後的新要求']);

    await speaker.stopForEmergency();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    speaker.speak('SOS 後不會重啟');
    await tester.pump();
    expect(engine.spoken, ['使用者回來後的新要求']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'without the platform plugin the device speaker is unavailable',
    () async {
      final speaker = TtsSafeWalkSpeaker.device();
      await speaker.prepare();
      expect(speaker.available, isFalse);
      var done = 0;
      speaker.speak('喂？', onDone: () => done++);
      expect(done, 1);
      speaker.stop();
      await speaker.stopForEmergency();
      await speaker.dispose();
    },
  );
}

final class _Engine implements CompanionSpeechEngine {
  _Engine({required this.voice});
  final bool voice;
  int stopCalls = 0;
  final spoken = <String>[];
  final _pending = <Completer<void>>[];

  @override
  Future<bool> prepare(List<String> languages) async => voice;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    final c = Completer<void>();
    _pending.add(c);
    return c.future;
  }

  @override
  Future<void> stop() async => stopCalls++;

  void finishAll() {
    for (final c in _pending) {
      if (!c.isCompleted) c.complete();
    }
    _pending.clear();
  }
}
