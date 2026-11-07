import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/companion_speaker_adapter.dart';
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
