// GENERATED from schemas/safe_walk/v1/contracts.schema.json. DO NOT EDIT.
// Runtime validation is mandatory; constructors and fromJson both validate.
import '../contracts/schema_validator.dart';

/// GeoJSON wire order is [longitude, latitude], unlike named lat/lng objects.
typedef GeoJsonCoordinate = ({double longitude, double latitude});

abstract class SafeWalkModel {
  const SafeWalkModel._(this._json);
  final Map<String, Object?> _json;
  Map<String, Object?> toJson() => copyJsonObject(_json);
}

GeoJsonCoordinate _geoJsonCoordinate(Object? value) {
  final tuple = value as List<Object?>;
  return (
    longitude: (tuple[0] as num).toDouble(),
    latitude: (tuple[1] as num).toDouble(),
  );
}

enum PositionSource {
  gps("gps"),
  manual("manual"),
  mock("mock");

  const PositionSource(this.wireValue);
  final String wireValue;
  static PositionSource fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown PositionSource wire value'),
  );
}

enum LocationFailureStatus {
  denied("denied"),
  timeout("timeout"),
  unavailable("unavailable"),
  unsupported("unsupported");

  const LocationFailureStatus(this.wireValue);
  final String wireValue;
  static LocationFailureStatus fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown LocationFailureStatus wire value'),
  );
}

enum DataMode {
  mock("mock"),
  live("live");

  const DataMode(this.wireValue);
  final String wireValue;
  static DataMode fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown DataMode wire value'),
  );
}

enum UnconfirmedRecognitionStatus {
  unconfirmed("unconfirmed"),
  notApplicable("not_applicable");

  const UnconfirmedRecognitionStatus(this.wireValue);
  final String wireValue;
  static UnconfirmedRecognitionStatus fromWire(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown UnconfirmedRecognitionStatus wire value',
        ),
      );
}

enum AssistancePointKind {
  police("police"),
  partnerStore("partner_store"),
  convenienceStore("convenience_store"),
  publicFacility("public_facility");

  const AssistancePointKind(this.wireValue);
  final String wireValue;
  static AssistancePointKind fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown AssistancePointKind wire value'),
  );
}

enum OpeningStatus {
  open("open"),
  closed("closed"),
  unknown("unknown");

  const OpeningStatus(this.wireValue);
  final String wireValue;
  static OpeningStatus fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown OpeningStatus wire value'),
  );
}

enum AssistanceCapability {
  contactAssistance("contact_assistance"),
  indoorWaiting("indoor_waiting"),
  unknown("unknown");

  const AssistanceCapability(this.wireValue);
  final String wireValue;
  static AssistanceCapability fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown AssistanceCapability wire value'),
  );
}

enum StatisticsAggregation {
  month("month"),
  year("year");

  const StatisticsAggregation(this.wireValue);
  final String wireValue;
  static StatisticsAggregation fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown StatisticsAggregation wire value'),
  );
}

enum RouteKind {
  direct("direct"),
  viaAssistance("via_assistance");

  const RouteKind(this.wireValue);
  final String wireValue;
  static RouteKind fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown RouteKind wire value'),
  );
}

enum RouteFailureStatus {
  noRoute("no_route"),
  providerUnavailable("provider_unavailable"),
  invalidInput("invalid_input"),
  cancelled("cancelled");

  const RouteFailureStatus(this.wireValue);
  final String wireValue;
  static RouteFailureStatus fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown RouteFailureStatus wire value'),
  );
}

enum IncidentCategory {
  personalThreat("personal_threat"),
  medical("medical"),
  fire("fire"),
  other("other");

  const IncidentCategory(this.wireValue);
  final String wireValue;
  static IncidentCategory fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown IncidentCategory wire value'),
  );
}

enum IncidentTransferState {
  localOnly("local_only"),
  handoffRequested("handoff_requested");

  const IncidentTransferState(this.wireValue);
  final String wireValue;
  static IncidentTransferState fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown IncidentTransferState wire value'),
  );
}

enum EmergencyChannel {
  police("110"),
  fire("119"),
  trustedContact("trusted_contact");

