import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
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

/// Read-only injected demo data. No files, network, storage, or live fallback.
final class MockSafetyDataRepository implements SafetyDataRepository {
  MockSafetyDataRepository({
    required Iterable<sw.AssistancePoint> assistancePoints,
    required Iterable<sw.AreaStatistics> areaStatistics,
  }) : _points = List<sw.AssistancePoint>.unmodifiable(assistancePoints),
       _statistics = List<sw.AreaStatistics>.unmodifiable(areaStatistics) {
    for (final point in _points) {
      _requireMock(point.source.dataMode);
      _requireSemantics('AssistancePoint', pointProblems(point));
    }
    for (final statistics in _statistics) {
      _requireMock(statistics.source.dataMode);
      _requireSemantics('AreaStatistics', statisticsProblems(statistics));
    }
  }

  final List<sw.AssistancePoint> _points;
  final List<sw.AreaStatistics> _statistics;

  @override
  Future<List<sw.AssistancePoint>> getAssistancePoints({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (mode != sw.DataMode.mock) throw const SafeWalkDataUnavailable();
    return _points;
  }

  @override
  Future<List<sw.AreaStatistics>> getAreaStatistics({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (mode != sw.DataMode.mock) throw const SafeWalkDataUnavailable();
    return _statistics;
  }
}

void _requireMock(sw.DataMode mode) {
  if (mode != sw.DataMode.mock) {
    throw const FormatException('Mock safety data cannot contain live records');
  }
}

void _requireSemantics(String contract, List<String> problems) {
  if (problems.isNotEmpty) {
    // Shared checks contain rule descriptions, never the rejected record.
    throw FormatException(
      'Invalid $contract semantics: ${problems.join('; ')}',
    );
  }
}
