import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// M2 consumes M1's position; it never starts another GPS listener.
abstract interface class RouteService {
  /// Preserve requestId; cancellation and unavailable providers are failures.
  ///
  /// A live provider must not fall back to a mock route labelled as live.
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  });
}
