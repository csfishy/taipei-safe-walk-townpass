import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Which way the top of the phone points, in degrees clockwise from magnetic
/// north, from the accelerometer and magnetometer (tilt-compensated, lightly
/// smoothed). Only listen while the map follows the walker; cancelling stops
/// the sensors. Platforms without the sensors deliver an error and no values.
Stream<double> watchDeviceHeading() {
  late final StreamController<double> out;
  StreamSubscription<AccelerometerEvent>? gravitySub;
  StreamSubscription<MagnetometerEvent>? fieldSub;
  List<double>? gravity;
  double? last;
  out = StreamController<double>(
    onListen: () {
      gravitySub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen((e) => gravity = [e.x, e.y, e.z], onError: out.addError);
      fieldSub =
          magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval)
              .listen((e) {
                final g = gravity;
                if (g == null) return;
                final h = headingFrom(g, [e.x, e.y, e.z]);
                if (h == null) return;
                last = last == null ? h : smoothHeading(last!, h);
                out.add(last!);
              }, onError: out.addError);
    },
    onCancel: () async {
      await gravitySub?.cancel();
      await fieldSub?.cancel();
    },
  );
  return out.stream;
}

/// Heading the walker is facing, from gravity and the magnetic field in
/// device coordinates (Android's `getRotationMatrix` convention): the top
/// edge when the phone is held flat, the back of the phone when it is held
/// upright (the top edge then points at the sky). Null in free fall or when
/// the field is parallel to gravity.
double? headingFrom(List<double> g, List<double> m) {
  var hx = m[1] * g[2] - m[2] * g[1];
  var hy = m[2] * g[0] - m[0] * g[2];
  var hz = m[0] * g[1] - m[1] * g[0];
  final hn = math.sqrt(hx * hx + hy * hy + hz * hz);
  final gn = math.sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
  if (hn < 0.1 || gn < 0.1) return null;
  hx /= hn;
  hy /= hn;
  hz /= hn;
  final ax = g[0] / gn, ay = g[1] / gn, az = g[2] / gn;
  // East = H, North = gravity × East, both in device coordinates.
  final my = az * hx - ax * hz;
  final mz = ax * hy - ay * hx;
  // Flat-ish (screen within ~60° of the sky): the top edge; else the back.
  final radians = az.abs() >= .5 ? math.atan2(hy, my) : math.atan2(-hz, -mz);
  return (radians * 180 / math.pi + 360) % 360;
}

/// Moves [from] a fraction of the shortest way towards [to] (handles 359°→1°).
double smoothHeading(double from, double to, [double k = .2]) {
  final diff = ((to - from + 540) % 360) - 180;
  return (from + k * diff + 360) % 360;
}
