import 'dart:math' as math;

/// Sun's apparent altitude at the horizon for sunrise/sunset (refraction plus
/// the solar disc radius), in degrees. Standard value used by NOAA.
const double sunriseSunsetElevationDegrees = -0.833;

/// NOAA solar position algorithm (Meeus, as in the NOAA solar calculator):
/// the sun's elevation above the horizon in degrees at [instant] for a
/// location at [latitude]/[longitude] (degrees, east positive).
///
/// Pure local computation: no network, no clock. Returns NaN for non-finite
/// or out-of-range input.
double solarElevationDegrees(
  DateTime instant,
  double latitude,
  double longitude,
) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    return double.nan;
  }
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;

  final utc = instant.toUtc();
  final jd = utc.millisecondsSinceEpoch / 86400000 + 2440587.5;
  final t = (jd - 2451545) / 36525;

  final l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360;
  final m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  final e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  final mRad = rad(m);
  final c =
      math.sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * mRad) * (0.019993 - 0.000101 * t) +
      math.sin(3 * mRad) * 0.000289;
  final omega = rad(125.04 - 1934.136 * t);
  final lambda = rad(l0 + c - 0.00569 - 0.00478 * math.sin(omega));
  final eps0 =
      23 +
      (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
  final eps = rad(eps0 + 0.00256 * math.cos(omega));
  final declination = math.asin(math.sin(eps) * math.sin(lambda));

  final y = math.pow(math.tan(eps / 2), 2).toDouble();
  final l0Rad = rad(l0);
  final equationOfTimeMinutes =
      4 *
      deg(
        y * math.sin(2 * l0Rad) -
            2 * e * math.sin(mRad) +
            4 * e * y * math.sin(mRad) * math.cos(2 * l0Rad) -
            0.5 * y * y * math.sin(4 * l0Rad) -
            1.25 * e * e * math.sin(2 * mRad),
      );

  final minutesUtc =
      utc.hour * 60 + utc.minute + utc.second / 60 + utc.millisecond / 60000;
  final trueSolarMinutes =
      (minutesUtc + equationOfTimeMinutes + 4 * longitude) % 1440;
  final hourAngle = rad(trueSolarMinutes / 4 - 180);
  final lat = rad(latitude);
  final sinElevation =
      math.sin(lat) * math.sin(declination) +
      math.cos(lat) * math.cos(declination) * math.cos(hourAngle);
  return deg(math.asin(sinElevation.clamp(-1.0, 1.0)));
}

/// True when the sun is below the sunrise/sunset horizon at [instant]
/// (after sunset, before sunrise). Polar day/night follow the sun's actual
/// elevation. Invalid coordinates return false (treated as daytime) rather
/// than throwing; callers validate coordinates before routing.
bool isNightAt(DateTime instant, double latitude, double longitude) {
  final elevation = solarElevationDegrees(instant, latitude, longitude);
  return elevation.isFinite && elevation < sunriseSunsetElevationDegrees;
}
