import 'package:town_pass/features/safe_walk/safety_data/aed/aed_normalizer.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Reads one URL and returns the decoded JSON value. Throwing means the
/// source could not be read. Injected so tests and M1 control the transport.
typedef AedJsonFetcher = Future<Object?> Function(Uri uri);

/// The live AED source could not be read completely or produced no valid
/// record. Distinct from [SafeWalkDataUnavailable] (not configured) and from
/// an empty result. The message never contains record contents.
final class AedSourceUnavailable implements Exception {
  const AedSourceUnavailable(this.message);

  final String message;

  @override
  String toString() => 'AED source unavailable: $message';
}

/// Outcome of the most recent successful import, for diagnostics.
final class AedImportReport {
  const AedImportReport({
    required this.sourceRows,
    required this.converted,
    required this.rejected,
    required this.retrievedAt,
  });

  final int sourceRows;
  final int converted;
  final List<AedRejectedRow> rejected;
  final String retrievedAt;
}

/// Live-only repository for the data.taipei AED dataset (in-process; no
/// backend). Mock data stays in [MockSafetyDataRepository]; this class never
/// returns demo records and never falls back to them.
final class DataTaipeiAedRepository implements SafetyDataRepository {
  DataTaipeiAedRepository({
    required AedJsonFetcher fetchJson,
    DateTime Function()? now,
    Duration cacheTtl = const Duration(hours: 1),
    int pageSize = 1000,
    SafetyDataParser parser = const ContractSafetyDataParser(),
  }) : _fetchJson = fetchJson,
       _now = now ?? DateTime.now,
       _cacheTtl = cacheTtl,
       _pageSize = pageSize,
       _parser = parser {
    if (pageSize < 1 || pageSize > 1000) {
      throw ArgumentError.value(pageSize, 'pageSize', 'data.taipei allows 1–1000');
    }
  }

  final AedJsonFetcher _fetchJson;
  final DateTime Function() _now;
  final Duration _cacheTtl;
  final int _pageSize;
  final SafetyDataParser _parser;

  List<sw.AssistancePoint>? _cached;
  DateTime? _loadedAt;
  Future<List<sw.AssistancePoint>>? _inFlight;
  AedImportReport? _lastReport;

  /// Null until the first successful import.
  AedImportReport? get lastReport => _lastReport;

  static Uri rowsUri(int offset, int limit) => Uri.https(
    'data.taipei',
    '/api/v1/dataset/$aedResourceId',
    {'scope': 'resourceAquire', 'limit': '$limit', 'offset': '$offset'},
  );

  static final Uri metadataUri = Uri.https(
    'data.taipei',
    '/api/frontstage/tpeod/dataset.view',
    {'id': aedDatasetId},
  );

  @override
  Future<List<sw.AssistancePoint>> getAssistancePoints({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (mode != sw.DataMode.live) throw const SafeWalkDataUnavailable();
    final cached = _cached, loadedAt = _loadedAt;
    if (cached != null &&
        loadedAt != null &&
        _now().difference(loadedAt) < _cacheTtl) {
      return cached;
    }
    final load = _inFlight ??= _load().whenComplete(() => _inFlight = null);
    final points = await load;
    // A cancelled caller receives nothing, even though the cache is filled.
    cancellation?.throwIfCancelled();
    return points;
  }

  /// This source has no statistics; it is not configured for them.
  @override
  Future<List<sw.AreaStatistics>> getAreaStatistics({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    throw const SafeWalkDataUnavailable();
  }

  Future<List<sw.AssistancePoint>> _load() async {
    final retrievedAt = _now();
    final rows = await _fetchAllRows();
    final metadata = await _fetchMetadata();
    final normalized = normalizeAedRows(
      rows,
      AedSourceInfo(
        retrievedAt: formatTaipeiTime(retrievedAt),
        resourceLastModified: metadata.$1,
        licenseName: metadata.$2,
      ),
    );
    final rejected = List<AedRejectedRow>.of(normalized.rejected);
    final points = <sw.AssistancePoint>[];
    for (final json in normalized.points) {
      try {
        points.add(_parser.parseAssistancePoint(json));
      } on FormatException catch (error) {
        rejected.add(AedRejectedRow(-1, 'contract: ${error.message}'));
      }
    }
    if (rows.isNotEmpty && points.isEmpty) {
      throw const AedSourceUnavailable('no row passed the shared contract');
    }
    final result = List<sw.AssistancePoint>.unmodifiable(points);
    _cached = result;
    _loadedAt = retrievedAt;
    _lastReport = AedImportReport(
      sourceRows: rows.length,
      converted: result.length,
      rejected: List<AedRejectedRow>.unmodifiable(rejected),
      retrievedAt: formatTaipeiTime(retrievedAt),
    );
    return result;
  }

  Future<List<Map<String, Object?>>> _fetchAllRows() async {
    final rows = <Map<String, Object?>>[];
    int? expected;
    var offset = 0;
    while (true) {
      final uri = rowsUri(offset, _pageSize);
      final Object? body;
      try {
        body = await _fetchJson(uri);
      } on Object catch (error) {
        throw AedSourceUnavailable('GET ${uri.path} failed: ${error.runtimeType}');
      }
      final result = body is Map ? body['result'] : null;
      final page = result is Map ? result['results'] : null;
      final count = result is Map ? result['count'] : null;
      if (page is! List || count is! int) {
        throw const AedSourceUnavailable('unexpected data.taipei response shape');
      }
      expected = count;
      for (final row in page) {
        if (row is! Map) {
          throw const AedSourceUnavailable('a data.taipei row is not an object');
        }
        rows.add(row.cast<String, Object?>());
      }
      offset += _pageSize;
      if (page.isEmpty || rows.length >= count) break;
    }
    if (rows.length != expected) {
      throw AedSourceUnavailable(
        'incomplete read: ${rows.length} of $expected rows',
      );
    }
    return rows;
  }

  /// Update time and licence. Failure leaves both unknown (null).
  Future<(String?, String?)> _fetchMetadata() async {
    try {
      final body = await _fetchJson(metadataUri);
      final payload = body is Map ? body['payload'] : null;
      if (payload is! Map) return (null, null);
      String? modified;
      final resources = payload['resources'];
      if (resources is List) {
        for (final resource in resources) {
          if (resource is Map && resource['rid'] == aedResourceId) {
            final value = resource['last_modified'];
            modified = value is String && value.isNotEmpty ? value : null;
          }
        }
      }
      final license = payload['license_name'];
      return (modified, license is String && license.isNotEmpty ? license : null);
    } on Object {
      return (null, null);
    }
  }
}
