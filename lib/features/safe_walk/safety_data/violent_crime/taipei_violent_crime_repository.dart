import 'dart:convert';

import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/violent_crime/violent_crime_normalizer.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Reads one URL and returns its body decoded as UTF-8 text. Throwing means
/// the source could not be read. Injected so tests and M1 control transport.
typedef ViolentCrimeTextFetcher = Future<String> Function(Uri uri);

/// The live source could not be read completely, changed format, or produced
/// no valid record. Distinct from [SafeWalkDataUnavailable] (not configured)
/// and from an empty result. The message never contains record contents.
final class ViolentCrimeSourceUnavailable implements Exception {
  const ViolentCrimeSourceUnavailable(this.message);

  final String message;

  @override
  String toString() => 'Violent-crime source unavailable: $message';
}

/// Outcome of the most recent successful import, for diagnostics.
final class ViolentCrimeImportReport {
  const ViolentCrimeImportReport({
    required this.csvUri,
    required this.sourceRows,
    required this.declaredRows,
    required this.converted,
    required this.rejected,
    required this.retrievedAt,
  });

  final Uri csvUri;
  final int sourceRows;

  /// data.taipei metadata `amount`; null when metadata could not be read.
  final int? declaredRows;
  final int converted;
  final List<ViolentCrimeRejectedRow> rejected;
  final String retrievedAt;
}

/// Live-only, in-process reader for 主計處「臺北市暴力犯罪案件按月別」. No
/// backend, no demo records, no fallback to them.
///
/// It returns the module-local [CityMonthlyCrimeStatistics], so it does not
/// implement the shared `SafetyDataRepository` (whose statistics must be
/// district-level `AreaStatistics`). M1 decides whether and how to wire it.
final class TaipeiViolentCrimeRepository {
  TaipeiViolentCrimeRepository({
    required ViolentCrimeTextFetcher fetchText,
    DateTime Function()? now,
    Duration cacheTtl = const Duration(hours: 6),
  }) : _fetchText = fetchText,
       _now = now ?? DateTime.now,
       _cacheTtl = cacheTtl;

  final ViolentCrimeTextFetcher _fetchText;
  final DateTime Function() _now;
  final Duration _cacheTtl;

  List<CityMonthlyCrimeStatistics>? _cached;
  DateTime? _loadedAt;
  Future<List<CityMonthlyCrimeStatistics>>? _inFlight;
  ViolentCrimeImportReport? _lastReport;

  /// Null until the first successful import.
  ViolentCrimeImportReport? get lastReport => _lastReport;

  static final Uri metadataUri = Uri.https(
    'data.taipei',
    '/api/frontstage/tpeod/dataset.view',
    {'id': violentCrimeDatasetId},
  );

  /// The resource is not stored on data.taipei (`has_datastore` is false);
  /// it links to the city statistics database. Used when metadata fails.
  static final Uri defaultCsvUri = Uri.parse(
    'https://tsis.dbas.gov.taipei/statis/webMain.aspx?sys=220&ymf=10601'
    '&kind=21&type=0&funid=a04003301&cycle=1&outmode=12&compmode=0'
    '&outkind=1&deflst=2&nzo=1',
  );

  static const _csvHost = 'tsis.dbas.gov.taipei';

