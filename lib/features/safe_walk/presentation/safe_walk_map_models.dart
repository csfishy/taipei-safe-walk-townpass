// View models and coordinate helpers for the Safe Walk map.
// Map reports and SMS drafts are presentation models; shared payloads remain canonical.
import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Latitude and longitude used by the map presentation.
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

double metersBetween(LatLng a, LatLng b) {
  final dx = (a.lng - b.lng) * 111320 * math.cos(a.lat * math.pi / 180);
  final dy = (a.lat - b.lat) * 110540;
  return math.sqrt(dx * dx + dy * dy);
}

int routeMeters(List<LatLng> path) {
  var sum = 0.0;
  for (var i = 1; i < path.length; i++) {
    sum += metersBetween(path[i - 1], path[i]);
  }
  return sum.round();
}

/// 路線（GeoJSON 座標）是否有一段離 [at] 不到 [radius] 公尺（點到線段距離）。
bool routePassesWithin(
  List<sw.GeoJsonCoordinate> line,
  LatLng at,
  double radius,
) {
  final k = 111320 * math.cos(at.lat * math.pi / 180);
  for (var i = 0; i + 1 < line.length; i++) {
    final ax = (line[i].longitude - at.lng) * k,
        ay = (line[i].latitude - at.lat) * 110540;
    final bx = (line[i + 1].longitude - at.lng) * k,
        by = (line[i + 1].latitude - at.lat) * 110540;
    final dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
    final t = len == 0 ? 0.0 : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    if (x * x + y * y < radius * radius) return true;
  }
  return false;
}

/// 相對於前進方向的轉彎（像導航 App 的「左轉／右轉」，不是東西南北）。
enum StepTurn {
  start,
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
}

const stepTurnLabel = {
  StepTurn.start: '出發，沿路直走',
  StepTurn.straight: '繼續直走',
  StepTurn.slightLeft: '稍微靠左',
  StepTurn.left: '左轉',
  StepTurn.sharpLeft: '向左急轉',
  StepTurn.slightRight: '稍微靠右',
  StepTurn.right: '右轉',
  StepTurn.sharpRight: '向右急轉',
  StepTurn.uTurn: '迴轉',
};

class RouteStep {
  RouteStep(this.turn, this.meters);
  final StepTurn turn;
  int meters;
}

double _bearing(LatLng a, LatLng b) {
  final dLng = (b.lng - a.lng) * math.cos(a.lat * math.pi / 180);
  return (math.atan2(dLng, b.lat - a.lat) * 180 / math.pi + 360) % 360;
}

/// 把路線轉成白話步驟：每次方向改變超過 25° 算一個轉彎，左右依前進方向判斷；
/// 距離四捨五入到 10 公尺。路名要等路線服務提供逐路口指示才有。
List<RouteStep> routeSteps(List<LatLng> path) {
  final steps = <RouteStep>[];
  double? heading;
  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1], b = path[i];
    final m = metersBetween(a, b).round();
    if (m < 3) continue;
    final h = _bearing(a, b);
    if (heading == null) {
      steps.add(RouteStep(StepTurn.start, m));
    } else {
      final d = ((h - heading + 540) % 360) - 180; // -180..180，正值＝往右
      final a2 = d.abs();
      final turn = a2 < 25
          ? null
          : a2 >= 155
          ? StepTurn.uTurn
          : d < 0
          ? (a2 < 60
                ? StepTurn.slightLeft
                : a2 < 120
                ? StepTurn.left
                : StepTurn.sharpLeft)
          : (a2 < 60
                ? StepTurn.slightRight
                : a2 < 120
                ? StepTurn.right
                : StepTurn.sharpRight);
      if (turn == null || m < 8 && steps.last.meters < 8) {
        steps.last.meters += m;
      } else {
        steps.add(RouteStep(turn, m));
      }
    }
    heading = h;
  }
  for (final s in steps) {
    s.meters = math.max(10, (s.meters / 10).round() * 10);
  }
  return steps;
}

// ───────── 常用目的地（提案型別；只存在記憶體，不保存住家地址） ─────────

class SavedPlace {
  const SavedPlace(this.id, this.label, this.at);
  final String id;
  final String label;

  /// An unset Live home has no location; it cannot produce a route or marker.
  final LatLng? at;
  bool get isHome => id == 'home';
}

enum AnomalyCategory { fight, suspicious, lighting, construction, other }

const anomalyCategoryLabel = {
  AnomalyCategory.fight: '打架衝突',
  AnomalyCategory.suspicious: '可疑人士',
  AnomalyCategory.lighting: '照明不足',
  AnomalyCategory.construction: '道路施工',
  AnomalyCategory.other: '其他狀況',
};

/// 回報可待確認、多人回報或由使用者解除；不宣稱已轉送警方。
enum AnomalyStatus { pending, multiReported, cleared }

const anomalyStatusLabel = {
  AnomalyStatus.pending: '待確認',
  AnomalyStatus.multiReported: '多人回報',
  AnomalyStatus.cleared: '已解除',
};

/// 犯罪紀錄區：官方犯罪紀錄的參考位置（地址或捷運出口比對，非精確案發地點）。
typedef CrimeSpot = ({String id, LatLng at, String label});

/// 系統內回報的避讓半徑（公尺），與路線規劃一致。
const reportAvoidRadiusMeters = 50.0;

class Anomaly {
  Anomaly({
    required this.id,
    required this.category,
    required this.at,
    required this.firstReportedAt,
    required this.reportCount,
    required this.status,
    List<String>? updates,
    this.mode = sw.DataMode.live,
  }) : updates = updates ?? [];
  final String id;
  final AnomalyCategory category;
  final LatLng at;
  final DateTime firstReportedAt;
  int reportCount;
  AnomalyStatus status;
  final List<String> updates;
  final sw.DataMode mode;
}

abstract final class SmsDraftTemplate {
  static const String? recipient = null;
  static const recipientNote = '';
  static String format({
    required String time,
    required sw.Position? position,
    required String situation,
    required String? nearbyPointName,
  }) {
    final coords = position == null
        ? '尚未取得'
        : '${position.coordinates.lat}, ${position.coordinates.lng}';
    final accuracy = position?.accuracyMeters == null
        ? '未提供'
        : '${position!.accuracyMeters!.round()} 公尺';
    return '時間：$time；GPS 座標：$coords；精度：$accuracy；情況：$situation；附近據點：${nearbyPointName ?? '尚未提供'}。';
  }
}
