import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/companion/companion_state.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart';

void main() {
  test('playing requires an actual playback acknowledgement', () {
    expect(
      nextCompanionState(CompanionState.idle, CompanionAction.playbackPaused),
      CompanionState.idle,
    );
    expect(
      nextCompanionState(CompanionState.idle, CompanionAction.playbackStarted),
      CompanionState.playing,
    );
    expect(
      nextCompanionState(
        CompanionState.playing,
        CompanionAction.playbackPaused,
      ),
      CompanionState.paused,
    );
  });
  for (final state in CompanionState.values) {
    for (final action in [
      CompanionAction.stopped,
      CompanionAction.emergency,
      CompanionAction.unmounted,
      CompanionAction.visibilityHidden,
    ]) {
      test('$action terminates $state', () {
        expect(nextCompanionState(state, action), CompanionState.ended);
      });
    }
  }
  test('audio failure is explicit and is not playback success', () {
    expect(
      nextCompanionState(CompanionState.playing, CompanionAction.audioError),
      CompanionState.error,
    );
  });
}
