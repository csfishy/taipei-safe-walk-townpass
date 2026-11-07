import '../models/safe_walk_models.dart';

export '../models/safe_walk_models.dart';
export 'cancellation.dart';
export 'schema_validator.dart'
    show
        ContractFormatException,
        ContractViolation,
        validateContract,
        safeWalkContractNames;
export 'semantics.dart';

/// A typed parser descriptor. Callers never cast a generic JSON map to a model.
final class ContractType<T extends SafeWalkModel> {
  const ContractType(this.name, this._decode);
  final String name;
  final T Function(Object?) _decode;

  T parse(Object? value) => _decode(value);
}

abstract final class SafeWalkContracts {
  static final coordinates = ContractType('Coordinates', Coordinates.fromJson);
  static final position = ContractType('Position', Position.fromJson);
  static final locationResult = ContractType(
    'LocationResult',
    LocationResult.fromJson,
  );
  static final sourceMetadata = ContractType(
    'SourceMetadata',
    SourceMetadata.fromJson,
  );
  static final recognition = ContractType('Recognition', Recognition.fromJson);
  static final assistancePoint = ContractType(
    'AssistancePoint',
    AssistancePoint.fromJson,
  );
  static final areaStatistics = ContractType(
    'AreaStatistics',
    AreaStatistics.fromJson,
  );
  static final routeRequest = ContractType(
    'RouteRequest',
    RouteRequest.fromJson,
  );
  static final lineString = ContractType('LineString', LineString.fromJson);
  static final routeCandidate = ContractType(
    'RouteCandidate',
    RouteCandidate.fromJson,
  );
  static final routeResult = ContractType('RouteResult', RouteResult.fromJson);
  static final incidentSummary = ContractType(
    'IncidentSummary',
    IncidentSummary.fromJson,
  );
  static final emergencyActionResult = ContractType(
    'EmergencyActionResult',
    EmergencyActionResult.fromJson,
  );
  static final companionScenario = ContractType(
    'CompanionScenario',
    CompanionScenario.fromJson,
  );
  static final companionEvent = ContractType(
    'CompanionEvent',
    CompanionEvent.fromJson,
  );
  static final appEvent = ContractType('AppEvent', AppEvent.fromJson);

  static final List<ContractType<SafeWalkModel>> all = List.unmodifiable([
    coordinates,
    position,
    locationResult,
    sourceMetadata,
    recognition,
    assistancePoint,
    areaStatistics,
    routeRequest,
    lineString,
    routeCandidate,
    routeResult,
    incidentSummary,
    emergencyActionResult,
    companionScenario,
    companionEvent,
    appEvent,
  ]);
}

T parseContract<T extends SafeWalkModel>(ContractType<T> type, Object? value) =>
    type.parse(value);

/// Dynamic fixture/import boundary. Product code should prefer typed descriptors.
SafeWalkModel parseContractByName(String name, Object? value) =>
    SafeWalkContracts.all
        .firstWhere(
          (type) => type.name == name,
          orElse: () => throw ArgumentError('Unknown Safe Walk contract name'),
        )
        .parse(value);
