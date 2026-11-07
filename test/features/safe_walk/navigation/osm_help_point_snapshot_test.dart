import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/osm_help_point_snapshot.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  final snapshot = OsmHelpPointSnapshot.parse(
    File('assets/safe_walk/osm_help_points_taipei.json').readAsStringSync(),
  );

  test('bundled snapshot covers Taipei stores and police', () {
    expect(snapshot.length, greaterThan(1000));
    expect(snapshot.license, contains('ODbL'));
  });

  test('statuses follow opening hours at lookup time; points pass checks', () {
    final tianmu = sw.Coordinates(lat: 25.1155, lng: 121.53);
    // 03:00 Taipei: day-time-only stores read as closed.
    final night = snapshot.near(tianmu, now: DateTime.utc(2026, 11, 7, 19));
    final noon = snapshot.near(tianmu, now: DateTime.utc(2026, 11, 8, 4));
    int open(List<sw.AssistancePoint> ps) =>
        ps.where((p) => p.availability == sw.OpeningStatus.open).length;
    expect(night, isNotEmpty);
    expect(open(noon), greaterThan(open(night)));
    expect(night.any((p) => p.kind == sw.AssistancePointKind.police), isTrue);
    for (final p in night) {
      expect(pointProblems(p), isEmpty, reason: p.id);
    }
  });
}
