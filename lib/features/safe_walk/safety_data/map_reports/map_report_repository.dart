import 'dart:async';
import 'dart:convert';

import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const mapReportSubmitRpcFunction = 'safe_walk_map_report_submit';
const mapReportQueryRpcFunction = 'safe_walk_map_report_query';
const mapReportResolveRpcFunction = 'safe_walk_map_report_resolve';
const mapReportCategories = {
  'fight',
  'suspicious',
  'lighting',
  'construction',
  'other',
};
const mapReportMaxDescriptionLength = 500;
const mapReportMaxLimit = 200;
const mapReportMaxOffset = 5000;

final class MapReportHttpResponse {
  const MapReportHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// M1 supplies native/web transport; no credentials or response bodies are logged.
typedef MapReportRpcTransport = Future<MapReportHttpResponse> Function(
  String function,
  Map<String, Object?> arguments, {
  SafeWalkCancellation? cancellation,
});

enum MapReportFailure {
  network,
  timeout,
  unauthorized,
  interfaceMissing,
  invalidArgument,
  conflict,
  rateLimited,
  serverUnavailable,
  invalidResponse,
}

final class MapReportException implements Exception {
  const MapReportException(this.failure, {this.statusCode});

  final MapReportFailure failure;
  final int? statusCode;

  @override
  String toString() =>
      'Map report failed: ${failure.name}'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

/// Public, user-selected map annotation, not an official incident or GPS trace.
final class MapReportRecord {
  const MapReportRecord({
    required this.id,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.reportedAt,
  });

  final String id;
  final String category;
  final double latitude;
  final double longitude;
  final String description;
  final DateTime reportedAt;
}

final class MapReportBounds {
  const MapReportBounds({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });

  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;

  void validate() {
    if (!_validCoordinate(minLat, minLng) ||
        !_validCoordinate(maxLat, maxLng) ||
        minLat > maxLat ||
        minLng > maxLng ||
        maxLat - minLat > 0.5 ||
        maxLng - minLng > 0.5) {
      throw ArgumentError('bounds must be ordered WGS84 within 0.5 degrees');
    }
  }
}

final class MapReportPage {
  const MapReportPage({
    required this.records,
    required this.totalMatching,
    required this.limit,
    required this.offset,
  });

  final List<MapReportRecord> records;
  final int totalMatching;
  final int limit;
  final int offset;

  bool get hasMore => offset + records.length < totalMatching;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool _validCoordinate(double lat, double lng) =>
    lat.isFinite &&
    lng.isFinite &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180;

bool _validDescription(String description) =>
    description.runes.length <= mapReportMaxDescriptionLength &&
    !description.contains('\u0000');

/// Live persistence only. Submit is idempotent for an unchanged request UUID
/// and payload, allowing safe retries after a lost commit acknowledgement.
/// Acknowledgement cancellation does not promise rollback of a sent write.
/// Community resolution removes only the explicitly selected report UUID.
/// There is no general update/table interface or fake-success fallback.
final class MapReportRepository {
  const MapReportRepository({required this.transport});

  final MapReportRpcTransport? transport;

  bool get isConfigured => transport != null;

