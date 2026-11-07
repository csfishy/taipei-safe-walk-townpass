import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/device_heading.dart';

void main() {
  // Phone flat, screen up: gravity reads +z; the field points north and down.
  const flat = [0.0, 0.0, 9.8];

  test('top edge towards north, east, south, west', () {
    expect(headingFrom(flat, [0, 20, -40]), closeTo(0, 0.5));
    expect(headingFrom(flat, [-20, 0, -40]), closeTo(90, 0.5));
    expect(headingFrom(flat, [0, -20, -40]), closeTo(180, 0.5));
    expect(headingFrom(flat, [20, 0, -40]), closeTo(270, 0.5));
  });

  test('upright phone reads the way the walker faces (back of the phone)', () {
    // Upright: gravity along +y. Facing north: north is behind the screen.
    expect(headingFrom([0, 9.8, 0], [0, -40, -20]), closeTo(0, 0.5));
    // Facing east: north is to the left (-x).
    expect(headingFrom([0, 9.8, 0], [-20, -40, 0]), closeTo(90, 0.5));
  });

  test('no reading in free fall or with no field', () {
    expect(headingFrom([0, 0, 0], [0, 20, -40]), isNull);
    expect(headingFrom(flat, [0, 0, 0]), isNull);
  });

  test('smoothing takes the short way round north', () {
    expect(smoothHeading(350, 10, .5), closeTo(0, 1e-9));
    expect(smoothHeading(10, 350, .5), closeTo(0, 1e-9));
    expect(smoothHeading(90, 100, .2), closeTo(92, 1e-9));
  });
}
