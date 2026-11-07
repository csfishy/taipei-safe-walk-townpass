import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// M4 normalizes source records, then delegates shared validation to contracts.
abstract interface class SafetyDataParser {
  sw.AssistancePoint parseAssistancePoint(Map<String, Object?> json);

  sw.AreaStatistics parseAreaStatistics(Map<String, Object?> json);
}

/// In-process data access; this declaration does not create a backend or API.
abstract interface class SafetyDataRepository {
  Future<List<sw.AssistancePoint>> getAssistancePoints({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  });

  Future<List<sw.AreaStatistics>> getAreaStatistics({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  });
}