  const EmergencyChannel(this.wireValue);
  final String wireValue;
  static EmergencyChannel fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown EmergencyChannel wire value'),
  );
}

enum EmergencyAction {
  dialLinkActivated("dial_link_activated"),
  shareSheetRequested("share_sheet_requested"),
  cancelled("cancelled"),
  notConfigured("not_configured"),
  failed("failed");

  const EmergencyAction(this.wireValue);
  final String wireValue;
  static EmergencyAction fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown EmergencyAction wire value'),
  );
}

enum CompanionState {
  idle("idle"),
  playing("playing"),
  paused("paused"),
  ended("ended"),
  error("error");

  const CompanionState(this.wireValue);
  final String wireValue;
  static CompanionState fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown CompanionState wire value'),
  );
}

enum CompanionReason {
  user("user"),
  emergency("emergency"),
  unmount("unmount"),
  audioError("audio_error"),
  notConfigured("not_configured"),
  visibilityHidden("visibility_hidden");

  const CompanionReason(this.wireValue);
  final String wireValue;
  static CompanionReason fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown CompanionReason wire value'),
  );
}

enum EmergencyOpenedReason {
  user("user"),
  threat("threat");

  const EmergencyOpenedReason(this.wireValue);
  final String wireValue;
  static EmergencyOpenedReason fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown EmergencyOpenedReason wire value'),
  );
}

enum CompanionStopReason {
  user("user"),
  emergency("emergency"),
  unmount("unmount"),
  visibilityHidden("visibility_hidden");

  const CompanionStopReason(this.wireValue);
  final String wireValue;
  static CompanionStopReason fromWire(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown CompanionStopReason wire value'),
  );
}

final class Coordinates extends SafeWalkModel {
  Coordinates._(super.json) : super._();
  factory Coordinates.fromJson(Object? value) =>
      Coordinates._(validatedContractObjectAt("#/\$defs/Coordinates", value));
  factory Coordinates({required double lat, required double lng}) =>
      Coordinates.fromJson({'lat': lat, 'lng': lng});
  double get lat => (_json['lat'] as num).toDouble();
  double get lng => (_json['lng'] as num).toDouble();
}

