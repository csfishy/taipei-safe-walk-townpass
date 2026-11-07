import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

/// The speaker the Safe Walk route owns: what the view needs, plus the
/// emergency latch and single disposal the composition root relies on.
abstract interface class SafeWalkRouteSpeaker implements SafeWalkSpeaker {
  /// Blocks delayed speech while hidden. Passing true only permits subsequent
  /// explicit speak calls; it never replays speech or clears the emergency latch.
  void setLifecycleActive(bool active);

  /// Stops at once and stays silent for the rest of this route.
  Future<void> stopForEmergency();

  /// Idempotent release of speech resources.
  Future<void> dispose();
}
