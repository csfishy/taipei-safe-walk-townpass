import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_ringtone.dart';
import 'package:town_pass/features/safe_walk/companion/companion_tts.dart';
import 'package:town_pass/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart';

class _Tone implements CompanionToneAdapter {
  final log = <String>[];
  Completer<void>? gate;
  Completer<void>? stopGate;
  bool playing = false;
  Uint8List? wav;

  @override
  Future<void> playLoop(Uint8List w) async {
    log.add('play');
    wav = w;
    await gate?.future;
    playing = true; // 模擬「遲到的 play 結果真的開始發聲」
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    await stopGate?.future;
    playing = false;
  }

  @override
  Future<void> dispose() async => log.add('dispose');
}

class _Engine implements CompanionSpeechEngine {
  final spoken = <String>[];
  int stops = 0;
  @override
  Future<bool> prepare(List<String> languages) async => true;
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {
    stops++;
  }
}

class _Player extends Fake implements AudioPlayer {
  final releaseGate = Completer<void>();
  Completer<void>? playGate;
  int plays = 0;
  int stops = 0;
  int disposals = 0;
  bool playing = false;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) => releaseGate.future;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    plays++;
    await playGate?.future;
    playing = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    playing = false;
  }
}

class _Failing implements CompanionToneAdapter {
  @override
  Future<void> playLoop(Uint8List wav) async => throw StateError('no audio');
  @override
  Future<void> stop() async => throw StateError('no audio');
  @override
  Future<void> dispose() async => throw StateError('no audio');
}

