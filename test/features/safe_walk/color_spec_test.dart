import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/util/tp_colors.dart';

double _luminance(Color color) {
  double linear(double channel) => channel <= .04045
      ? channel / 12.92
      : math.pow((channel + .055) / 1.055, 2.4).toDouble();
  return .2126 * linear(color.r) +
      .7152 * linear(color.g) +
      .0722 * linear(color.b);
}

double _contrast(Color first, Color second) {
  final a = _luminance(first);
  final b = _luminance(second);
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  test('official primary500 requires dark text, not white labels', () {
    expect(_contrast(TPColors.white, TPColors.primary500), lessThan(3));
    expect(
      _contrast(TPColors.grayscale900, TPColors.primary500),
      greaterThanOrEqualTo(4.5),
    );
  });
  test('deep primary and emergency red600 support normal white text', () {
    expect(
      _contrast(TPColors.white, TPColors.primary700),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(TPColors.white, TPColors.red600),
      greaterThanOrEqualTo(4.5),
    );
    expect(_contrast(TPColors.white, TPColors.red500), lessThan(4.5));
  });
  test(
    'official neutral and secondary informational pairs support normal text',
    () {
      expect(
        _contrast(TPColors.grayscale900, TPColors.white),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(TPColors.grayscale900, TPColors.grayscale50),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(TPColors.grayscale700, TPColors.white),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(TPColors.secondary800, TPColors.secondary50),
        greaterThanOrEqualTo(4.5),
      );
    },
  );
}
