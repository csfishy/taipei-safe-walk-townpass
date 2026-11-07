import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// M1's explicit, user-initiated seam to native platform capabilities.
///
/// This interface does not obtain GPS, request permissions, or activate a phone.
/// Implementations must reject false `userInitiated` before native side effects.
/// Mock mode must use fixtures and must never obtain a real device location.
abstract interface class PlatformService {
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  });

  /// An OS handoff is not evidence of a connected call or official acceptance.
  ///
  /// A real handoff requires live mode, a user action, and [allowRealCalls].
  /// Location in [summary] cannot be shared without its explicit consent.
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  });
}
