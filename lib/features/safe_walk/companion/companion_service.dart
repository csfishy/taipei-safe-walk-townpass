import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// One local-audio playback lifecycle.
///
/// [started] completes only after the adapter confirms audible playback has
/// begun. [completed] completes only after that asset has finished normally.
/// Stop, cancellation, and adapter errors may complete either future with an
/// error; callers must not infer one milestone from the other.
abstract interface class CompanionPlayback {
  Future<void> get started;

  Future<void> get completed;
}

/// An injected local-audio capability, not a phone call or microphone service.
abstract interface class CompanionAudioAdapter {
  /// Creates a playback and returns its two explicit lifecycle milestones.
  ///
  /// Returning the handle does not itself mean playback has started or ended.
  Future<CompanionPlayback> playAsset(
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
