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

enum StepDir { east, west, north, south }

const stepDirLabel = {StepDir.east: '東', StepDir.west: '西', StepDir.north: '北', StepDir.south: '南'};

class RouteStep {
  RouteStep(this.dir, this.meters);
  final StepDir dir;
  int meters;
}

/// 把路線轉成白話步驟（同方向合併、四捨五入到 10 公尺）。
List<RouteStep> routeSteps(List<LatLng> path) {
  final steps = <RouteStep>[];
  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1], b = path[i];
    final dLat = b.lat - a.lat, dLng = b.lng - a.lng;
    final dir = (dLng.abs() * math.cos(a.lat * math.pi / 180) > dLat.abs()) ? (dLng > 0 ? StepDir.east : StepDir.west) : (dLat > 0 ? StepDir.north : StepDir.south);
    final m = metersBetween(a, b).round();
    if (m < 3) continue;
    if (steps.isNotEmpty && steps.last.dir == dir) {
      steps.last.meters += m;
    } else {
      steps.add(RouteStep(dir, m));
    }
  }
  for (final s in steps) {
    s.meters = math.max(10, (s.meters / 10).round() * 10);
  }
  return steps;
}

// ───────── 求助據點（共用 AssistancePoint 型別，示範資料） ─────────

sw.SourceMetadata _demoSource() => sw.SourceMetadata(
  datasetId: 'demo-only',
  title: '人工示範資料（非政府資料）',
  dataMode: sw.DataMode.mock,
  sourceUrl: null,
  retrievedAt: '2026-11-07T11:30:00+08:00',
  dataUpdatedAt: null,
  license: null,
  coverage: '虛構示範區域，禁止用於實地導航',
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
  _point('demo-point-1', '示範求助據點 A（非真實機關）', sw.AssistancePointKind.publicFacility, 25.001, 121.501, sw.OpeningStatus.unknown),
  _point('demo-point-m3-1', '示範據點 B：派出所（非真實機關）', sw.AssistancePointKind.police, 25.0002, 121.5008, sw.OpeningStatus.open),
  _point('demo-point-m3-2', '示範據點 C：便利商店（非真實商店）', sw.AssistancePointKind.convenienceStore, 25.0005, 121.4997, sw.OpeningStatus.unknown),
];

// ───────── 異常回報（提案型別） ─────────

enum AnomalyCategory { fight, suspicious, lighting, construction, other }

const anomalyCategoryLabel = {AnomalyCategory.fight: '打架衝突', AnomalyCategory.suspicious: '可疑人士', AnomalyCategory.lighting: '照明不足', AnomalyCategory.construction: '道路施工', AnomalyCategory.other: '其他狀況'};

/// 待確認 → 多人回報 → 已協助轉通報（示範）→ 已解除（警方確認後移除）。
enum AnomalyStatus { pending, multiReported, forwardedDemo, cleared }

const anomalyStatusLabel = {AnomalyStatus.pending: '待確認', AnomalyStatus.multiReported: '多人回報', AnomalyStatus.forwardedDemo: '已協助轉通報', AnomalyStatus.cleared: '已解除'};

class Anomaly {
  Anomaly({required this.id, required this.category, required this.at, required this.firstReportedAt, required this.reportCount, required this.status, List<String>? updates})
    : updates = updates ?? [];
  final String id;
  final AnomalyCategory category;
  final LatLng at;
  final DateTime firstReportedAt;
  int reportCount;
  AnomalyStatus status;
  final List<String> updates;
  final sw.DataMode mode = sw.DataMode.mock;
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

// ───────── 模擬來電劇本（提案型別，Reels 式預寫對話） ─────────

class CallerLine {
  const CallerLine(this.text, this.replies, this.next);
  final String text;

  /// 使用者的 3 個快速回覆。
  final List<String> replies;

  /// 任一回覆之後，對方接著說的那一句（索引）。
  final int next;
}

abstract final class FakeCallScript {
  static const disclosure = '這不是真人通話，也沒有報警';
  static const caller = '家人';
  static const lines = [
    CallerLine('喂，你走到哪裡啦？晚餐吃了沒？', ['我正在回家路上，已經吃過了。', '我剛出發，等一下再吃晚餐。', '我走得比較慢，你陪我聊一下好嗎？'], 1),
    CallerLine('好呀，我陪你聊。你想沿著大路走，還是先找地方休息？', ['我想沿著大路慢慢走。', '我想先到附近的便利商店休息。', '我先停在明亮的地方看看路線。'], 2),
    CallerLine('先走到附近的便利商店或人多的地方，需要的話按緊急求助。', ['我覺得好像有人跟著我，我先去便利商店。', '我現在走到比較暗的地方，我先往人多的地方走。', '好，我會注意周圍。'], 3),
    CallerLine('沒問題，慢慢來。到家之後再跟我聊聊今天的事，好嗎？', ['好，到家後我再跟你說。', '我還想再聊一會兒。', '謝謝你陪我，我先確認一下方向。'], 0),
  ];
  static const templates = ['我覺得好像有人跟著我', '我現在走到比較暗的地方', '你可以陪我聊一下嗎？', '我會沿著明亮的大路走。', '我想先到附近的便利商店休息。', '我說話比較慢，請等我一下。', '我到了之後再跟你說，謝謝你。'];
}

// ───────── 簡訊報警範本（提案；收件號碼由 M1 決定，不放 IP） ─────────

abstract final class SmsDraftTemplate {
  static const String? recipient = null;
  static const recipientNote = '由 M1 決定';
  static String format({required String time, required sw.Position? position, required String situation, required String? nearbyPointName}) {
    final coords = position == null ? '尚未取得' : '${position.coordinates.lat}, ${position.coordinates.lng}';
    final accuracy = position?.accuracyMeters == null ? '未提供' : '${position!.accuracyMeters!.round()} 公尺';
    return '示範，未傳送。時間：$time；GPS 座標：$coords；精度：$accuracy；情況：$situation；附近據點：${nearbyPointName ?? '尚未提供'}。';
  }
}
