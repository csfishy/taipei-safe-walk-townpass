import '../models/safe_walk_models.dart';

/// Pure ports of the original semantic checks. No I/O, storage or logging.
/// Structural validity alone never proves official recognition or road safety.
List<String> positionProblems(Position position, {DateTime? now}) {
  final errors = <String>[];
  if (position.source == PositionSource.gps &&
      (position.accuracyMeters == null || position.observedAt == null)) {
    errors.add('GPS requires accuracyMeters and observedAt');
  }
  final observedAt = position.observedAt;
  if (observedAt != null) {
    // JS Date.parse rejects leap-second text; preserve the original semantic rule.
    final parsed = RegExp(r':60(?:\.|[Z+-])').hasMatch(observedAt)
        ? null
        : DateTime.tryParse(observedAt);
    if (parsed == null) {
      errors.add('Invalid observation time');
    } else {
      final age = (now ?? DateTime.now()).difference(parsed).inMilliseconds;
      if (age < -30000) {
        errors.add('Position timestamp is in the future');
      } else if (position.source == PositionSource.gps && age > 60000) {
        errors.add('GPS fix is stale; refresh or request manual location');
      }
    }
  }
  return errors;
}

List<String> sourceProblems(SourceMetadata source) =>
    source.dataMode == DataMode.live && source.sourceUrl == null
    ? ['Live data needs a source URL']
    : [];

List<String> pointProblems(AssistancePoint point) {
  final errors = sourceProblems(point.source);
  if (point.availability != OpeningStatus.unknown &&
      point.availabilityCheckedAt == null) {
    errors.add('Opening state needs a checked time');
  }
  if (point.kind == AssistancePointKind.partnerStore &&
      point.recognition is! ConfirmedRecognition) {
    errors.add('Partner store requires recognition evidence');
  }
  if (point.source.dataMode == DataMode.mock &&
      point.recognition is ConfirmedRecognition) {
    errors.add('Mock data cannot claim official recognition');
  }
  return errors;
}

List<String> statisticsProblems(AreaStatistics statistics) {
  final errors = sourceProblems(statistics.source);
  if (statistics.periodStart.compareTo(statistics.periodEnd) > 0) {
    errors.add('Reversed statistics period');
  }
  if (statistics.ratePer100k != null &&
      statistics.populationDenominator == null) {
    errors.add('Rate needs its documented population denominator');
  }
  return errors;
}

List<String> routeProblems(
  RouteResult result, {
  List<AssistancePoint> points = const [],
}) {
  if (result is! RouteSuccess) return [];
  final errors = <String>[];
  for (final candidate in result.routes) {
    if (result.mode == DataMode.live && !candidate.walkingNetworkVerified) {
      errors.add('Live geometry must come from a verified walking provider');
    }
    if (result.mode == DataMode.live &&
        candidate.provider.toLowerCase().contains('mock')) {
      errors.add('Mock provider cannot return live routes');
    }
    if (candidate.kind == RouteKind.viaAssistance &&
        candidate.viaPointIds.isEmpty) {
      errors.add('Via-assistance route needs a referenced point');
    }
    for (final id in candidate.viaPointIds) {
      AssistancePoint? point;
      for (final item in points) {
        if (item.id == id) {
          point = item;
          break;
        }
      }
      if (point == null) {
        errors.add('Unknown point reference: $id');
      } else if (result.mode == DataMode.live) {
        if (point.source.dataMode != DataMode.live) {
          errors.add('Live route cannot reference demo points');
        }
        if (point.availability == OpeningStatus.closed) {
          errors.add('Do not recommend a closed point');
        }
        errors.addAll(pointProblems(point));
      }
    }
  }
  return errors;
}

/// Run immediately before sharing externally, not when creating a local draft.
List<String> shareProblems(IncidentSummary summary) {
  if (summary.mode == DataMode.mock) {
    return ['Demo reports must never be sent to a public service'];
  }
  if (summary.location != null && !summary.consentToShareLocation) {
    return ['Location sharing requires explicit consent'];
  }
  return [];
}