void main() {
  test('合成鈴聲是有效、非靜音的 16-bit mono WAV', () {
    final wav = buildCompanionRingtoneWav();
    final d = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(d.getUint16(22, Endian.little), 1);
    expect(d.getUint16(34, Endian.little), 16);
    expect(d.getUint32(4, Endian.little), wav.length - 8);
    expect(d.getUint32(40, Endian.little), wav.length - 44);
    var peak = 0;
    for (var o = 44; o < wav.length; o += 2) {
      final s = d.getInt16(o, Endian.little).abs();
      if (s > peak) peak = s;
    }
    expect(peak, greaterThan(3000), reason: '鈴聲要聽得到');
    expect(peak, lessThan(32767));
  });

  test('start 播放合成音，stop 停止', () async {
    final tone = _Tone();
    final ring = CompanionRingtone(tone);
    await ring.start();
    expect(tone.playing, isTrue);
    expect(tone.wav, isNotEmpty);
    ring.stop();
    await pumpEventQueue();
    expect(tone.playing, isFalse);
    await ring.dispose();
  });

  test('stop 後才完成的 play 不會重新響鈴', () async {
    final tone = _Tone()..gate = Completer<void>();
    final ring = CompanionRingtone(tone);
    final started = ring.start();
    await pumpEventQueue();
    ring.stop();
    tone.gate!.complete();
    await started;
    expect(tone.playing, isFalse);
  });

  test(
    'restart waits for stale play cleanup before starting the new ring',
    () async {
      final tone = _Tone()..gate = Completer<void>();
      final ring = CompanionRingtone(tone);
      final first = ring.start();
      await pumpEventQueue();
      ring.stop();
      final second = ring.start();
      await pumpEventQueue();
      expect(tone.log.where((e) => e == 'play'), hasLength(1));
      tone.gate!.complete();
      await Future.wait([first, second]);
      expect(tone.playing, isTrue);
      expect(tone.log.where((e) => e == 'play'), hasLength(2));
      await ring.dispose();
    },
  );

  test('restart waits for a delayed stop before playing again', () async {
    final tone = _Tone();
    final ring = CompanionRingtone(tone);
    await ring.start();
    tone.stopGate = Completer<void>();
    ring.stop();
    final restarted = ring.start();
    await pumpEventQueue();
    expect(tone.log.where((e) => e == 'play'), hasLength(1));
    tone.stopGate!.complete();
    await restarted;
    expect(tone.playing, isTrue);
    expect(tone.log.where((e) => e == 'play'), hasLength(2));
    await ring.dispose();
  });

  group('native tone adapter cancellation', () {
    test('stop during setup prevents playback', () async {
      final player = _Player();
      final adapter = AudioplayersToneAdapter(player);
      final starting = adapter.playLoop(Uint8List(1));
      await adapter.stop();
      player.releaseGate.complete();
      await starting;
      expect(player.plays, 0);
      expect(player.playing, isFalse);
      await adapter.dispose();
    });

    test('dispose during setup cannot create a replacement player', () async {
      final player = _Player();
      final adapter = AudioplayersToneAdapter(player);
      final starting = adapter.playLoop(Uint8List(1));
      await adapter.dispose();
      player.releaseGate.complete();
      await starting;
      await adapter.playLoop(Uint8List(1));
      expect(player.plays, 0);
      expect(player.disposals, 1);
      expect(player.playing, isFalse);
    });

    test(
      'stop during delayed playback stops its late completion too',
      () async {
        final player = _Player()..playGate = Completer<void>();
        player.releaseGate.complete();
        final adapter = AudioplayersToneAdapter(player);
        final starting = adapter.playLoop(Uint8List(1));
        await pumpEventQueue();
        expect(player.plays, 1);
        await adapter.stop();
        player.playGate!.complete();
        await starting;
        expect(player.playing, isFalse);
        expect(player.stops, 2);
        await adapter.dispose();
      },
    );
  });

  test('dispose 中途：遲到結果不發聲，重複 dispose 安全，之後 start 無效', () async {
    final tone = _Tone()..gate = Completer<void>();
    final ring = CompanionRingtone(tone);
    final started = ring.start();
    await pumpEventQueue();
    final d1 = ring.dispose();
    tone.gate!.complete();
    await started;
    await d1;
    await ring.dispose();
    await ring.start();
    expect(tone.playing, isFalse);
    expect(tone.log.where((e) => e == 'dispose'), hasLength(1));
    expect(tone.log.where((e) => e == 'play'), hasLength(1));
  });

  test('響鈴逾時自動停止', () async {
    final tone = _Tone();
    final ring = CompanionRingtone(
      tone,
      maxDuration: const Duration(milliseconds: 20),
    );
    await ring.start();
    expect(tone.playing, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(tone.playing, isFalse);
    await ring.dispose();
  });

  test('播放器錯誤不丟出例外', () async {
    final ring = CompanionRingtone(_Failing());
    await ring.start();
    await ring.dispose();
  });

  group('TtsSafeWalkSpeaker 鈴聲與朗讀', () {
    Future<(TtsSafeWalkSpeaker, _Tone, _Engine)> make() async {
      final tone = _Tone();
      final engine = _Engine();
      final s = TtsSafeWalkSpeaker(
        CompanionTtsSpeaker(engine),
        ringtone: CompanionRingtone(tone),
      );
      await s.prepare();
      return (s, tone, engine);
    }

    test('startRing 發聲；裝置 TTS 也實際朗讀', () async {
      final (s, tone, engine) = await make();
      s.startRing();
      await pumpEventQueue();
      expect(tone.playing, isTrue);
      s.speak('喂，你到哪了？');
      await pumpEventQueue();
      expect(engine.spoken, ['喂，你到哪了？']);
    });

    test('stopRing 停止鈴聲', () async {
      final (s, tone, _) = await make();
      s.startRing();
      await pumpEventQueue();
      s.stopRing();
      await pumpEventQueue();
      expect(tone.playing, isFalse);
    });

    test('背景（lifecycle inactive）停止鈴聲，返回前景不會自動重響', () async {
      final (s, tone, _) = await make();
      s.startRing();
      await pumpEventQueue();
      s.setLifecycleActive(false);
      await pumpEventQueue();
      expect(tone.playing, isFalse);
      s.setLifecycleActive(true);
      await pumpEventQueue();
      expect(tone.playing, isFalse);
    });

    test('背景時 startRing 不發聲', () async {
      final (s, tone, _) = await make();
      s.setLifecycleActive(false);
      s.startRing();
      await pumpEventQueue();
      expect(tone.log.where((e) => e == 'play'), isEmpty);
    });

    test('SOS：停止鈴聲，之後本路線不再響也不再朗讀', () async {
      final (s, tone, engine) = await make();
      s.startRing();
      await pumpEventQueue();
      await s.stopForEmergency();
      expect(tone.playing, isFalse);
      s.startRing();
      s.speak('不該出現');
      await pumpEventQueue();
      expect(tone.playing, isFalse);
      expect(engine.spoken, isEmpty);
    });

    test('dispose 釋放播放器', () async {
      final (s, tone, _) = await make();
      s.startRing();
      await pumpEventQueue();
      await s.dispose();
      expect(tone.playing, isFalse);
      expect(tone.log, contains('dispose'));
    });

    test('dispose fences TTS before a slow ringtone stop completes', () async {
      final (s, tone, engine) = await make();
      tone.stopGate = Completer<void>();
      final disposing = s.dispose();
      expect(s.available, isFalse);
      s.speak('must not play during disposal');
      s.startRing();
      await pumpEventQueue();
      expect(engine.spoken, isEmpty);
      expect(engine.stops, greaterThan(0));
      expect(tone.log.where((e) => e == 'play'), isEmpty);
      tone.stopGate!.complete();
      await disposing;
    });
  });
}
