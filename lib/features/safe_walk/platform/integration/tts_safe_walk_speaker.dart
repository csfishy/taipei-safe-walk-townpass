import 'dart:async';

import 'package:town_pass/features/safe_walk/companion/companion_ringtone.dart';
import 'package:town_pass/features/safe_walk/companion/companion_tts.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

/// M1 bridge from the view's speaker to M5's on-device TTS.
///
/// Device speech only: no API key, network service or recording. Until the
/// device confirms a suitable voice it is unavailable and the view keeps its
/// text-only notice. After an emergency stop it stays silent for this route.
final class TtsSafeWalkSpeaker implements SafeWalkRouteSpeaker, SafeWalkRinger {
  TtsSafeWalkSpeaker(this._tts, {CompanionRingtone? ringtone})
    : _ringtone = ringtone; // ignore: prefer_initializing_formals

  factory TtsSafeWalkSpeaker.device() => TtsSafeWalkSpeaker(
    CompanionTtsSpeaker(FlutterTtsEngine()),
    ringtone: CompanionRingtone.device(),
  );

  final CompanionTtsSpeaker _tts;
  final CompanionRingtone? _ringtone;
  bool _emergencyStopped = false;
  bool _lifecycleActive = true;

  /// Asks the device for a voice; safe to call more than once.
  Future<void> prepare() => _tts.prepare();

  @override
  bool get available =>
      _lifecycleActive && !_emergencyStopped && _tts.available;

  @override
  void speak(String text, {void Function()? onDone}) {
    if (!_lifecycleActive || _emergencyStopped) {
      onDone?.call();
      return;
    }
    _tts.speak(text, onDone: onDone);
  }

  @override
  void setLifecycleActive(bool active) {
    if (_lifecycleActive == active) return;
    _lifecycleActive = active;
    if (!active) {
      _tts.stop();
      _ringtone?.stop();
    }
  }

  @override
  void startRing() {
    if (!_lifecycleActive || _emergencyStopped) return;
    unawaited(_ringtone?.start());
  }

  @override
  void stopRing() => _ringtone?.stop();

  @override
  void stop() => _tts.stop();

  @override
  Future<void> stopForEmergency() async {
    _emergencyStopped = true;
    _ringtone?.stop();
    _tts.stop();
  }

  @override
  Future<void> dispose() async {
    _lifecycleActive = false;
    _emergencyStopped = true;
    // Fence speech immediately, even if the native ringtone stop is delayed.
    await Future.wait([
      _tts.dispose(),
      if (_ringtone != null) _ringtone.dispose(),
    ]);
  }
}
