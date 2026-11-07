import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_ringtone.dart';
import 'package:town_pass/features/safe_walk/companion/companion_tts.dart';
import 'package:town_pass/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart';

class _Tone implements CompanionToneAdapter {
  final log = <String>[];
  Completer<void>? gate;
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
    playing = false;
  }

  @override
  Future<void> dispose() async => log.add('dispose');
}

class _Engine implements CompanionSpeechEngine {
  final spoken = <String>[];
  @override
  Future<bool> prepare(List<String> languages) async => true;
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
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
    final ring = CompanionRingtone(tone, maxDuration: const Duration(milliseconds: 20));
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
      final s = TtsSafeWalkSpeaker(CompanionTtsSpeaker(engine), ringtone: CompanionRingtone(tone));
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
  });
}
