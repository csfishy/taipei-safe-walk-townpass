import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

/// The speaker the Safe Walk route owns: what the view needs, plus the
/// emergency latch and single disposal the composition root relies on.
abstract interface class SafeWalkRouteSpeaker implements SafeWalkSpeaker {
  /// Prevents delayed view work from restarting speech while the app is hidden.
  /// Passing true again restores speech unless an emergency already latched it off.
  void setLifecycleActive(bool active);

  /// Stops at once and stays silent for the rest of this route.
  Future<void> stopForEmergency();

  /// Idempotent release of speech resources.
  Future<void> dispose();
}
