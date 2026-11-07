import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/shared/route_instructions.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

void main() {
  test('Valhalla maneuvers read like 「XX路口X轉，沿OO路直行X公尺」', () {
    final steps = instructionsFromValhalla([
      {'type': 3, 'length': 0.144, 'begin_shape_index': 0},
      {
        'type': 10,
        'street_names': ['士東路91巷'],
        'length': 0.261,
        'begin_shape_index': 3,
      },
      {
        'type': 9,
        'street_names': ['士東路'],
        'length': 0.309,
        'begin_shape_index': 13,
      },
      {
        'type': 16,
        'street_names': ['中山北路六段'],
        'length': 0.203,
        'begin_shape_index': 24,
      },
      {
        'type': 8,
        'street_names': ['天母東路'],
        'length': 0.04,
      },
      {'type': 4, 'length': 0.0, 'begin_shape_index': 35},
    ]);
    expect(steps.map((s) => s.text), [
      '出發，直行 140 公尺',
      '在士東路91巷口右轉，沿士東路91巷直行 260 公尺',
      '在士東路口靠右，沿士東路直行 310 公尺',
      '在中山北路六段路口靠左，沿中山北路六段直行 200 公尺',
      '沿天母東路繼續直行 40 公尺',
    ]);
    expect(steps[1].shapeIndex, 3);
  });

  test('missing or malformed maneuvers give no steps', () {
    expect(instructionsFromValhalla(null), isEmpty);
    expect(
      instructionsFromValhalla([
        1,
        'x',
        {'type': 'right'},
      ]),
      isEmpty,
    );
  });

  test('progress: next instruction ahead and metres to it', () {
    // Straight north along lng 121.5, ~111 m per 0.001 degree.
    final line = [
      for (var i = 0; i <= 4; i++)
        (longitude: 121.5, latitude: 25.0 + i * 0.001),
    ];
    const steps = [
      RouteInstruction(
        turn: TurnKind.start,
        street: 'A路',
        meters: 200,
        shapeIndex: 0,
      ),
      RouteInstruction(
        turn: TurnKind.right,
        street: 'B路',
        meters: 200,
        shapeIndex: 2,
      ),
    ];
    final p = routeProgress(
      line,
      steps,
      sw.Coordinates(lat: 25.001, lng: 121.5),
    );
    expect(p.next?.street, 'B路');
    expect(p.toNextMeters, closeTo(111, 2));
    expect(p.remainingMeters, closeTo(333, 3));
    final end = routeProgress(
      line,
      steps,
      sw.Coordinates(lat: 25.003, lng: 121.5),
    );
    expect(end.next, isNull);
    expect(end.toNextMeters, closeTo(111, 2));
  });

  group('progress between route vertices', () {
    // About 222 m north, then 202 m east. The only turn starts at index 1.
    const line = [
      (longitude: 121.5, latitude: 25.0),
      (longitude: 121.5, latitude: 25.002),
      (longitude: 121.502, latitude: 25.002),
    ];
    const turn = RouteInstruction(
      turn: TurnKind.right,
      street: 'B路',
      meters: 202,
      shapeIndex: 1,
    );

    test('keeps the turn ahead after passing the segment midpoint', () {
      final progress = routeProgress(line, [
        turn,
      ], sw.Coordinates(lat: 25.0012, lng: 121.5));
      expect(progress.next, same(turn));
      expect(progress.toNextMeters, closeTo(89, 2));
      expect(progress.remainingMeters, closeTo(291, 2));
    });

    test('subtracts distance already walked within a segment', () {
      final progress = routeProgress(line, [
        turn,
      ], sw.Coordinates(lat: 25.0008, lng: 121.5));
      expect(progress.next, same(turn));
      expect(progress.toNextMeters, closeTo(133, 2));
      expect(progress.remainingMeters, closeTo(335, 2));
    });

    test('measures along the route when the fix is slightly beside it', () {
      final progress = routeProgress(line, [
        turn,
      ], sw.Coordinates(lat: 25.0008, lng: 121.5001));
      expect(progress.next, same(turn));
      expect(progress.toNextMeters, closeTo(133, 2));
      expect(progress.remainingMeters, closeTo(335, 2));
    });

    test('advances the instruction at the turn and measures the next leg', () {
      final atTurn = routeProgress(line, [
        turn,
      ], sw.Coordinates(lat: 25.002, lng: 121.5));
      expect(atTurn.next, isNull);
      expect(atTurn.toNextMeters, closeTo(202, 2));
      final afterTurn = routeProgress(line, [
        turn,
      ], sw.Coordinates(lat: 25.002, lng: 121.501));
      expect(afterTurn.next, isNull);
      expect(afterTurn.toNextMeters, closeTo(101, 2));
      expect(afterTurn.remainingMeters, closeTo(101, 2));
    });

    test('clamps progress before the start and beyond the destination', () {
      final before = routeProgress(line, [
        turn,
      ], sw.Coordinates(lat: 24.999, lng: 121.5));
      expect(before.next, same(turn));
      expect(before.toNextMeters, closeTo(222, 2));
      expect(before.remainingMeters, closeTo(424, 2));
      final after = routeProgress(line, [
        turn,
      ], sw.Coordinates(lat: 25.002, lng: 121.503));
      expect(after, (next: null, toNextMeters: 0.0, remainingMeters: 0.0));
    });

    test('duplicate vertices do not discard a turn that is still ahead', () {
      const duplicateTurn = RouteInstruction(
        turn: TurnKind.right,
        street: 'B路',
        meters: 202,
        shapeIndex: 2,
      );
      final progress = routeProgress(
        [line[0], line[0], line[1], line[1], line[2]],
        [duplicateTurn],
        sw.Coordinates(lat: 25.0012, lng: 121.5),
      );
      expect(progress.next, same(duplicateTurn));
      expect(progress.toNextMeters, closeTo(89, 2));
      expect(progress.remainingMeters, closeTo(291, 2));
    });

    test('empty, single-point and zero-length routes have no progress', () {
      for (final geometry in [
        <sw.GeoJsonCoordinate>[],
        [line[0]],
        [line[0], line[0], line[0]],
      ]) {
        expect(
          routeProgress(geometry, [
            turn,
          ], sw.Coordinates(lat: 25.1, lng: 121.5)),
          (next: null, toNextMeters: 0.0, remainingMeters: 0.0),
        );
      }
    });
  });
}
