import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Parses normalized records using the canonical model and semantic checks.
final class ContractSafetyDataParser implements SafetyDataParser {
  const ContractSafetyDataParser();

  @override
  sw.AssistancePoint parseAssistancePoint(Map<String, Object?> json) {
    final point = sw.AssistancePoint.fromJson(json);
    _requireSemantics('AssistancePoint', pointProblems(point));
    return point;
  }

  @override
  sw.AreaStatistics parseAreaStatistics(Map<String, Object?> json) {
    final statistics = sw.AreaStatistics.fromJson(json);
    _requireSemantics('AreaStatistics', statisticsProblems(statistics));
    return statistics;
  }
}

/// An unavailable source is different from a configured source with no records.
/// This is an internal exception, not an additional schema payload or status.
final class SafeWalkDataUnavailable implements Exception {
  const SafeWalkDataUnavailable();

  @override
  String toString() => 'Safe Walk live safety data source is not configured';
}

void _requireSemantics(String contract, List<String> problems) {
  if (problems.isNotEmpty) {
    // Shared checks contain rule descriptions, never the rejected record.
    throw FormatException(
      'Invalid $contract semantics: ${problems.join('; ')}',
    );
  }
}
