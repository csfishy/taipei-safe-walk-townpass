import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_warning/crime_warning_repository.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_warning/get_connect_crime_warning_fetcher.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_warning/reviewed_taipei_crime_geography.dart';
import 'package:town_pass/features/safe_walk/shared/models/crime_warning.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  test(
    'real primary provider reads official metadata and UTF-8 CSV without location',
    () async {
      // The default test binding intentionally denies HTTP. This opt-in scope
      // restores normal TLS-verified HTTP, not an accept-all certificate client.
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      try {
        final repository = OfficialCrimeWarningRepository(
          fetchText: getConnectCrimeWarningTextFetcher,
          resolveGeometry: createVerifiedTaipeiCrimeGeography().call,
        );
        final snapshot = await repository.getWarnings(mode: sw.DataMode.live);
        expect(snapshot.records, isNotEmpty);
        expect(snapshot.isComplete, isTrue);
        expect(
          snapshot.status,
          anyOf(CrimeWarningDataStatus.ready, CrimeWarningDataStatus.stale),
        );
        expect(
          snapshot.records.every((record) => record.mode == sw.DataMode.live),
          isTrue,
        );
        // No user coordinates or record location text is written to the log.
        // ignore: avoid_print
        print(
          'Official crime source: ${snapshot.records.length} rows, '
          '${snapshot.zones.length} mapped, ${snapshot.unlocatedRecordCount} unlocated, '
          '${snapshot.status.name}',
        );
      } finally {
        HttpOverrides.global = previous;
      }
    },
    skip: Platform.environment['SAFE_WALK_CRIME_LIVE'] == '1' ? false : 'set SAFE_WALK_CRIME_LIVE=1 for the official public-source provider smoke test',
    timeout: const Timeout(Duration(seconds: 150)),
  );
}
