import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/nearby_help.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

sw.AssistancePoint store(
  String id, {
  double lat = 25.001,
  String kind = 'public_facility',
  String availability = 'unknown',
}) => sw.AssistancePoint.fromJson(
  (jsonDecode(
      File('test/fixtures/safe_walk/valid/03-AssistancePoint.json')
          .readAsStringSync(),
    ) as Map).cast<String, Object?>()
    ..['id'] = id
    ..['kind'] = kind
    ..['coordinates'] = {'lat': lat, 'lng': 121.501}
    ..['availability'] = availability
    ..['availabilityCheckedAt'] = availability == 'unknown'
        ? null
        : '2026-11-08T00:00:00Z',
);

void main() {
  test('picks the nearest open places, drops closed, at most one unknown', () {
    final origin = sw.Coordinates(lat: 25.0, lng: 121.501);
    final picked = pickNearbyCandidates(origin, [
      store(
        'closed',
        lat: 25.0005,
        kind: 'convenience_store',
        availability: 'closed',
      ),
      store('unknown-1', lat: 25.0010, kind: 'police'),
      store('unknown-2', lat: 25.0011, kind: 'convenience_store'),
      store(
        'open-1',
        lat: 25.0020,
        kind: 'convenience_store',
        availability: 'open',
      ),
      store('open-2', lat: 25.0030, kind: 'police', availability: 'open'),
      store(
        'open-3',
        lat: 25.0040,
        kind: 'convenience_store',
        availability: 'open',
      ),
      store('other-kind', lat: 25.0001, availability: 'open'),
    ], count: 3);
    expect(picked.map((p) => p.id), ['unknown-1', 'open-1', 'open-2']);
  });
}
