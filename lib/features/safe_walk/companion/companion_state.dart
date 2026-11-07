import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart';

/// Playback acknowledgements are distinct from a user's start request.
enum CompanionAction {
  playbackStarted,
  playbackPaused,
  stopped,
  emergency,
  unmounted,
  visibilityHidden,
  audioError,
}

/// Pure state seam; does not play audio, start timers or claim a real call.
CompanionState nextCompanionState(
  CompanionState current,
  CompanionAction action,
) => switch (action) {
  CompanionAction.stopped ||
  CompanionAction.emergency ||
  CompanionAction.unmounted ||
  CompanionAction.visibilityHidden => CompanionState.ended,
  CompanionAction.audioError => CompanionState.error,
  CompanionAction.playbackStarted => CompanionState.playing,
  CompanionAction.playbackPaused when current == CompanionState.playing =>
    CompanionState.paused,
  _ => current,
};
