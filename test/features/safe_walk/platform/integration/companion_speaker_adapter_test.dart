import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/companion_speaker_adapter.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  test(
    'default bridge really composes M5 and reports text-only not_configured',
    () async {
      final speaker = CompanionSpeakerAdapter.unavailable();
      final events = <sw.CompanionEvent>[];
      final subscription = speaker.events.listen(events.add);
      final done = Completer<void>();

      expect(speaker.available, isFalse);
      speaker.speak('這是模擬陪伴台詞。', onDone: done.complete);
      await done.future;

      expect(events, hasLength(1));
      expect(events.single.state, sw.CompanionState.ended);
      expect(events.single.reason, sw.CompanionReason.notConfigured);
      expect(speaker.lastError, isNull);
      await speaker.dispose();
      await subscription.cancel();
    },
  );

  test(
    'unavailable native adapter never returns a fake playback handle',
    () async {
      const audio = UnavailableCompanionAudioAdapter();
      await expectLater(
        audio.playAsset('assets/not-installed.mp3'),
        throwsUnsupportedError,
      );
      await audio.pause();
      await audio.stop();
      await audio.dispose();
    },
  );

  test(
    'an injected audio scenario cannot silently enable recordings',
    () async {
      final controller = _Controller();
      final speaker = CompanionSpeakerAdapter(
        controller: controller,
        scenarioForText: (text) => sw.CompanionScenario(
          id: 'unexpected-audio',
          label: '未配置錄音',
          steps: [
            sw.CompanionStep(
              id: 'line',
              text: text,
              audioSrc: '/audio/voice.mp3',
              pauseAfterMs: 0,
            ),
          ],
        ),
      );
      final done = Completer<void>();
      speaker.speak('不能播放未配置的音檔。', onDone: done.complete);
      await done.future;

      expect(speaker.available, isFalse);
      expect(controller.scenarios, isEmpty);
      expect(speaker.lastError, isA<UnsupportedError>());
      await speaker.dispose();
    },
  );

  test(
    'invalid text does not bypass the shared schema or escape asynchronously',
    () async {
      final controller = _Controller();
      final speaker = CompanionSpeakerAdapter(controller: controller);
      final done = Completer<void>();
      speaker.speak(List.filled(301, '字').join(), onDone: done.complete);
      await done.future;

      expect(controller.scenarios, isEmpty);
      expect(speaker.lastError, isA<UnsupportedError>());
      await speaker.dispose();
    },
  );

  test('replacing a pending preview suppresses its late callback', () async {
    final controller = _Controller()..holdStarts = true;
    final speaker = CompanionSpeakerAdapter(controller: controller);
    var firstDone = 0, secondDone = 0;
    speaker.speak('第一句', onDone: () => firstDone++);
    await pumpEventQueue();
    speaker.speak('第二句', onDone: () => secondDone++);
    await pumpEventQueue();

    expect(controller.cancellations.first!.isCancelled, isTrue);
    controller.pendingStarts.last.complete();
    await pumpEventQueue();
    controller.pendingStarts.first.complete();
    await pumpEventQueue();

    expect(firstDone, 0);
    expect(secondDone, 1);
    await speaker.dispose();
  });

  test(
    'normal stop cancels a pending preview and ignores its delayed result',
    () async {
      final controller = _Controller()..holdStarts = true;
      final speaker = CompanionSpeakerAdapter(controller: controller);
      var done = 0;
      speaker.speak('待停止的文字', onDone: () => done++);
      await pumpEventQueue();
      speaker.stop();
      await pumpEventQueue();
      controller.pendingStarts.single.complete();
      await pumpEventQueue();

      expect(controller.cancellations.single!.isCancelled, isTrue);
      expect(controller.stops.last, sw.CompanionStopReason.user);
      expect(done, 0);
      await speaker.dispose();
    },
  );

  test('late failure from cancelled work does not escape or invoke an old callback', () async {
    final controller = _Controller()..holdStarts = true;
    final speaker = CompanionSpeakerAdapter(controller: controller);
    var done = 0;
    speaker.speak('已取消的回覆', onDone: () => done++);
    await pumpEventQueue();
    speaker.stop();
    await pumpEventQueue();
    controller.pendingStarts.single.completeError(StateError('late failure'));
    await pumpEventQueue();

    expect(done, 0);
    expect(
      speaker.lastError,
      isNull,
      reason: 'cancelled work is not a current failure',
    );
    await speaker.dispose();
  });

  test(
    'emergency stop is immediate and late replies cannot restart M5',
    () async {
      final controller = _Controller()..stopGate = Completer<void>();
      final speaker = CompanionSpeakerAdapter(controller: controller);
      var oldDone = 0, lateDone = 0;
      speaker.speak('等待前一個停止動作的回覆', onDone: () => oldDone++);
      final emergency = speaker.stopForEmergency();
      speaker.speak('SOS 後到達的延遲回覆', onDone: () => lateDone++);

      expect(controller.stops.last, sw.CompanionStopReason.emergency);
      expect(controller.scenarios, isEmpty);
      controller.stopGate!.complete();
      await emergency;
      await pumpEventQueue();

      expect(oldDone, 0);
      expect(lateDone, 1, reason: 'only clears the unavailable text indicator');
      expect(controller.scenarios, isEmpty);
      await speaker.dispose();
    },
  );

  test('pause invalidates pending speech work without restarting it', () async {
    final controller = _Controller()..holdStarts = true;
    final speaker = CompanionSpeakerAdapter(controller: controller);
    var done = 0;
    speaker.speak('等待中的回覆', onDone: () => done++);
    await pumpEventQueue();
    await speaker.pause();
    controller.pendingStarts.single.complete();
    await pumpEventQueue();

    expect(controller.pauses, 1);
    expect(done, 0);
    await speaker.dispose();
  });

  test('background prevents a late start even after resume', () async {
    final controller = _Controller()..stopGate = Completer<void>();
    final speaker = CompanionSpeakerAdapter(controller: controller);
    var oldDone = 0, blockedDone = 0, resumedDone = 0;
    speaker.speak('還在等待停止的舊台詞', onDone: () => oldDone++);
    speaker.setLifecycleActive(false);
    speaker.speak('背景的新台詞', onDone: () => blockedDone++);
    speaker.setLifecycleActive(true);
    controller.stopGate!.complete();
    await pumpEventQueue();

    expect(controller.scenarios, isEmpty);
    expect(oldDone, 0);
    expect(blockedDone, 1);
    expect(speaker.available, isFalse, reason: 'resume cannot configure audio');
    speaker.speak('回前景後的明確新要求', onDone: () => resumedDone++);
    await pumpEventQueue();
    expect(controller.scenarios.single.steps.single.text, '回前景後的明確新要求');
    expect(resumedDone, 1);
    await speaker.dispose();
  });

  test(
    'background cancels a pending start and ignores its late error',
    () async {
      final controller = _Controller()..holdStarts = true;
      final speaker = CompanionSpeakerAdapter(controller: controller);
      var oldDone = 0;
      speaker.speak('已開始但仍在等待的預覽', onDone: () => oldDone++);
      await pumpEventQueue();

      speaker.setLifecycleActive(false);
      expect(controller.cancellations.single!.isCancelled, isTrue);
      speaker.setLifecycleActive(true);
      controller.pendingStarts.single.completeError(StateError('late start'));
      await pumpEventQueue();

      expect(controller.scenarios, hasLength(1));
      expect(oldDone, 0);
      expect(speaker.lastError, isNull);
      expect(speaker.available, isFalse);
      await speaker.dispose();
    },
  );

  test('resuming a background bridge cannot clear emergency stop', () async {
    final controller = _Controller();
    final speaker = CompanionSpeakerAdapter(controller: controller);
    speaker.setLifecycleActive(false);
    await speaker.stopForEmergency();
    speaker.setLifecycleActive(true);
    var done = 0;
    speaker.speak('SOS 之後不重啟', onDone: () => done++);
    await pumpEventQueue();

    expect(controller.stops, contains(sw.CompanionStopReason.emergency));
    expect(controller.scenarios, isEmpty);
    expect(done, 1);
    expect(speaker.available, isFalse);
    await speaker.dispose();
  });

  testWidgets('composition lifecycle gates the non-TTS bridge', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controller = _Controller();
    final speaker = CompanionSpeakerAdapter(controller: controller);
    await tester.pumpWidget(
      MaterialApp(home: SafeWalkCompositionRoot(speaker: speaker)),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    speaker.speak('背景不交給 M5');
    await tester.pump();
    expect(controller.scenarios, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.scenarios, isEmpty, reason: 'no replay on resume');
    speaker.speak('回前景後的新要求');
    await tester.pump();
    expect(controller.scenarios, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.disposals, 1);
  });

  test(
    'dispose fences off new work before awaiting stop and disposes only once',
    () async {
      final controller = _Controller()..stopGate = Completer<void>();
      final speaker = CompanionSpeakerAdapter(controller: controller);
      speaker.speak('還在等待停止的回覆');
      final first = speaker.dispose();
      final second = speaker.dispose();
      speaker.speak('dispose 期間不得重啟');
      expect(identical(first, second), isTrue);
      expect(controller.scenarios, isEmpty);

      controller.stopGate!.complete();
      await first;
      await pumpEventQueue();
      await speaker.pause();
      await speaker.stopForEmergency();
      speaker.stop();

      expect(controller.disposals, 1);
      expect(controller.pauses, 0);
      expect(controller.scenarios, isEmpty);
    },
  );

  test(
    'background stop errors are observable and disposal still releases M5',
    () async {
      final controller = _Controller()..stopError = StateError('stop failed');
      final speaker = CompanionSpeakerAdapter(controller: controller);
      speaker.stop();
      await pumpEventQueue();
      expect(speaker.lastError, isA<StateError>());
      await speaker.dispose();
      expect(controller.disposals, 1);
    },
  );
}

final class _Controller implements CompanionController {
  final scenarios = <sw.CompanionScenario>[];
  final cancellations = <SafeWalkCancellation?>[];
  final stops = <sw.CompanionStopReason>[];
  final pendingStarts = <Completer<void>>[];
  final _events = StreamController<sw.CompanionEvent>.broadcast();
  bool holdStarts = false;
  Completer<void>? stopGate;
  Object? stopError;
  int pauses = 0, disposals = 0;

  @override
  Stream<sw.CompanionEvent> get events => _events.stream;

  @override
  Future<void> start(
    sw.CompanionScenario scenario, {
    SafeWalkCancellation? cancellation,
  }) async {
    scenarios.add(scenario);
    cancellations.add(cancellation);
    if (holdStarts) {
      final pending = Completer<void>();
      pendingStarts.add(pending);
      await pending.future;
    }
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> stop(sw.CompanionStopReason reason) async {
    stops.add(reason);
    if (stopError case final error?) throw error;
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await _events.close();
  }
}
