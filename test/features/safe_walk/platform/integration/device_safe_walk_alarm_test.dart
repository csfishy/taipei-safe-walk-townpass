import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/integration/device_safe_walk_alarm.dart';

class _Player extends Fake implements AudioPlayer {
  ReleaseMode? recordedReleaseMode;
  double? recordedVolume;
  Source? recordedSource;
  int stops = 0;
  int disposals = 0;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async => recordedReleaseMode = mode;

  @override
  Future<void> setVolume(double value) async => recordedVolume = value;

  @override
  Future<void> play(
    Source value, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async => recordedSource = value;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposals++;
}

void main() {
  test('安全警報是有效且非靜音的 mono WAV', () {
    final wav = buildSafetyAlarmWav();
    final data = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint16(34, Endian.little), 16);
    expect(data.getUint32(40, Endian.little), wav.length - 44);

    var peak = 0;
    for (var offset = 44; offset < wav.length; offset += 2) {
      peak = peak < data.getInt16(offset, Endian.little).abs()
          ? data.getInt16(offset, Endian.little).abs()
          : peak;
    }
    expect(peak, greaterThan(1000));
  });

  test('裝置播放器使用循環與 App 最大音量，dispose 會停止', () async {
    final player = _Player();
    final alarm = DeviceSafeWalkAlarm(player: player);

    await alarm.start();
    expect(player.recordedReleaseMode, ReleaseMode.loop);
    expect(player.recordedVolume, 1);
    expect(player.recordedSource, isA<BytesSource>());

    await alarm.dispose();
    expect(player.stops, 1);
    expect(player.disposals, 1);
    expect(alarm.available, isFalse);
  });
}
