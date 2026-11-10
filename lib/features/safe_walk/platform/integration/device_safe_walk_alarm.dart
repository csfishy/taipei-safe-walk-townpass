import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_alarm.dart';

final class DeviceSafeWalkAlarm implements SafeWalkAlarm {
  DeviceSafeWalkAlarm({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  bool _disposed = false;

  @override
  bool get available => !_disposed;

  @override
  Future<void> start() async {
    if (_disposed) return;
    await _player.setReleaseMode(ReleaseMode.loop);
    // Maximum app-output amplitude. The OS volume remains under user control.
    await _player.setVolume(1);
    await _player.play(
      BytesSource(buildSafetyAlarmWav(), mimeType: 'audio/wav'),
    );
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.stop();
    await _player.dispose();
  }
}

/// Original dual-tone safety alarm synthesized locally without audio files.
Uint8List buildSafetyAlarmWav({int sampleRate = 16000}) {
  const durationSeconds = 6;
  final sampleCount = sampleRate * durationSeconds;
  final pcm = ByteData(sampleCount * 2);

  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final cycle = t % 0.8;
    final frequency = cycle < 0.4 ? 880.0 : 660.0;
    final pulse = t % 0.2;
    final envelope = math.min(
      1.0,
      math.min(pulse / 0.012, (0.2 - pulse) / 0.025),
    );
    final tone = math.sin(2 * math.pi * frequency * t);
    final harmonic = 0.22 * math.sin(4 * math.pi * frequency * t);
    final value = ((tone + harmonic) * envelope * 0.48).clamp(-1.0, 1.0);
    pcm.setInt16(i * 2, (value * 32767).round(), Endian.little);
  }

  final dataLength = pcm.lengthInBytes;
  final wav = ByteData(44 + dataLength);
  void writeTag(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      wav.setUint8(offset + i, tag.codeUnitAt(i));
    }
  }

  writeTag(0, 'RIFF');
  wav.setUint32(4, 36 + dataLength, Endian.little);
  writeTag(8, 'WAVE');
  writeTag(12, 'fmt ');
  wav.setUint32(16, 16, Endian.little);
  wav.setUint16(20, 1, Endian.little);
  wav.setUint16(22, 1, Endian.little);
  wav.setUint32(24, sampleRate, Endian.little);
  wav.setUint32(28, sampleRate * 2, Endian.little);
  wav.setUint16(32, 2, Endian.little);
  wav.setUint16(34, 16, Endian.little);
  writeTag(36, 'data');
  wav.setUint32(40, dataLength, Endian.little);

  final bytes = wav.buffer.asUint8List();
  bytes.setRange(44, bytes.length, pcm.buffer.asUint8List());
  return bytes;
}
