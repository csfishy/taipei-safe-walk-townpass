// M3 示範資料：只供 UI 設計與展示使用，全部是人工虛構內容。
// 異常回報、模擬來電劇本、簡訊範本目前共用 Schema 沒有對應型別，這裡是「提案型別」，待 M1 納入 Schema。
import 'dart:math' as math;

import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

/// 示範地圖用的經緯度（虛構街區，非實際路網）。
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

abstract final class DemoGeo {
  static const minLat = 24.9994, maxLat = 25.0017, minLng = 121.4994, maxLng = 121.5016;
  static const start = LatLng(25.0, 121.5);
  static const home = LatLng(25.001, 121.5012);
  static const streetsLng = [121.4997, 121.5, 121.5006, 121.5012];
  static const streetsLat = [25.0, 25.0005, 25.001];

  /// 回家：繞開西側 121.5000 街上的異常回報。
  static const homeRoute = [start, LatLng(25.0, 121.5006), LatLng(25.0005, 121.5006), LatLng(25.0005, 121.5012), home];

  /// 較短但經過異常回報的路線（只畫虛線對照）。
  static const shortcutRoute = [start, LatLng(25.001, 121.5), home];

  /// shortcut: 沿街道的 L 形示範路線，不是路徑規劃；接 M2 RouteService 後改用真實 RouteResult。
  static List<LatLng> lRoute(LatLng from, LatLng to) => [from, LatLng(from.lat, to.lng), to];
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

/// 以每分鐘 70 公尺估算（示範值）。
int walkMinutes(int meters) => math.max(1, (meters / 70).round());

/// 路線（GeoJSON 座標）是否有一段離 [at] 不到 [radius] 公尺（點到線段距離）。
bool routePassesWithin(List<sw.GeoJsonCoordinate> line, LatLng at, double radius) {
  final k = 111320 * math.cos(at.lat * math.pi / 180);
  for (var i = 0; i + 1 < line.length; i++) {
    final ax = (line[i].longitude - at.lng) * k, ay = (line[i].latitude - at.lat) * 110540;
    final bx = (line[i + 1].longitude - at.lng) * k, by = (line[i + 1].latitude - at.lat) * 110540;
    final dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
    final t = len == 0 ? 0.0 : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    if (x * x + y * y < radius * radius) return true;
  }
  return false;
}

/// 相對於前進方向的轉彎（像導航 App 的「左轉／右轉」，不是東西南北）。
enum StepTurn { start, straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn }

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
          ? (a2 < 60 ? StepTurn.slightLeft : a2 < 120 ? StepTurn.left : StepTurn.sharpLeft)
          : (a2 < 60 ? StepTurn.slightRight : a2 < 120 ? StepTurn.right : StepTurn.sharpRight);
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

/// 預設常用地點（可在目的地選單編輯）。座標取自 OpenStreetMap：
/// 家＝臺北市立大學天母校區體育館，公司＝臺北市立大學天母校區（忠誠路二段 101 號）。
List<SavedPlace> demoPlaces() => const [SavedPlace('home', '家', LatLng(25.1160, 121.535083)), SavedPlace('work', '公司', LatLng(25.114604, 121.537019))];

/// 到某個常用地點的示範路線：家用繞開異常的路線，其他用沿街 L 形。
List<LatLng> placeRoute(LatLng start, SavedPlace p) => p.at == null ? const [] : p.isHome && start.lat == DemoGeo.start.lat && start.lng == DemoGeo.start.lng ? DemoGeo.homeRoute : DemoGeo.lRoute(start, p.at!);

// ───────── 求助據點（共用 AssistancePoint 型別，示範資料） ─────────

sw.SourceMetadata _demoSource() => sw.SourceMetadata(
  datasetId: 'demo-only',
  title: '安心行整理',
  dataMode: sw.DataMode.mock,
  sourceUrl: null,
  retrievedAt: '2026-11-07T11:30:00+08:00',
  dataUpdatedAt: null,
  license: null,
  coverage: '僅供參考',
  limitations: const ['不代表實際據點、通行狀況、營業時間或犯罪狀況'],
);

sw.AssistancePoint _point(String id, String name, sw.AssistancePointKind kind, double lat, double lng, sw.OpeningStatus open) => sw.AssistancePoint(
  id: id,
  name: name,
  kind: kind,
  coordinates: sw.Coordinates(lat: lat, lng: lng),
  address: null,
  publicPhone: null,
  recognition: sw.UnconfirmedRecognition(status: kind == sw.AssistancePointKind.police ? sw.UnconfirmedRecognitionStatus.notApplicable : sw.UnconfirmedRecognitionStatus.unconfirmed, checkedAt: null),
  availability: open,
  availabilityCheckedAt: null,
  capabilities: const [sw.AssistanceCapability.unknown],
  source: _demoSource(),
);

List<sw.AssistancePoint> demoAssistancePoints() => [
  _point('demo-point-1', '公共服務據點', sw.AssistancePointKind.publicFacility, 25.001, 121.501, sw.OpeningStatus.unknown),
  _point('demo-point-m3-1', '派出所', sw.AssistancePointKind.police, 25.0002, 121.5008, sw.OpeningStatus.unknown),
  _point('demo-point-m3-2', '便利商店', sw.AssistancePointKind.convenienceStore, 25.0005, 121.4997, sw.OpeningStatus.unknown),
];

// ───────── 異常回報（提案型別） ─────────

enum AnomalyCategory { fight, suspicious, lighting, construction, other }

const anomalyCategoryLabel = {AnomalyCategory.fight: '打架衝突', AnomalyCategory.suspicious: '可疑人士', AnomalyCategory.lighting: '照明不足', AnomalyCategory.construction: '道路施工', AnomalyCategory.other: '其他狀況'};

/// 待確認 → 多人回報 → 已協助轉通報（示範）→ 已解除（警方確認後移除）。
enum AnomalyStatus { pending, multiReported, forwardedDemo, cleared }

const anomalyStatusLabel = {AnomalyStatus.pending: '待確認', AnomalyStatus.multiReported: '多人回報', AnomalyStatus.forwardedDemo: '示範轉通報（未送出）', AnomalyStatus.cleared: '已解除'};

/// 犯罪紀錄區：官方犯罪紀錄的參考位置（地址或捷運出口比對，非精確案發地點）。
typedef CrimeSpot = ({String id, LatLng at, String label});

/// 系統內回報的避讓半徑（公尺），與路線規劃一致。
const reportAvoidRadiusMeters = 50.0;

class Anomaly {
  Anomaly({required this.id, required this.category, required this.at, required this.firstReportedAt, required this.reportCount, required this.status, List<String>? updates, this.mode = sw.DataMode.mock})
    : updates = updates ?? [];
  final String id;
  final AnomalyCategory category;
  final LatLng at;
  final DateTime firstReportedAt;
  int reportCount;
  AnomalyStatus status;
  final List<String> updates;
  final sw.DataMode mode;
}

/// 回家示範路線刻意不走西側 121.5000 那條街與北側西段；落在那裡、尚未解除的回報就是「已繞開」。
int avoidedCount(List<Anomaly> list) =>
    list.where((a) => a.status != AnomalyStatus.cleared && ((a.at.lng - 121.5).abs() < .00005 || ((a.at.lat - 25.001).abs() < .00005 && a.at.lng < 121.5006))).length;

List<Anomaly> demoAnomalies() => [
  Anomaly(
    id: 'demo-anomaly-1',
    category: AnomalyCategory.lighting,
    at: const LatLng(25.0003, 121.5),
    firstReportedAt: DateTime.parse('2026-11-07T19:00:00+08:00'),
    reportCount: 1,
    status: AnomalyStatus.pending,
  ),
  Anomaly(
    id: 'demo-anomaly-2',
    category: AnomalyCategory.construction,
    at: const LatLng(25.001, 121.5003),
    firstReportedAt: DateTime.parse('2026-11-07T19:05:00+08:00'),
    reportCount: 3,
    status: AnomalyStatus.multiReported,
  ),
  Anomaly(
    id: 'demo-anomaly-3',
    category: AnomalyCategory.fight,
    at: const LatLng(25.0007, 121.5),
    firstReportedAt: DateTime.parse('2026-11-07T19:10:00+08:00'),
    reportCount: 2,
    status: AnomalyStatus.forwardedDemo,
  ),
  Anomaly(
    id: 'demo-anomaly-4',
    category: AnomalyCategory.suspicious,
    at: const LatLng(25.0012, 121.4997),
    firstReportedAt: DateTime.parse('2026-11-07T18:00:00+08:00'),
    reportCount: 2,
    status: AnomalyStatus.cleared,
  ),
];

// ───────── 簡訊報警範本（提案；收件號碼由 M1 決定，不放 IP） ─────────

abstract final class SmsDraftTemplate {
  static const String? recipient = null;
  static const recipientNote = '';
  static String format({required String time, required sw.Position? position, required String situation, required String? nearbyPointName}) {
    final coords = position == null ? '尚未取得' : '${position.coordinates.lat}, ${position.coordinates.lng}';
    final accuracy = position?.accuracyMeters == null ? '未提供' : '${position!.accuracyMeters!.round()} 公尺';
    return '時間：$time；GPS 座標：$coords；精度：$accuracy；情況：$situation；附近據點：${nearbyPointName ?? '尚未提供'}。';
  }
}
