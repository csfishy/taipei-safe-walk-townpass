import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// An injected local-audio capability, not a phone call or microphone service.
abstract interface class CompanionAudioAdapter {
  Future<void> playAsset(
    String assetPath, {
    SafeWalkCancellation? cancellation,
  });

  Future<void> pause();

  Future<void> stop();

  /// Idempotently release playback, timers, and native resources.
  Future<void> dispose();
}

/// M5 owns a pure controller; presentation and GetX bindings are separate work.
abstract interface class CompanionController {
  Stream<sw.CompanionEvent> get events;

  Future<void> start(
    sw.CompanionScenario scenario, {
    SafeWalkCancellation? cancellation,
  });

  Future<void> pause();

  Future<void> stop(sw.CompanionStopReason reason);

  /// Cancel pending playback, stop audio, and close the event stream once.
  Future<void> dispose();
}
