import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_controller.dart';
import 'package:town_pass/features/safe_walk/companion/companion_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  late FakeAudioAdapter audio;
  late LocalCompanionController controller;
  late List<sw.CompanionEvent> events;
  late StreamSubscription<sw.CompanionEvent> subscription;

  setUp(() {
    audio = FakeAudioAdapter();
    events = [];
    controller = buildController(audio);
    subscription = controller.events.listen(events.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await controller.dispose();
  });

  test('missing audio reports not configured without claiming playback', () async {
    await controller.start(scenario(audioSources: [null]));

    expect(audio.playedAssets, isEmpty);
    expect(events, hasLength(1));
    expect(events.single.state, sw.CompanionState.ended);
    expect(events.single.reason, sw.CompanionReason.notConfigured);
  });

  test('unapproved wire audio source is rejected locally', () async {
    await controller.start(scenario(audioSources: ['/audio/unknown.mp3']));

    expect(audio.playedAssets, isEmpty);
    expect(events.single.reason, sw.CompanionReason.notConfigured);
  });

  test('plays approved local assets in scenario order', () async {
    await controller.start(
      scenario(audioSources: ['/audio/one.mp3', '/audio/two.mp3']),
    );

    expect(audio.playedAssets, [
      'assets/companion/one.mp3',
      'assets/companion/two.mp3',
    ]);
    expect(events.map((event) => event.state), [
      sw.CompanionState.playing,
      sw.CompanionState.playing,
      sw.CompanionState.ended,
    ]);
  });

  test('pause invalidates pending progression', () async {
    final delayed = Completer<void>();
    await subscription.cancel();
    await controller.dispose();
    events.clear();
    audio = FakeAudioAdapter();
    controller = buildController(audio, delay: (_) => delayed.future);
    subscription = controller.events.listen(events.add);

    final start = controller.start(
      scenario(audioSources: ['/audio/one.mp3', '/audio/two.mp3']),
    );
    await pumpEventQueue();
    await controller.pause();
    delayed.complete();
    await start;

    expect(audio.pauseCalls, 1);
    expect(audio.playedAssets, ['assets/companion/one.mp3']);
    expect(events.last.state, sw.CompanionState.paused);
  });

  test('emergency stop emits once and prevents delayed next step', () async {
    final delayed = Completer<void>();
    await subscription.cancel();
    await controller.dispose();
    events.clear();
    audio = FakeAudioAdapter();
    controller = buildController(audio, delay: (_) => delayed.future);
    subscription = controller.events.listen(events.add);

    final start = controller.start(
      scenario(audioSources: ['/audio/one.mp3', '/audio/two.mp3']),
    );
    await pumpEventQueue();
    await controller.stop(sw.CompanionStopReason.emergency);
    await controller.stop(sw.CompanionStopReason.emergency);
    delayed.complete();
    await start;

    expect(audio.playedAssets, ['assets/companion/one.mp3']);
    expect(
      events.where((event) => event.reason == sw.CompanionReason.emergency),
      hasLength(1),
    );
  });

  test('cancellation stops audio and ignores a late play result', () async {
    final cancellation = TestCancellation();
    final play = Completer<void>();
    audio.playCompleter = play;

    final start = controller.start(
      scenario(audioSources: ['/audio/one.mp3']),
      cancellation: cancellation,
    );
    await pumpEventQueue();
    cancellation.cancel();
    await start;
    play.complete();
    await pumpEventQueue();

    expect(audio.stopCalls, 1);
    expect(events, isEmpty);
  });

  test('audio failure is explicit and stops the adapter', () async {
    audio.playError = StateError('audio unavailable');

    await controller.start(scenario(audioSources: ['/audio/one.mp3']));

    expect(audio.stopCalls, 1);
    expect(events.single.state, sw.CompanionState.error);
    expect(events.single.reason, sw.CompanionReason.audioError);
  });

  test('dispose is repeatable, terminates once, and releases audio once', () async {
    final delayed = Completer<void>();
    await subscription.cancel();
    await controller.dispose();
    events.clear();
    audio = FakeAudioAdapter();
    controller = buildController(audio, delay: (_) => delayed.future);
    subscription = controller.events.listen(events.add);

    final start = controller.start(
      scenario(audioSources: ['/audio/one.mp3', '/audio/two.mp3']),
    );
    await pumpEventQueue();
    await Future.wait([controller.dispose(), controller.dispose()]);
    delayed.complete();
    await start;

    expect(audio.disposeCalls, 1);
    expect(
      events.where((event) => event.reason == sw.CompanionReason.unmount),
      hasLength(1),
    );
  });
}

LocalCompanionController buildController(
  FakeAudioAdapter audio, {
  CompanionDelay? delay,
}) =>
    LocalCompanionController(
    audio: audio,
    resolveAsset: (source) => const {
      '/audio/one.mp3': 'assets/companion/one.mp3',
      '/audio/two.mp3': 'assets/companion/two.mp3',
    }[source],
    clock: () => DateTime.utc(2026, 11, 7, 7),
    delay: delay ?? (_) async {},
  );

sw.CompanionScenario scenario({required List<String?> audioSources}) =>
    sw.CompanionScenario(
      id: 'scenario-1',
      label: '測試陪伴',
      steps: [
        for (var index = 0; index < audioSources.length; index++)
          sw.CompanionStep(
            id: 'step-$index',
            text: '測試台詞 $index',
            audioSrc: audioSources[index],
            pauseAfterMs: 100,
          ),
      ],
    );

final class FakeAudioAdapter implements CompanionAudioAdapter {
  final List<String> playedAssets = [];
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  Completer<void>? playCompleter;
  Object? playError;

  @override
  Future<void> playAsset(
    String assetPath, {
    SafeWalkCancellation? cancellation,
  }) async {
    playedAssets.add(assetPath);
    if (playError case final error?) throw error;
    await playCompleter?.future;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

final class TestCancellation implements SafeWalkCancellation {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