  /// Months oldest first. [from] / [to] are inclusive `YYYY-MM` filters.
  Future<List<CityMonthlyCrimeStatistics>> getMonthlyStatistics({
    required sw.DataMode mode,
    String? from,
    String? to,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    _requireMonth('from', from);
    _requireMonth('to', to);
    if (from != null && to != null && from.compareTo(to) > 0) {
      throw ArgumentError('from must not be after to');
    }
    // There is no demo dataset for this format; mock is not configured.
    if (mode != sw.DataMode.live) throw const SafeWalkDataUnavailable();
    final records = await _records();
    // A cancelled caller receives nothing, even though the cache is filled.
    cancellation?.throwIfCancelled();
    return List<CityMonthlyCrimeStatistics>.unmodifiable(
      records.where((r) {
        final month = r.periodStart.substring(0, 7);
        return (from == null || month.compareTo(from) >= 0) &&
            (to == null || month.compareTo(to) <= 0);
      }),
    );
  }

  Future<List<CityMonthlyCrimeStatistics>> _records() {
    final cached = _cached, loadedAt = _loadedAt;
    if (cached != null &&
        loadedAt != null &&
        _now().difference(loadedAt) < _cacheTtl) {
      return Future.value(cached);
    }
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<List<CityMonthlyCrimeStatistics>> _load() async {
    final retrievedAt = _now();
    final metadata = await _fetchMetadata();
    final csvUri = metadata.csvUri ?? defaultCsvUri;
    final String csv;
    try {
      csv = await _fetchText(csvUri);
    } on Object catch (error) {
      throw ViolentCrimeSourceUnavailable(
        'GET ${csvUri.host} failed: ${error.runtimeType}',
      );
    }
    final body = csv.startsWith('﻿') ? csv.substring(1) : csv;
    if (!body.startsWith(violentCrimeCsvHeaderStart)) {
      throw const ViolentCrimeSourceUnavailable(
        'unexpected content (not the expected UTF-8 CSV)',
      );
    }
    final ViolentCrimeNormalized normalized;
    try {
      normalized = normalizeViolentCrimeCsv(
        body,
        ViolentCrimeSourceInfo(
          retrievedAt: formatTaipeiTime(retrievedAt),
          resourceLastModified: metadata.lastModified,
          licenseName: metadata.license,
        ),
      );
    } on ViolentCrimeFormatException catch (error) {
      throw ViolentCrimeSourceUnavailable(error.message);
    }
    final rejected = List<ViolentCrimeRejectedRow>.of(normalized.rejected);
    final records = <CityMonthlyCrimeStatistics>[];
    for (final record in normalized.records) {
      final problems = cityCrimeProblems(record);
      if (problems.isEmpty) {
        records.add(record);
      } else {
        rejected.add(ViolentCrimeRejectedRow(-1, problems.join('; ')));
      }
    }
    if (records.isEmpty) {
      throw const ViolentCrimeSourceUnavailable('no valid monthly record');
    }
    final result = List<CityMonthlyCrimeStatistics>.unmodifiable(records);
    _cached = result;
    _loadedAt = retrievedAt;
    _lastReport = ViolentCrimeImportReport(
      csvUri: csvUri,
      sourceRows: normalized.records.length + normalized.rejected.length,
      declaredRows: metadata.declaredRows,
      converted: result.length,
      rejected: List<ViolentCrimeRejectedRow>.unmodifiable(rejected),
      retrievedAt: formatTaipeiTime(retrievedAt),
    );
    return result;
  }

  /// CSV link, update time, licence and declared rows. Any failure leaves
  /// them unknown (null); a link outside the statistics host is ignored.
  Future<_Metadata> _fetchMetadata() async {
    try {
      final decoded = jsonDecode(await _fetchText(metadataUri));
      final payload = decoded is Map ? decoded['payload'] : null;
      if (payload is! Map) return const _Metadata();
      Map? resource;
      final resources = payload['resources'];
      if (resources is List) {
        for (final r in resources) {
          if (r is Map && r['rid'] == violentCrimeResourceId) resource = r;
        }
      }
      final url = resource?['url'];
      final modified = resource?['last_modified'];
      final amount = resource?['amount'];
      final license = payload['license_name'];
      return _Metadata(
        csvUri: url is String ? _acceptCsvUri(url) : null,
        lastModified: modified is String && modified.isNotEmpty
            ? modified
            : null,
        license: license is String && license.isNotEmpty ? license : null,
        declaredRows: amount is int ? amount : null,
      );
    } on Object {
      return const _Metadata();
    }
  }

  static Uri? _acceptCsvUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host == _csvHost
        ? uri
        : null;
  }

  static void _requireMonth(String name, String? value) {
    if (value != null &&
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'must be YYYY-MM');
    }
  }
}

final class _Metadata {
  const _Metadata({
    this.csvUri,
    this.lastModified,
    this.license,
    this.declaredRows,
  });

  final Uri? csvUri;
  final String? lastModified;
  final String? license;
  final int? declaredRows;
}