final class Position extends SafeWalkModel {
  Position._(super.json) : super._();
  factory Position.fromJson(Object? value) =>
      Position._(validatedContractObjectAt("#/\$defs/Position", value));
  factory Position({
    required Coordinates coordinates,
    required PositionSource source,
    required double? accuracyMeters,
    required String? observedAt,
  }) => Position.fromJson({
    'schemaVersion': "1.0.0",
    'coordinates': coordinates.toJson(),
    'source': source.wireValue,
    'accuracyMeters': accuracyMeters,
    'observedAt': observedAt,
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  Coordinates get coordinates => Coordinates.fromJson(_json['coordinates']);
  PositionSource get source =>
      PositionSource.fromWire(_json['source'] as String);
  double? get accuracyMeters => _json['accuracyMeters'] == null
      ? null
      : (_json['accuracyMeters'] as num).toDouble();
  String? get observedAt =>
      _json['observedAt'] == null ? null : _json['observedAt'] as String;
}

sealed class LocationResult extends SafeWalkModel {
  LocationResult._(super.json) : super._();
  factory LocationResult.fromJson(Object? value) {
    final json = validatedContractObject('LocationResult', value);
    return switch (json['status']) {
      "ok" => LocationSuccess._(json),
      "denied" ||
      "timeout" ||
      "unavailable" ||
      "unsupported" => LocationFailure._(json),
      _ => throw StateError('Validated LocationResult has no variant'),
    };
  }
}

final class LocationSuccess extends LocationResult {
  LocationSuccess._(super.json) : super._();
  factory LocationSuccess.fromJson(Object? value) => LocationSuccess._(
    validatedContractObjectAt("#/\$defs/LocationResult/oneOf/0", value),
  );
  factory LocationSuccess({required Position position}) =>
      LocationSuccess.fromJson({'status': "ok", 'position': position.toJson()});
  String get status => _json['status'] as String;
  Position get position => Position.fromJson(_json['position']);
}

final class LocationFailure extends LocationResult {
  LocationFailure._(super.json) : super._();
  factory LocationFailure.fromJson(Object? value) => LocationFailure._(
    validatedContractObjectAt("#/\$defs/LocationResult/oneOf/1", value),
  );
  factory LocationFailure({
    required LocationFailureStatus status,
    required String message,
  }) => LocationFailure.fromJson({
    'status': status.wireValue,
    'message': message,
  });
  LocationFailureStatus get status =>
      LocationFailureStatus.fromWire(_json['status'] as String);
  String get message => _json['message'] as String;
}

final class SourceMetadata extends SafeWalkModel {
  SourceMetadata._(super.json) : super._();
  factory SourceMetadata.fromJson(Object? value) => SourceMetadata._(
    validatedContractObjectAt("#/\$defs/SourceMetadata", value),
  );
  factory SourceMetadata({
    required String datasetId,
    required String title,
    required DataMode dataMode,
    required String? sourceUrl,
    required String retrievedAt,
    required String? dataUpdatedAt,
    required String? license,
    required String coverage,
    required List<String> limitations,
  }) => SourceMetadata.fromJson({
    'datasetId': datasetId,
    'title': title,
    'dataMode': dataMode.wireValue,
    'sourceUrl': sourceUrl,
    'retrievedAt': retrievedAt,
    'dataUpdatedAt': dataUpdatedAt,
    'license': license,
    'coverage': coverage,
    'limitations': limitations.map((item) => item).toList(growable: false),
  });
  String get datasetId => _json['datasetId'] as String;
  String get title => _json['title'] as String;
  DataMode get dataMode => DataMode.fromWire(_json['dataMode'] as String);
  String? get sourceUrl =>
      _json['sourceUrl'] == null ? null : _json['sourceUrl'] as String;
  String get retrievedAt => _json['retrievedAt'] as String;
  String? get dataUpdatedAt =>
      _json['dataUpdatedAt'] == null ? null : _json['dataUpdatedAt'] as String;
  String? get license =>
      _json['license'] == null ? null : _json['license'] as String;
  String get coverage => _json['coverage'] as String;
  List<String> get limitations => List<String>.unmodifiable(
    (_json['limitations'] as List<Object?>).map((item) => item as String),
  );
}

sealed class Recognition extends SafeWalkModel {
  Recognition._(super.json) : super._();
  factory Recognition.fromJson(Object? value) {
    final json = validatedContractObject('Recognition', value);
    return switch (json['status']) {
      "confirmed" => ConfirmedRecognition._(json),
      "unconfirmed" || "not_applicable" => UnconfirmedRecognition._(json),
      _ => throw StateError('Validated Recognition has no variant'),
    };
  }
}

final class ConfirmedRecognition extends Recognition {
  ConfirmedRecognition._(super.json) : super._();
  factory ConfirmedRecognition.fromJson(Object? value) =>
      ConfirmedRecognition._(
        validatedContractObjectAt("#/\$defs/Recognition/oneOf/0", value),
      );
  factory ConfirmedRecognition({
    required String evidenceUrl,
    required String checkedAt,
  }) => ConfirmedRecognition.fromJson({
    'status': "confirmed",
    'evidenceUrl': evidenceUrl,
    'checkedAt': checkedAt,
  });
  String get status => _json['status'] as String;
  String get evidenceUrl => _json['evidenceUrl'] as String;
  String get checkedAt => _json['checkedAt'] as String;
}

final class UnconfirmedRecognition extends Recognition {
  UnconfirmedRecognition._(super.json) : super._();
  factory UnconfirmedRecognition.fromJson(Object? value) =>
      UnconfirmedRecognition._(
        validatedContractObjectAt("#/\$defs/Recognition/oneOf/1", value),
      );
  factory UnconfirmedRecognition({
    required UnconfirmedRecognitionStatus status,
    required String? checkedAt,
  }) => UnconfirmedRecognition.fromJson({
    'status': status.wireValue,
    'evidenceUrl': null,
    'checkedAt': checkedAt,
  });
  UnconfirmedRecognitionStatus get status =>
      UnconfirmedRecognitionStatus.fromWire(_json['status'] as String);
  Null get evidenceUrl => null;
  String? get checkedAt =>
      _json['checkedAt'] == null ? null : _json['checkedAt'] as String;
}

final class AssistancePoint extends SafeWalkModel {
  AssistancePoint._(super.json) : super._();
  factory AssistancePoint.fromJson(Object? value) => AssistancePoint._(
    validatedContractObjectAt("#/\$defs/AssistancePoint", value),
  );
  factory AssistancePoint({
    required String id,
    required String name,
    required AssistancePointKind kind,
    required Coordinates coordinates,
    required String? address,
    required String? publicPhone,
    required Recognition recognition,
    required OpeningStatus availability,
    required String? availabilityCheckedAt,
    required List<AssistanceCapability> capabilities,
    required SourceMetadata source,
  }) => AssistancePoint.fromJson({
    'schemaVersion': "1.0.0",
    'id': id,
    'name': name,
    'kind': kind.wireValue,
    'coordinates': coordinates.toJson(),
    'address': address,
    'publicPhone': publicPhone,
    'recognition': recognition.toJson(),
    'availability': availability.wireValue,
    'availabilityCheckedAt': availabilityCheckedAt,
    'capabilities': capabilities
        .map((item) => item.wireValue)
        .toList(growable: false),
    'source': source.toJson(),
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  String get id => _json['id'] as String;
  String get name => _json['name'] as String;
  AssistancePointKind get kind =>
      AssistancePointKind.fromWire(_json['kind'] as String);
  Coordinates get coordinates => Coordinates.fromJson(_json['coordinates']);
  String? get address =>
      _json['address'] == null ? null : _json['address'] as String;
  String? get publicPhone =>
      _json['publicPhone'] == null ? null : _json['publicPhone'] as String;
  Recognition get recognition => Recognition.fromJson(_json['recognition']);
  OpeningStatus get availability =>
      OpeningStatus.fromWire(_json['availability'] as String);
  String? get availabilityCheckedAt => _json['availabilityCheckedAt'] == null
      ? null
      : _json['availabilityCheckedAt'] as String;
  List<AssistanceCapability> get capabilities =>
      List<AssistanceCapability>.unmodifiable(
        (_json['capabilities'] as List<Object?>).map(
          (item) => AssistanceCapability.fromWire(item as String),
        ),
      );
  SourceMetadata get source => SourceMetadata.fromJson(_json['source']);
}

final class AreaStatistics extends SafeWalkModel {
  AreaStatistics._(super.json) : super._();
  factory AreaStatistics.fromJson(Object? value) => AreaStatistics._(
    validatedContractObjectAt("#/\$defs/AreaStatistics", value),
  );
  factory AreaStatistics({
    required String id,
    required String district,
    required String periodStart,
    required String periodEnd,
    required StatisticsAggregation aggregation,
    required String category,
    required int caseCount,
    required int? populationDenominator,
    required double? ratePer100k,
    required SourceMetadata source,
  }) => AreaStatistics.fromJson({
    'schemaVersion': "1.0.0",
    'id': id,
    'city': "臺北市",
    'district': district,
    'geographicLevel': "district",
    'periodStart': periodStart,
    'periodEnd': periodEnd,
    'aggregation': aggregation.wireValue,
    'category': category,
    'caseCount': caseCount,
    'populationDenominator': populationDenominator,
    'ratePer100k': ratePer100k,
    'source': source.toJson(),
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  String get id => _json['id'] as String;
  String get city => _json['city'] as String;
  String get district => _json['district'] as String;
  String get geographicLevel => _json['geographicLevel'] as String;
  String get periodStart => _json['periodStart'] as String;
  String get periodEnd => _json['periodEnd'] as String;
  StatisticsAggregation get aggregation =>
      StatisticsAggregation.fromWire(_json['aggregation'] as String);
  String get category => _json['category'] as String;
  int get caseCount => (_json['caseCount'] as num).toInt();
  int? get populationDenominator => _json['populationDenominator'] == null
      ? null
      : (_json['populationDenominator'] as num).toInt();
  double? get ratePer100k => _json['ratePer100k'] == null
      ? null
      : (_json['ratePer100k'] as num).toDouble();
  SourceMetadata get source => SourceMetadata.fromJson(_json['source']);
}

final class RouteRequest extends SafeWalkModel {
  RouteRequest._(super.json) : super._();
  factory RouteRequest.fromJson(Object? value) =>
      RouteRequest._(validatedContractObjectAt("#/\$defs/RouteRequest", value));
  factory RouteRequest({
    required String requestId,
    required DataMode mode,
    required Position origin,
    required Coordinates destination,
    required String departAt,
    required RouteKind preference,
    required int maxExtraDistanceMeters,
    required List<String> assistancePointIds,
  }) => RouteRequest.fromJson({
    'schemaVersion': "1.0.0",
    'requestId': requestId,
    'mode': mode.wireValue,
    'origin': origin.toJson(),
    'destination': destination.toJson(),
    'departAt': departAt,
    'preference': preference.wireValue,
    'maxExtraDistanceMeters': maxExtraDistanceMeters,
    'assistancePointIds': assistancePointIds
        .map((item) => item)
        .toList(growable: false),
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  String get requestId => _json['requestId'] as String;
  DataMode get mode => DataMode.fromWire(_json['mode'] as String);
  Position get origin => Position.fromJson(_json['origin']);
  Coordinates get destination => Coordinates.fromJson(_json['destination']);
  String get departAt => _json['departAt'] as String;
  RouteKind get preference => RouteKind.fromWire(_json['preference'] as String);
  int get maxExtraDistanceMeters =>
      (_json['maxExtraDistanceMeters'] as num).toInt();
  List<String> get assistancePointIds => List<String>.unmodifiable(
    (_json['assistancePointIds'] as List<Object?>).map(
      (item) => item as String,
    ),
  );
}

final class LineString extends SafeWalkModel {
  LineString._(super.json) : super._();
  factory LineString.fromJson(Object? value) =>
      LineString._(validatedContractObjectAt("#/\$defs/LineString", value));
  factory LineString({required List<GeoJsonCoordinate> coordinates}) =>
      LineString.fromJson({
        'type': "LineString",
        'coordinates': coordinates
            .map((item) => [item.longitude, item.latitude])
            .toList(growable: false),
      });
  String get type => _json['type'] as String;
  List<GeoJsonCoordinate> get coordinates =>
      List<GeoJsonCoordinate>.unmodifiable(
        (_json['coordinates'] as List<Object?>).map(
          (item) => _geoJsonCoordinate(item),
        ),
      );
}

final class RouteCandidate extends SafeWalkModel {
  RouteCandidate._(super.json) : super._();
  factory RouteCandidate.fromJson(Object? value) => RouteCandidate._(
    validatedContractObjectAt("#/\$defs/RouteCandidate", value),
  );
  factory RouteCandidate({
    required String id,
    required RouteKind kind,
    required LineString geometry,
    required double distanceMeters,
    required double? durationSeconds,
    required List<String> viaPointIds,
    required String provider,
    required bool walkingNetworkVerified,
    required List<String> explanations,
    required List<String> warnings,
  }) => RouteCandidate.fromJson({
    'id': id,
    'kind': kind.wireValue,
    'geometry': geometry.toJson(),
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'viaPointIds': viaPointIds.map((item) => item).toList(growable: false),
    'provider': provider,
    'walkingNetworkVerified': walkingNetworkVerified,
    'explanations': explanations.map((item) => item).toList(growable: false),
    'warnings': warnings.map((item) => item).toList(growable: false),
  });
  String get id => _json['id'] as String;
  RouteKind get kind => RouteKind.fromWire(_json['kind'] as String);
  LineString get geometry => LineString.fromJson(_json['geometry']);
  double get distanceMeters => (_json['distanceMeters'] as num).toDouble();
  double? get durationSeconds => _json['durationSeconds'] == null
      ? null
      : (_json['durationSeconds'] as num).toDouble();
  List<String> get viaPointIds => List<String>.unmodifiable(
    (_json['viaPointIds'] as List<Object?>).map((item) => item as String),
  );
  String get provider => _json['provider'] as String;
  bool get walkingNetworkVerified => _json['walkingNetworkVerified'] as bool;
  List<String> get explanations => List<String>.unmodifiable(
    (_json['explanations'] as List<Object?>).map((item) => item as String),
  );
  List<String> get warnings => List<String>.unmodifiable(
    (_json['warnings'] as List<Object?>).map((item) => item as String),
  );
}

sealed class RouteResult extends SafeWalkModel {
  RouteResult._(super.json) : super._();
  factory RouteResult.fromJson(Object? value) {
    final json = validatedContractObject('RouteResult', value);
    return switch (json['status']) {
      "ok" => RouteSuccess._(json),
      "no_route" ||
      "provider_unavailable" ||
      "invalid_input" ||
      "cancelled" => RouteFailure._(json),
      _ => throw StateError('Validated RouteResult has no variant'),
    };
  }
  String get schemaVersion => _json['schemaVersion'] as String;
  String get requestId => _json['requestId'] as String;
  DataMode get mode => DataMode.fromWire(_json['mode'] as String);
  String get generatedAt => _json['generatedAt'] as String;
  List<String> get warnings => List<String>.unmodifiable(
    (_json['warnings'] as List<Object?>).map((item) => item as String),
  );
}

final class RouteSuccess extends RouteResult {
  RouteSuccess._(super.json) : super._();
  factory RouteSuccess.fromJson(Object? value) => RouteSuccess._(
    validatedContractObjectAt("#/\$defs/RouteResult/oneOf/0", value),
  );
  factory RouteSuccess({
    required String requestId,
    required DataMode mode,
    required String generatedAt,
    required List<RouteCandidate> routes,
    required List<String> warnings,
  }) => RouteSuccess.fromJson({
    'schemaVersion': "1.0.0",
    'requestId': requestId,
    'mode': mode.wireValue,
    'generatedAt': generatedAt,
    'status': "ok",
    'routes': routes.map((item) => item.toJson()).toList(growable: false),
    'warnings': warnings.map((item) => item).toList(growable: false),
  });
  String get status => _json['status'] as String;
  List<RouteCandidate> get routes => List<RouteCandidate>.unmodifiable(
    (_json['routes'] as List<Object?>).map(
      (item) => RouteCandidate.fromJson(item),
    ),
  );
}

final class RouteFailure extends RouteResult {
  RouteFailure._(super.json) : super._();
  factory RouteFailure.fromJson(Object? value) => RouteFailure._(
    validatedContractObjectAt("#/\$defs/RouteResult/oneOf/1", value),
  );
  factory RouteFailure({
    required String requestId,
    required DataMode mode,
    required String generatedAt,
    required RouteFailureStatus status,
    required String reason,
    required List<String> warnings,
  }) => RouteFailure.fromJson({
    'schemaVersion': "1.0.0",
    'requestId': requestId,
    'mode': mode.wireValue,
    'generatedAt': generatedAt,
    'status': status.wireValue,
    'routes': <Object?>[],
    'reason': reason,
    'warnings': warnings.map((item) => item).toList(growable: false),
  });
  RouteFailureStatus get status =>
      RouteFailureStatus.fromWire(_json['status'] as String);
  List<Never> get routes => const <Never>[];
  String get reason => _json['reason'] as String;
}

final class IncidentSummary extends SafeWalkModel {
  IncidentSummary._(super.json) : super._();
  factory IncidentSummary.fromJson(Object? value) => IncidentSummary._(
    validatedContractObjectAt("#/\$defs/IncidentSummary", value),
  );
  factory IncidentSummary({
    required String id,
    required DataMode mode,
    required IncidentCategory category,
    required String createdAt,
    required Position? location,
    required String note,
    required bool consentToShareLocation,
    required IncidentTransferState transferState,
  }) => IncidentSummary.fromJson({
    'schemaVersion': "1.0.0",
    'id': id,
    'mode': mode.wireValue,
    'category': category.wireValue,
    'createdAt': createdAt,
    'location': location?.toJson(),
    'note': note,
    'consentToShareLocation': consentToShareLocation,
    'transferState': transferState.wireValue,
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  String get id => _json['id'] as String;
  DataMode get mode => DataMode.fromWire(_json['mode'] as String);
  IncidentCategory get category =>
      IncidentCategory.fromWire(_json['category'] as String);
  String get createdAt => _json['createdAt'] as String;
  Position? get location =>
      _json['location'] == null ? null : Position.fromJson(_json['location']);
  String get note => _json['note'] as String;
  bool get consentToShareLocation => _json['consentToShareLocation'] as bool;
  IncidentTransferState get transferState =>
      IncidentTransferState.fromWire(_json['transferState'] as String);
}

final class EmergencyActionResult extends SafeWalkModel {
  EmergencyActionResult._(super.json) : super._();
  factory EmergencyActionResult.fromJson(Object? value) =>
      EmergencyActionResult._(
        validatedContractObjectAt("#/\$defs/EmergencyActionResult", value),
      );
  factory EmergencyActionResult({
    required EmergencyChannel channel,
    required EmergencyAction action,
    required String message,
  }) => EmergencyActionResult.fromJson({
    'schemaVersion': "1.0.0",
    'channel': channel.wireValue,
    'action': action.wireValue,
    'officialReceipt': null,
    'message': message,
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  EmergencyChannel get channel =>
      EmergencyChannel.fromWire(_json['channel'] as String);
  EmergencyAction get action =>
      EmergencyAction.fromWire(_json['action'] as String);
  Null get officialReceipt => null;
  String get message => _json['message'] as String;
}

final class CompanionScenario extends SafeWalkModel {
  CompanionScenario._(super.json) : super._();
  factory CompanionScenario.fromJson(Object? value) => CompanionScenario._(
    validatedContractObjectAt("#/\$defs/CompanionScenario", value),
  );
  factory CompanionScenario({
    required String id,
    required String label,
    required List<CompanionStep> steps,
  }) => CompanionScenario.fromJson({
    'schemaVersion': "1.0.0",
    'id': id,
    'label': label,
    'disclosure': "模擬通話，未聯絡任何人",
    'steps': steps.map((item) => item.toJson()).toList(growable: false),
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  String get id => _json['id'] as String;
  String get label => _json['label'] as String;
  String get disclosure => _json['disclosure'] as String;
  List<CompanionStep> get steps => List<CompanionStep>.unmodifiable(
    (_json['steps'] as List<Object?>).map(
      (item) => CompanionStep.fromJson(item),
    ),
  );
}

final class CompanionEvent extends SafeWalkModel {
  CompanionEvent._(super.json) : super._();
  factory CompanionEvent.fromJson(Object? value) => CompanionEvent._(
    validatedContractObjectAt("#/\$defs/CompanionEvent", value),
  );
  factory CompanionEvent({
    required String scenarioId,
    required CompanionState state,
    required CompanionReason reason,
    required String occurredAt,
  }) => CompanionEvent.fromJson({
    'schemaVersion': "1.0.0",
    'scenarioId': scenarioId,
    'state': state.wireValue,
    'reason': reason.wireValue,
    'occurredAt': occurredAt,
  });
  String get schemaVersion => _json['schemaVersion'] as String;
  String get scenarioId => _json['scenarioId'] as String;
  CompanionState get state => CompanionState.fromWire(_json['state'] as String);
  CompanionReason get reason =>
      CompanionReason.fromWire(_json['reason'] as String);
  String get occurredAt => _json['occurredAt'] as String;
}

sealed class AppEvent extends SafeWalkModel {
  AppEvent._(super.json) : super._();
  factory AppEvent.fromJson(Object? value) {
    final json = validatedContractObject('AppEvent', value);
    return switch (json['type']) {
      "location.updated" => LocationUpdatedEvent._(json),
      "route.completed" => RouteCompletedEvent._(json),
      "emergency.opened" => EmergencyOpenedEvent._(json),
      "companion.changed" => CompanionChangedEvent._(json),
      _ => throw StateError('Validated AppEvent has no variant'),
    };
  }
}

final class LocationUpdatedEvent extends AppEvent {
  LocationUpdatedEvent._(super.json) : super._();
  factory LocationUpdatedEvent.fromJson(Object? value) =>
      LocationUpdatedEvent._(
        validatedContractObjectAt("#/\$defs/AppEvent/oneOf/0", value),
      );
  factory LocationUpdatedEvent({required Position payload}) =>
      LocationUpdatedEvent.fromJson({
        'type': "location.updated",
        'payload': payload.toJson(),
      });
  String get type => _json['type'] as String;
  Position get payload => Position.fromJson(_json['payload']);
}

final class RouteCompletedEvent extends AppEvent {
  RouteCompletedEvent._(super.json) : super._();
  factory RouteCompletedEvent.fromJson(Object? value) => RouteCompletedEvent._(
    validatedContractObjectAt("#/\$defs/AppEvent/oneOf/1", value),
  );
  factory RouteCompletedEvent({required RouteResult payload}) =>
      RouteCompletedEvent.fromJson({
        'type': "route.completed",
        'payload': payload.toJson(),
      });
  String get type => _json['type'] as String;
  RouteResult get payload => RouteResult.fromJson(_json['payload']);
}

final class EmergencyOpenedEvent extends AppEvent {
  EmergencyOpenedEvent._(super.json) : super._();
  factory EmergencyOpenedEvent.fromJson(Object? value) =>
      EmergencyOpenedEvent._(
        validatedContractObjectAt("#/\$defs/AppEvent/oneOf/2", value),
      );
  factory EmergencyOpenedEvent({required EmergencyOpenedPayload payload}) =>
      EmergencyOpenedEvent.fromJson({
        'type': "emergency.opened",
        'payload': payload.toJson(),
      });
  String get type => _json['type'] as String;
  EmergencyOpenedPayload get payload =>
      EmergencyOpenedPayload.fromJson(_json['payload']);
}

final class CompanionChangedEvent extends AppEvent {
  CompanionChangedEvent._(super.json) : super._();
  factory CompanionChangedEvent.fromJson(Object? value) =>
      CompanionChangedEvent._(
        validatedContractObjectAt("#/\$defs/AppEvent/oneOf/3", value),
      );
  factory CompanionChangedEvent({required CompanionEvent payload}) =>
      CompanionChangedEvent.fromJson({
        'type': "companion.changed",
        'payload': payload.toJson(),
      });
  String get type => _json['type'] as String;
  CompanionEvent get payload => CompanionEvent.fromJson(_json['payload']);
}

final class CompanionStep extends SafeWalkModel {
  CompanionStep._(super.json) : super._();
  factory CompanionStep.fromJson(Object? value) => CompanionStep._(
    validatedContractObjectAt(
      "#/\$defs/CompanionScenario/properties/steps/items",
      value,
    ),
  );
  factory CompanionStep({
    required String id,
    required String text,
    required String? audioSrc,
    required int pauseAfterMs,
  }) => CompanionStep.fromJson({
    'id': id,
    'text': text,
    'audioSrc': audioSrc,
    'pauseAfterMs': pauseAfterMs,
  });
  String get id => _json['id'] as String;
  String get text => _json['text'] as String;
  String? get audioSrc =>
      _json['audioSrc'] == null ? null : _json['audioSrc'] as String;
  int get pauseAfterMs => (_json['pauseAfterMs'] as num).toInt();
}

final class EmergencyOpenedPayload extends SafeWalkModel {
  EmergencyOpenedPayload._(super.json) : super._();
  factory EmergencyOpenedPayload.fromJson(Object? value) =>
      EmergencyOpenedPayload._(
        validatedContractObjectAt(
          "#/\$defs/AppEvent/oneOf/2/properties/payload",
          value,
        ),
      );
  factory EmergencyOpenedPayload({required EmergencyOpenedReason reason}) =>
      EmergencyOpenedPayload.fromJson({'reason': reason.wireValue});
  EmergencyOpenedReason get reason =>
      EmergencyOpenedReason.fromWire(_json['reason'] as String);
}
