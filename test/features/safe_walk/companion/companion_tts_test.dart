import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
      expect(engine.languages, ['en-US', 'en-GB']);
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
    late List<Map<String, String>> voices;
    late Object? setVoiceResult;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = [];
      availableLanguages = {'zh-CN'};
      speakResult = 1;
      setVoiceResult = 1;
      voices = [
        {
          'name': 'local-zh-CN',
          'locale': 'zh-CN',
          'network_required': '0',
          'features': '',
        },
      ];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'isLanguageAvailable':
            return availableLanguages.contains(call.arguments);
          case 'speak':
            return speakResult;
          case 'getVoices':
            return voices
                .where((voice) => availableLanguages.contains(voice['locale']))
                .toList();
          case 'setVoice':
            return setVoiceResult;
          default:
            return 1;
        }
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    Future<void> platformSays(String method) => messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );

    test('offline policy rejects a network-only Chinese voice', () async {
      voices.single['network_required'] = '1';
      final engine = FlutterTtsEngine(FlutterTts());

      expect(await engine.prepare(['zh-CN']), isFalse);
      expect(calls.where((call) => call.method == 'setLanguage'), isEmpty);
      expect(calls.where((call) => call.method == 'setVoice'), isEmpty);
    });

    test('offline policy rejects missing voice privacy metadata', () async {
      voices.single.remove('network_required');
      final engine = FlutterTtsEngine(FlutterTts());

      expect(await engine.prepare(['zh-CN']), isFalse);
      expect(calls.where((call) => call.method == 'setVoice'), isEmpty);
    });

    test('offline policy rejects a voice requiring installation', () async {
      voices.single['features'] = 'notInstalled';
      final engine = FlutterTtsEngine(FlutterTts());

      expect(await engine.prepare(['zh-CN']), isFalse);
      expect(calls.where((call) => call.method == 'setVoice'), isEmpty);
    });

    test(
      'offline policy requires successful explicit voice selection',
      () async {
        setVoiceResult = 0;
        final engine = FlutterTtsEngine(FlutterTts());

        expect(await engine.prepare(['zh-CN']), isFalse);
      },
    );

    test('falls back to the next available Chinese voice', () async {
      final engine = FlutterTtsEngine(FlutterTts());
      expect(await engine.prepare(['zh-TW', 'zh-CN']), isTrue);
      final selected = calls.singleWhere((c) => c.method == 'setVoice');
      expect(selected.arguments, {'name': 'local-zh-CN', 'locale': 'zh-CN'});
      expect(calls.where((c) => c.method == 'setLanguage'), isEmpty);
    });

    test('selects an installed iOS voice by identifier', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      availableLanguages = {'zh-TW'};
      voices = [
        {
          'name': 'Mei-Jia',
          'locale': 'zh-TW',
          'identifier': 'com.apple.voice.compact.zh-TW.Mei-Jia',
        },
      ];
      final engine = FlutterTtsEngine(FlutterTts());

      expect(await engine.prepare(['zh-TW', 'zh-CN']), isTrue);
      expect(
        calls.singleWhere((c) => c.method == 'setVoice').arguments,
        voices.single,
      );
      expect(calls.where((c) => c.method == 'setLanguage'), isEmpty);
    });

    test(
      'unknown native platforms stay unavailable without querying voices',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final engine = FlutterTtsEngine(FlutterTts());

        expect(await engine.prepare(['zh-CN']), isFalse);
        expect(calls, isEmpty);
      },
    );

    test('reports no voice when none is installed', () async {
      availableLanguages = {};
      final engine = FlutterTtsEngine(FlutterTts());
      expect(await engine.prepare(['zh-TW', 'zh-CN']), isFalse);
      expect(calls.where((c) => c.method == 'setLanguage'), isEmpty);
    });

    test('never asks the plugin to await completion', () async {
      final engine = FlutterTtsEngine(FlutterTts());
      await engine.prepare(['zh-CN']);
      unawaited(engine.speak('喂？'));
      await pumpEventQueue();
      expect(
        calls.map((c) => c.method),
        isNot(contains('awaitSpeakCompletion')),
      );
    });

    test('an utterance ends on the platform completion callback', () async {
      final engine = FlutterTtsEngine(FlutterTts());
      var finished = false;
      unawaited(engine.speak('喂？').then((_) => finished = true));
      await pumpEventQueue();
      expect(finished, isFalse);
      await platformSays('speak.onComplete');
      await pumpEventQueue();
      expect(finished, isTrue);
    });

    test(
      'stop releases pending speech but times out without a terminal',
      () async {
        final engine = FlutterTtsEngine(FlutterTts());
        var finished = false;
        unawaited(engine.speak('喂？').then((_) => finished = true));
        await pumpEventQueue();
        final stopped = expectLater(
          engine.stop(),
          throwsA(isA<TimeoutException>()),
        );
        await pumpEventQueue();
        expect(finished, isTrue);
        expect(calls.map((c) => c.method), contains('stop'));
        await stopped;
      },
    );

    test('a rejected utterance ends at once', () async {
      speakResult = 0;
      final engine = FlutterTtsEngine(FlutterTts());
      var finished = false;
      unawaited(engine.speak('喂？').then((_) => finished = true));
      await pumpEventQueue();
      expect(finished, isTrue);
    });

    test('idle stop never calls native code or creates a timer', () async {
      final engine = FlutterTtsEngine(FlutterTts());

      Future<void> expectIdleStop() async {
        var timers = 0;
        await runZoned(
          engine.stop,
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              timers++;
              return parent.createTimer(zone, duration, callback);
            },
          ),
        );
        expect(calls.where((call) => call.method == 'stop'), isEmpty);
        expect(timers, 0);
      }

      await expectIdleStop();
      final spoken = engine.speak('正常結束的語句');
      await pumpEventQueue();
      await platformSays('speak.onComplete');
      await spoken;
      await expectIdleStop();
    });

    test('concurrent active stops share one terminal barrier', () async {
      final engine = FlutterTtsEngine(FlutterTts());
      final spoken = engine.speak('舊句');
      await pumpEventQueue();

      final firstStop = engine.stop();
      final secondStop = engine.stop();
      expect(identical(firstStop, secondStop), isTrue);
      await pumpEventQueue();
      expect(calls.where((call) => call.method == 'stop'), hasLength(1));
      await platformSays('speak.onCancel');
      await Future.wait([spoken, firstStop, secondStop]);
    });

    test(
      'new speech also waits when terminal arrives before stop RPC reply',
      () async {
        final stopReply = Completer<Object?>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'stop') return await stopReply.future;
          return 1;
        });
        final engine = FlutterTtsEngine(FlutterTts());
        final first = engine.speak('舊句');
        await pumpEventQueue();
        final stopping = engine.stop();
        final second = engine.speak('新句');
        await platformSays('speak.onCancel');
        await pumpEventQueue();
        expect(calls.where((call) => call.method == 'speak'), hasLength(1));

        stopReply.complete(1);
        await stopping;
        await pumpEventQueue();
        expect(calls.where((call) => call.method == 'speak'), hasLength(2));
        await platformSays('speak.onComplete');
        await Future.wait([first, second]);
      },
    );

    test(
      'late rejection of an old speak RPC cannot release new speech',
      () async {
        final oldReply = Completer<Object?>();
        var speaks = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'speak' && ++speaks == 1) return oldReply.future;
          return 1;
        });
        final engine = FlutterTtsEngine(FlutterTts());
        final first = engine.speak('舊句');
        await pumpEventQueue();
        final stopping = engine.stop();
        var newFinished = false;
        final second = engine.speak('新句').then((_) => newFinished = true);
        await platformSays('speak.onCancel');
        await stopping;
        await pumpEventQueue();

        oldReply.complete(0);
        await pumpEventQueue();
        expect(newFinished, isFalse);
        await platformSays('speak.onComplete');
        await Future.wait([first, second]);
        expect(newFinished, isTrue);
      },
    );

    for (final terminal in [
      'speak.onCancel',
      'speak.onComplete',
      'speak.onError',
    ]) {
      test(
        'terminal barrier consumes old $terminal before starting new speech',
        () async {
          final engine = FlutterTtsEngine(FlutterTts());
          final first = engine.speak('舊句');
          await pumpEventQueue();
          final stopped = engine.stop();
          var newFinished = false;
          final second = engine.speak('新句').then((_) => newFinished = true);
          await pumpEventQueue();
          final startedBeforeOldTerminal = calls
              .where((call) => call.method == 'speak')
              .length;

          await platformSays(terminal);
          await stopped;
          await pumpEventQueue();
          final finishedByOldTerminal = newFinished;
          await platformSays('speak.onComplete');
          await Future.wait([first, second]);

          expect(startedBeforeOldTerminal, 1);
          expect(finishedByOldTerminal, isFalse);
          expect(newFinished, isTrue);
        },
      );
    }

    test(
      'terminal barrier timeout disables voice and rejects late restart',
      () async {
        final speaker = CompanionTtsSpeaker(FlutterTtsEngine(FlutterTts()));
        await speaker.prepare();
        speaker.speak('舊句');
        await pumpEventQueue();
        speaker.stop();
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        expect(speaker.available, isFalse);
        await platformSays('speak.onCancel');
        speaker.speak('不可以因為遲到回呼重新播放');
        await pumpEventQueue();
        expect(calls.where((call) => call.method == 'speak'), hasLength(1));
        await speaker.dispose();
      },
    );

    test(
      'device driver handoff isolates old route callbacks and late stop',
      () async {
        final oldRoute = FlutterTtsEngine();
        final first = oldRoute.speak('舊路線');
        await pumpEventQueue();
        final stopped = oldRoute.stop();
        final newRoute = FlutterTtsEngine();
        var newFinished = false;
        final second = newRoute.speak('新路線').then((_) => newFinished = true);
        await pumpEventQueue();
        final startedBeforeOldTerminal = calls
            .where((call) => call.method == 'speak')
            .length;

        await platformSays('speak.onCancel');
        await stopped;
        await pumpEventQueue();
        final finishedByOldTerminal = newFinished;
        final stopsBeforeOldDispose = calls
            .where((call) => call.method == 'stop')
            .length;
        await oldRoute.stop();
        final stopsAfterOldDispose = calls
            .where((call) => call.method == 'stop')
            .length;
        await platformSays('speak.onComplete');
        await Future.wait([first, second]);

        expect(startedBeforeOldTerminal, 1);
        expect(finishedByOldTerminal, isFalse);
        expect(stopsAfterOldDispose, stopsBeforeOldDispose);
        expect(newFinished, isTrue);
      },
    );
    test(
      'stopping a queued owner prevents late speech after handoff',
      () async {
        final oldRoute = FlutterTtsEngine();
        final first = oldRoute.speak('舊路線');
        await pumpEventQueue();
        final stopping = oldRoute.stop();
        final queuedRoute = FlutterTtsEngine();
        final queued = queuedRoute.speak('已離開的新路線');
        await pumpEventQueue();
        await queuedRoute.stop();

        await platformSays('speak.onCancel');
        await stopping;
        await pumpEventQueue();
        final dispatched = calls.where((call) => call.method == 'speak').length;
        await platformSays('speak.onComplete');
        await Future.wait([first, queued]);

        expect(dispatched, 1);
      },
    );

    test('three queued owners recheck each new active utterance', () async {
      final oldRoute = FlutterTtsEngine();
      final first = oldRoute.speak('舊路線');
      await pumpEventQueue();
      final stopping = oldRoute.stop();
      final finished = <int>{};
      for (var i = 0; i < 3; i++) {
        final route = FlutterTtsEngine();
        unawaited(route.speak('排隊 $i').then((_) => finished.add(i)));
      }

      await platformSays('speak.onCancel');
      await stopping;
      await pumpEventQueue();
      await platformSays('speak.onCancel');
      await pumpEventQueue();
      final afterSecondTerminal = calls
          .where((call) => call.method == 'speak')
          .length;
      await platformSays('speak.onCancel');
      await pumpEventQueue();
      await platformSays('speak.onComplete');
      await first;
      await pumpEventQueue();

      expect(afterSecondTerminal, 3);
      expect(finished, {0, 1, 2});
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
