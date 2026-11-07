import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// 模擬來電鈴聲（原創：程式合成的兩音鈴響，無任何第三方鈴聲素材）。
///
/// 這是「模擬陪伴」的提示音，不是真實來電，也沒有任何人撥號。
const companionRingCycle = Duration(milliseconds: 1500);

/// 合成一個鈴響週期的 16-bit PCM mono WAV：約 0.75 秒兩音鈴聲，其餘靜音，可無縫循環。
Uint8List buildCompanionRingtoneWav({int sampleRate = 16000}) {
  final total = (sampleRate * companionRingCycle.inMilliseconds / 1000).round();
  final pcm = ByteData(total * 2);
  const notes = [(784.0, 0.0, 0.35), (988.0, 0.38, 0.75)]; // G5、B5，原創音型
  for (var i = 0; i < total; i++) {
    final t = i / sampleRate;
    var v = 0.0;
    for (final (freq, start, end) in notes) {
      if (t < start || t >= end) continue;
      final age = t - start;
      final attack = math.min(1.0, age / 0.01);
      final release = math.min(1.0, (end - t) / 0.08);
      v += math.sin(2 * math.pi * freq * t) * attack * release * math.exp(-age * 3);
    }
    pcm.setInt16(i * 2, (v * 0.5 * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  final dataLen = pcm.lengthInBytes;
  final out = ByteData(44 + dataLen);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  out.setUint32(40, dataLen, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(44, bytes.length, pcm.buffer.asUint8List());
  return bytes;
}

/// 注入式循環播放能力（native 播放器或測試 fake）。
abstract interface class CompanionToneAdapter {
  /// 在實際開始循環播放後完成；失敗會丟出例外。
  Future<void> playLoop(Uint8List wav);

  Future<void> stop();

  Future<void> dispose();
}

/// 控制鈴聲生命週期。stop／dispose 會使尚未完成的 start 失效，
/// 遲到的播放結果不會重新發聲；自動在 [maxDuration] 後停止。
final class CompanionRingtone {
  CompanionRingtone(
    this._adapter, {
    this.maxDuration = const Duration(seconds: 18),
    Uint8List? wav,
  }) : _wav = wav ?? buildCompanionRingtoneWav();

  /// 預設使用裝置播放器。
  factory CompanionRingtone.device() => CompanionRingtone(AudioplayersToneAdapter());

  final CompanionToneAdapter _adapter;
  final Duration maxDuration;
  final Uint8List _wav;
  int _generation = 0;
  bool _disposed = false;
  Timer? _limit;

  Future<void> start() async {
    if (_disposed) return;
    final generation = ++_generation;
    _limit?.cancel();
    _limit = Timer(maxDuration, stop);
    try {
      await _adapter.playLoop(_wav);
    } catch (_) {
      // 無法發聲時安靜失敗；畫面仍有震動與視覺響鈴。
      if (generation == _generation) _limit?.cancel();
      return;
    }
    // 播放途中已被停止：補一次 stop，確保遲到的 play 不會繼續響。
    if (generation != _generation || _disposed) await _quietStop();
  }

  void stop() {
    if (_disposed) return;
    _generation++;
    _limit?.cancel();
    _limit = null;
    unawaited(_quietStop());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _limit?.cancel();
    _limit = null;
    await _quietStop();
    try {
      await _adapter.dispose();
    } catch (_) {}
  }

  Future<void> _quietStop() async {
    try {
      await _adapter.stop();
    } catch (_) {}
  }
}

/// audioplayers 實作：以記憶體 WAV 播放，不下載、不讀檔、不需任何權限。
final class AudioplayersToneAdapter implements CompanionToneAdapter {
  AudioplayersToneAdapter([AudioPlayer? player]) : _player = player;

  AudioPlayer? _player;
  AudioPlayer get _p => _player ??= AudioPlayer();

  @override
  Future<void> playLoop(Uint8List wav) async {
    await _p.setReleaseMode(ReleaseMode.loop);
    await _p.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> dispose() async {
    final p = _player;
    _player = null;
    await p?.dispose();
  }
}
