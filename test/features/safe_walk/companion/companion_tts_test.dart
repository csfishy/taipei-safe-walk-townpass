import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanionTtsSpeaker', () {
    test('is unavailable until the device confirms a voice', () async {
      final engine = _FakeEngine(prepared: false);
      final speaker = CompanionTtsSpeaker(engine);
      expect(speaker.available, isFalse);
      await speaker.prepare();
      expect(speaker.available, isFalse);

      var done = 0;
      speaker.speak('喂，你到哪了？', onDone: () => done++);
      expect(done, 1, reason: 'unavailable speech ends like a text preview');
      expect(engine.spoken, isEmpty);
    });

    test('a failing prepare leaves the speaker unavailable', () async {
      final speaker = CompanionTtsSpeaker(_FakeEngine(prepareThrows: true));
      await speaker.prepare();
      expect(speaker.available, isFalse);
    });

    test('prepare runs once and passes the language preference', () async {
      final engine = _FakeEngine();
      final speaker = CompanionTtsSpeaker(engine);
      await Future.wait([speaker.prepare(), speaker.prepare()]);
      expect(engine.prepareCalls, 1);
      expect(engine.languages, ['zh-TW', 'zh-CN']);
      expect(speaker.available, isTrue);
    });

    test('speaks a line and reports done only after it finishes', () async {
      final engine = _FakeEngine();
      final speaker = CompanionTtsSpeaker(engine);
      await speaker.prepare();

      var done = 0;
      speaker.speak('走大路，走亮的地方。', onDone: () => done++);
      await pumpEventQueue();
      expect(engine.spoken, ['走大路，走亮的地方。']);
      expect(done, 0);

      engine.finishCurrent();
      await pumpEventQueue();
      expect(done, 1);
    });

    test(
      'a newer line silences the older line and its late completion',
      () async {
        final engine = _FakeEngine();
        final speaker = CompanionTtsSpeaker(engine);
        await speaker.prepare();

        final done = <String>[];
        speaker.speak('第一句', onDone: () => done.add('first'));
        await pumpEventQueue();
        speaker.speak('第二句', onDone: () => done.add('second'));
        await pumpEventQueue();

        expect(engine.stopCalls, greaterThanOrEqualTo(2));
        engine.finishAll();
        await pumpEventQueue();
        expect(done, ['second']);
      },
    );

    test('stop prevents onDone of the stopped line', () async {
      final engine = _FakeEngine();
      final speaker = CompanionTtsSpeaker(engine);
      await speaker.prepare();

      var done = 0;
      speaker.speak('慢慢走，不要急。', onDone: () => done++);
      await pumpEventQueue();
      speaker.stop();
      engine.finishAll();
      await pumpEventQueue();
      expect(done, 0);
    });

    test('empty text never reaches the engine', () async {
      final engine = _FakeEngine();
      final speaker = CompanionTtsSpeaker(engine);
      await speaker.prepare();
      var done = 0;
      speaker.speak('   ', onDone: () => done++);
      expect(done, 1);
      expect(engine.spoken, isEmpty);
    });

    test('engine failure ends the line without throwing', () async {
      final engine = _FakeEngine(speakThrows: true);
      final speaker = CompanionTtsSpeaker(engine);
      await speaker.prepare();
      var done = 0;
      speaker.speak('怕的話，按求助。', onDone: () => done++);
      await pumpEventQueue();
      expect(done, 1);
    });

    test('dispose is repeatable and makes the speaker unavailable', () async {
      final engine = _FakeEngine();
      final speaker = CompanionTtsSpeaker(engine);
      await speaker.prepare();
      var done = 0;
      speaker.speak('到家記得關好門。', onDone: () => done++);
      await pumpEventQueue();

      await speaker.dispose();
      await speaker.dispose();
      expect(speaker.available, isFalse);
      engine.finishAll();
      await pumpEventQueue();
      expect(done, 0);

      speaker.speak('不會再唸', onDone: () => done++);
      expect(done, 1);
      expect(engine.spoken, ['到家記得關好門。']);
    });
  });

  group('FlutterTtsEngine (mocked platform channel)', () {
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late Set<String> availableLanguages;
    late Object? speakResult;

    setUp(() {
      calls = [];
      availableLanguages = {'zh-CN'};
      speakResult = 1;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'isLanguageAvailable':
            return availableLanguages.contains(call.arguments);
          case 'speak':
            return speakResult;
          default:
            return 1;
        }
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> platformSays(String method) => messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );

    test('falls back to the next available Chinese voice', () async {
      final engine = FlutterTtsEngine();
      expect(await engine.prepare(['zh-TW', 'zh-CN']), isTrue);
      final setLanguage = calls.where((c) => c.method == 'setLanguage');
      expect(setLanguage.single.arguments, 'zh-CN');
    });

    test('reports no voice when none is installed', () async {
      availableLanguages = {};
      final engine = FlutterTtsEngine();
      expect(await engine.prepare(['zh-TW', 'zh-CN']), isFalse);
      expect(calls.where((c) => c.method == 'setLanguage'), isEmpty);
    });

    test('never asks the plugin to await completion', () async {
      final engine = FlutterTtsEngine();
      await engine.prepare(['zh-CN']);
      unawaited(engine.speak('喂？'));
      await pumpEventQueue();
      expect(
        calls.map((c) => c.method),
        isNot(contains('awaitSpeakCompletion')),
      );
    });

    test('an utterance ends on the platform completion callback', () async {
      final engine = FlutterTtsEngine();
      var finished = false;
      unawaited(engine.speak('喂？').then((_) => finished = true));
      await pumpEventQueue();
      expect(finished, isFalse);
      await platformSays('speak.onComplete');
      await pumpEventQueue();
      expect(finished, isTrue);
    });

    test('stop releases a pending utterance even without a callback', () async {
      final engine = FlutterTtsEngine();
      var finished = false;
      unawaited(engine.speak('喂？').then((_) => finished = true));
      await pumpEventQueue();
      await engine.stop();
      await pumpEventQueue();
      expect(finished, isTrue);
      expect(calls.map((c) => c.method), contains('stop'));
    });

    test('a rejected utterance ends at once', () async {
      speakResult = 0;
      final engine = FlutterTtsEngine();
      var finished = false;
      unawaited(engine.speak('喂？').then((_) => finished = true));
      await pumpEventQueue();
      expect(finished, isTrue);
    });
  });
}

final class _FakeEngine implements CompanionSpeechEngine {
  _FakeEngine({
    this.prepared = true,
    this.prepareThrows = false,
    this.speakThrows = false,
  });

  final bool prepared, prepareThrows, speakThrows;
  int prepareCalls = 0, stopCalls = 0;
  List<String>? languages;
  final spoken = <String>[];
  final _pending = <Completer<void>>[];

  @override
  Future<bool> prepare(List<String> languages) async {
    prepareCalls++;
    this.languages = languages;
    if (prepareThrows) throw StateError('no tts');
    return prepared;
  }

  @override
  Future<void> speak(String text) {
    if (speakThrows) return Future.error(StateError('speak failed'));
    spoken.add(text);
    final pending = Completer<void>();
    _pending.add(pending);
    return pending.future;
  }

  @override
  Future<void> stop() async => stopCalls++;

  void finishCurrent() => _pending.removeLast().complete();

  void finishAll() {
    for (final p in _pending) {
      if (!p.isCompleted) p.complete();
    }
    _pending.clear();
  }
}
