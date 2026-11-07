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
}
