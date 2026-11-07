import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/opening_hours.dart';

void main() {
  // 2026-11-09 is a Monday.
  DateTime at(int day, int h, [int m = 0]) =>
      DateTime.utc(2026, 11, 8 + day, h, m);
  final mon = 1, sat = 6, sun = 7;

  test('24/7 and plain ranges', () {
    expect(openingHoursOpenAt('24/7', at(mon, 3)), isTrue);
    expect(openingHoursOpenAt('Mo-Su 10:30-22:00', at(mon, 10, 29)), isFalse);
    expect(openingHoursOpenAt('Mo-Su 10:30-22:00', at(mon, 10, 30)), isTrue);
    expect(openingHoursOpenAt('Mo-Su 10:30-22:00', at(mon, 22)), isFalse);
    expect(openingHoursOpenAt('0:00-24:00', at(sun, 23, 59)), isTrue);
  });

  test('day selectors, later rules win, off', () {
    const spec = 'Mo-Fr 07:00-23:00; Sa,Su 09:00-21:00; Su off';
    expect(openingHoursOpenAt(spec, at(mon, 8)), isTrue);
    expect(openingHoursOpenAt(spec, at(sat, 8)), isFalse);
    expect(openingHoursOpenAt(spec, at(sat, 10)), isTrue);
    expect(openingHoursOpenAt(spec, at(sun, 10)), isFalse);
    expect(openingHoursOpenAt('Fr-Mo 10:00-12:00', at(sun, 11)), isTrue);
  });

  test('overnight ranges spill into the next morning', () {
    const spec = 'Mo-Fr 18:00-02:00';
    expect(openingHoursOpenAt(spec, at(mon, 23)), isTrue);
    expect(openingHoursOpenAt(spec, at(2, 1, 30)), isTrue); // Tue after Mon
    expect(openingHoursOpenAt(spec, at(mon, 1)), isFalse); // Sun not listed
    expect(openingHoursOpenAt(spec, at(mon, 12)), isFalse);
  });

  test('unreadable syntax is unknown, never open', () {
    for (final spec in [
      '',
      'PH off',
      'Mo-Su 10:00+',
      'Jan-Mar 09:00-17:00',
      'by appointment',
      'Mo 25:00-26:00',
    ]) {
      expect(openingHoursOpenAt(spec, at(mon, 12)), isNull, reason: spec);
    }
  });

  test('must stay open for the margin', () {
    const spec = 'Mo-Su 07:00-22:00';
    expect(
      openingHoursOpenFor(spec, at(mon, 21, 20), const Duration(minutes: 30)),
      isTrue,
    );
    expect(
      openingHoursOpenFor(spec, at(mon, 21, 40), const Duration(minutes: 30)),
      isFalse,
    );
  });

  test('Taipei time is UTC+8', () {
    final t = taipeiTimeOf(DateTime.utc(2026, 11, 8, 16, 30));
    expect((t.weekday, t.hour, t.minute), (DateTime.monday, 0, 30));
  });
}