  Future<MapReportRecord> submit({
    required sw.DataMode mode,
    required String requestId,
    required String category,
    required double latitude,
    required double longitude,
    String description = '',
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final normalizedDescription = description.trim();
    if (!_uuid.hasMatch(requestId) ||
        !mapReportCategories.contains(category) ||
        !_validCoordinate(latitude, longitude) ||
        !_validDescription(normalizedDescription)) {
      throw ArgumentError('Invalid map report fields');
    }
    final decoded = await _call(mode, mapReportSubmitRpcFunction, {
      'p_request_id': requestId,
      'p_category': category,
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_description': normalizedDescription,
    }, cancellation);
    try {
      final record = _parseRecord(decoded['report']);
      if (record.id.toLowerCase() != requestId.toLowerCase() ||
          record.category != category ||
          record.latitude != latitude ||
          record.longitude != longitude ||
          record.description != normalizedDescription) {
        throw const FormatException('Unmatched map report acknowledgement');
      }
      return record;
    } on FormatException {
      throw const MapReportException(MapReportFailure.invalidResponse);
    }
  }

  Future<MapReportPage> query({
    required sw.DataMode mode,
    MapReportBounds? bounds,
    int limit = mapReportMaxLimit,
    int offset = 0,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    bounds?.validate();
    if (limit < 1 ||
        limit > mapReportMaxLimit ||
        offset < 0 ||
        offset > mapReportMaxOffset) {
      throw ArgumentError('Invalid map report page');
    }
    final decoded = await _call(mode, mapReportQueryRpcFunction, {
      'p_min_lat': bounds?.minLat,
      'p_min_lng': bounds?.minLng,
      'p_max_lat': bounds?.maxLat,
      'p_max_lng': bounds?.maxLng,
      'p_limit': limit,
      'p_offset': offset,
    }, cancellation);
    try {
      final raw = decoded['records'];
      final total = decoded['totalMatching'];
      if (raw is! List ||
          raw.length > limit ||
          total is! int ||
          total < 0 ||
          decoded['limit'] != limit ||
          decoded['offset'] != offset ||
          raw.length != (total - offset).clamp(0, limit)) {
        throw const FormatException('Invalid map report page');
      }
      final ids = <String>{};
      final records = <MapReportRecord>[];
      for (final value in raw) {
        final record = _parseRecord(value);
        if (!ids.add(record.id.toLowerCase()) ||
            (bounds != null &&
                (record.latitude < bounds.minLat ||
                    record.latitude > bounds.maxLat ||
                    record.longitude < bounds.minLng ||
                    record.longitude > bounds.maxLng))) {
          throw const FormatException('Invalid map report page records');
        }
        records.add(record);
      }
      return MapReportPage(
        records: List.unmodifiable(records),
        totalMatching: total,
        limit: limit,
        offset: offset,
      );
    } on FormatException {
      throw const MapReportException(MapReportFailure.invalidResponse);
    }
  }

  /// Physically remove the selected public report. An acknowledged absent row
  /// is also success, allowing safe retry after a lost delete acknowledgement.
  /// The server retires removed IDs so an old submit cannot recreate the row.
  Future<void> resolve({
    required sw.DataMode mode,
    required String reportId,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (!_uuid.hasMatch(reportId)) {
      throw ArgumentError('Invalid map report id');
    }
    final decoded = await _call(mode, mapReportResolveRpcFunction, {
      'p_report_id': reportId,
    }, cancellation);
    final acknowledgedId = decoded['reportId'];
    if (acknowledgedId is! String ||
        acknowledgedId.toLowerCase() != reportId.toLowerCase() ||
        decoded['removed'] is! bool) {
      throw const MapReportException(MapReportFailure.invalidResponse);
    }
  }

  Future<Map<String, Object?>> _call(
    sw.DataMode mode,
    String function,
    Map<String, Object?> arguments,
    SafeWalkCancellation? cancellation,
  ) async {
    final transport = this.transport;
    if (mode != sw.DataMode.live || transport == null) {
      throw const SafeWalkDataUnavailable();
    }
    final MapReportHttpResponse response;
    try {
      final pending = transport(
        function,
        arguments,
        cancellation: cancellation,
      );
      response = await (cancellation == null
          ? pending
          : Future.any([
              pending,
              cancellation.whenCancelled.then<MapReportHttpResponse>(
                (_) => throw const SafeWalkCancelledException(),
              ),
            ]));
    } on SafeWalkCancelledException {
      rethrow;
    } on TimeoutException {
      cancellation?.throwIfCancelled();
      throw const MapReportException(MapReportFailure.timeout);
    } on Object {
      cancellation?.throwIfCancelled();
      throw const MapReportException(MapReportFailure.network);
    }
    cancellation?.throwIfCancelled();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MapReportException(
        _failureFor(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?> ||
          decoded['interfaceVersion'] != 1) {
        throw const FormatException('Invalid map report interface');
      }
      return decoded;
    } on FormatException {
      throw const MapReportException(MapReportFailure.invalidResponse);
    }
  }

  static MapReportRecord _parseRecord(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid map report');
    }
    final id = value['id'];
    final category = value['category'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final description = value['description'];
    final reportedAt = value['reportedAt'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        category is! String ||
        !mapReportCategories.contains(category) ||
        latitude is! num ||
        longitude is! num ||
        !_validCoordinate(latitude.toDouble(), longitude.toDouble()) ||
        description is! String ||
        !_validDescription(description) ||
        reportedAt is! String ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(reportedAt)) {
      throw const FormatException('Invalid map report fields');
    }
    final date = DateTime.tryParse(reportedAt);
    if (date == null) throw const FormatException('Invalid map report date');
    return MapReportRecord(
      id: id,
      category: category,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      description: description,
      reportedAt: date.toUtc(),
    );
  }

  static MapReportFailure _failureFor(int status, String body) {
    String? code;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['code'] is String) {
        code = decoded['code'] as String;
      }
    } on FormatException {
      // The response body is intentionally never exposed or logged.
    }
    if (status == 404 || code == 'PGRST202') {
      return MapReportFailure.interfaceMissing;
    }
    if (status == 401 || status == 403 || code == '42501') {
      return MapReportFailure.unauthorized;
    }
    if (code == '22023' || code == '22P02') {
      return MapReportFailure.invalidArgument;
    }
    if (status == 409 || code == '23505') return MapReportFailure.conflict;
    if (status == 429 || code == 'PT429') return MapReportFailure.rateLimited;
    if (status >= 500) return MapReportFailure.serverUnavailable;
    return MapReportFailure.invalidResponse;
  }
}
