import 'dart:async';

import 'package:town_pass/features/safe_walk/companion/companion_tts.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';

/// M1 bridge from the view's speaker to M5's on-device TTS.
///
/// Device speech only: no API key, network service or recording. Until the
/// device confirms a Chinese voice it is unavailable and the view keeps its
/// text-only notice. After an emergency stop it stays silent for this route.
final class TtsSafeWalkSpeaker implements SafeWalkRouteSpeaker {
  TtsSafeWalkSpeaker(this._tts);

  factory TtsSafeWalkSpeaker.device() =>
      TtsSafeWalkSpeaker(CompanionTtsSpeaker(FlutterTtsEngine()));

  final CompanionTtsSpeaker _tts;
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
    if (!active) _tts.stop();
  }

  @override
  void stop() => _tts.stop();

  @override
  Future<void> stopForEmergency() async {
    _emergencyStopped = true;
    _tts.stop();
  }

  @override
  Future<void> dispose() => _tts.dispose();
}
