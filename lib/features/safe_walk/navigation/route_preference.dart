import 'package:town_pass/features/safe_walk/navigation/day_night.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// What the walker prefers from the route in the current light: shaded
/// streets by day, lit streets at night.
enum RoutePreferenceKind { shade, lit }

/// Chooses the preference from the start position and the time, locally.
RoutePreferenceKind routePreferenceAt(sw.Coordinates origin, DateTime now) =>
    isNightAt(now, origin.lat, origin.lng)
    ? RoutePreferenceKind.lit
    : RoutePreferenceKind.shade;

/// Which preference was requested and whether the route provider really
/// applied it. `applied: false` is a disclosed limit, never hidden.
final class RoutePreference {
  const RoutePreference({required this.kind, required this.applied});

  final RoutePreferenceKind kind;
  final bool applied;

  /// Traditional Chinese disclosure shown with the route warnings.
  String get disclosure => switch ((kind, applied)) {
    (RoutePreferenceKind.lit, true) =>
      '夜間已優先選擇有路燈的路段（依 OpenStreetMap 路燈標記，標記不完整，不保證照明）',
    (RoutePreferenceKind.lit, false) => '夜間偏好路燈路線：這條路線沒有套用路燈偏好，不保證沿途有照明',
    (RoutePreferenceKind.shade, true) => '白天已優先選擇有樹蔭的路段（不保證實際遮蔭）',
    (RoutePreferenceKind.shade, false) => '白天偏好樹蔭路線：尚無可驗證的樹蔭資料，這條路線沒有套用樹蔭偏好',
  };
}
