import 'dart:async';

import 'package:town_pass/features/safe_walk/safety_data/crime_warning/crime_warning_parser.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/crime_warning.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

typedef CrimeWarningTextFetcher = Future<String> Function(Uri uri);
typedef CrimeWarningGeographicResolver = CrimeWarningZone? Function(
  CrimeLocationRecord record,
);

final class CrimeWarningDataUnavailable implements Exception {
  const CrimeWarningDataUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'Crime warning unavailable: $reason';
}

abstract interface class CrimeWarningRepository {
  Future<CrimeWarningSnapshot> getWarnings({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
    bool forceRefresh = false,
  });
}

/// Public-source reads only. No location, geocoding, or mock fallback.
final class OfficialCrimeWarningRepository implements CrimeWarningRepository {
  OfficialCrimeWarningRepository({
    required this.fetchText,
    this.dataset = CrimeWarningDataset.womenChildren,
    this.resolveGeometry,
    DateTime Function()? now,
    this.cacheTtl = const Duration(hours: 6),
    this.requestTimeout = const Duration(seconds: 30),
    this.maxSourceAge = const Duration(days: 190),
  }) : _now = now ?? DateTime.now;

  final CrimeWarningTextFetcher fetchText;
  final CrimeWarningDataset dataset;
  final CrimeWarningGeographicResolver? resolveGeometry;
  final Duration cacheTtl;
  final Duration requestTimeout;
  final Duration maxSourceAge;
  final DateTime Function() _now;
  CrimeWarningSnapshot? _cached;
  int _sequence = 0;

  @override
  Future<CrimeWarningSnapshot> getWarnings({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
    bool forceRefresh = false,
  }) async {
    cancellation?.throwIfCancelled();
    if (mode != sw.DataMode.live) {
      throw const CrimeWarningDataUnavailable('Mock source not configured');
    }
    final cached = _cached;
    final now = _now().toUtc();
    if (!forceRefresh &&
        cached != null &&
        !now.isBefore(cached.retrievedAt) &&
        now.difference(cached.retrievedAt) < cacheTtl) {
      return _withFreshness(cached, now);
    }
    final sequence = ++_sequence;
    try {
      final metadata = await _read(dataset.metadataUrl, cancellation);
      cancellation?.throwIfCancelled();
      final source = CrimeWarningSourceInfo.fromMetadata(
        metadata,
        dataset: dataset,
        retrievedAt: now,
      );
      final csv = await _read(dataset.csvUrl, cancellation);
      cancellation?.throwIfCancelled();
      final parsed = parseCrimeWarningCsv(csv, source: source);
      final zones = <CrimeWarningZone>[];
      final warnings = <String>[];
      for (final record in parsed.records) {
        cancellation?.throwIfCancelled();
        final zone = resolveGeometry?.call(record);
        if (zone != null) {
          if (!identical(zone.record, record)) {
            throw const CrimeWarningFormatException(
              'resolver changed source record',
            );
          }
          zones.add(zone);
        }
      }
      final complete =
          parsed.rejected.isEmpty &&
          (source.declaredRows == null ||
              source.declaredRows == parsed.sourceRows);
      if (!complete) warnings.add('來源筆數或部分欄位未完整核對，不宣稱已完成避讓。');
      if (parsed.records.length > zones.length) {
        warnings.add(
          '${parsed.records.length - zones.length} 筆文字警示尚未可靠定位，不參與精確路段避讓。',
        );
      }
      final result = _withFreshness(
        CrimeWarningSnapshot(
          records: parsed.records,
          zones: zones,
          mode: mode,
          retrievedAt: now,
          status: parsed.records.isEmpty
              ? CrimeWarningDataStatus.empty
              : CrimeWarningDataStatus.ready,
          isComplete: complete,
          warnings: warnings,
        ),
        now,
      );
      cancellation?.throwIfCancelled();
      if (sequence == _sequence) _cached = result;
      return result;
    } on SafeWalkCancelledException {
      rethrow;
    } on CrimeWarningFormatException catch (error) {
      throw CrimeWarningDataUnavailable(error.message);
    } on Object catch (error) {
      throw CrimeWarningDataUnavailable(
        'source request failed (${error.runtimeType})',
      );
    }
  }

  Future<String> _read(Uri uri, SafeWalkCancellation? cancellation) async {
    cancellation?.throwIfCancelled();
    final read = fetchText(uri).timeout(requestTimeout);
    if (cancellation == null) return read;
    return Future.any([
      read,
      cancellation.whenCancelled.then<String>(
        (_) => throw const SafeWalkCancelledException(),
      ),
    ]);
  }

  CrimeWarningSnapshot _withFreshness(
    CrimeWarningSnapshot snapshot,
    DateTime now,
  ) {
    final stale = snapshot.records.any(
      (record) =>
          record.dataUpdatedAt == null ||
          record.dataUpdatedAt!.isAfter(now.add(const Duration(days: 1))) ||
          now.difference(record.dataUpdatedAt!) > maxSourceAge,
    );
    return CrimeWarningSnapshot(
      records: snapshot.records,
      zones: snapshot.zones,
      mode: snapshot.mode,
      retrievedAt: snapshot.retrievedAt,
      status: stale ? CrimeWarningDataStatus.stale : snapshot.status,
      isComplete: snapshot.isComplete,
      warnings: [
        ...snapshot.warnings.where((value) => value != '來源更新時間未知或過期；不參與避讓。'),
        if (stale) '來源更新時間未知或過期；不參與避讓。',
      ],
    );
  }
}
