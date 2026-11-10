// Artificial map fixtures for isolated tests only.
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_models.dart';
export 'package:town_pass/features/safe_walk/presentation/safe_walk_map_models.dart';

abstract final class DemoGeo {
  static const start = LatLng(25.0, 121.5);
  static const home = LatLng(25.001, 121.5012);

  /// 回家：繞開西側 121.5000 街上的異常回報。
  static const homeRoute = [
    start,
    LatLng(25.0, 121.5006),
    LatLng(25.0005, 121.5006),
    LatLng(25.0005, 121.5012),
    home,
  ];

  /// shortcut: 沿街道的 L 形示範路線，不是路徑規劃；接 M2 RouteService 後改用真實 RouteResult。
  static List<LatLng> lRoute(LatLng from, LatLng to) => [
    from,
    LatLng(from.lat, to.lng),
    to,
  ];
}

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

sw.AssistancePoint _point(
  String id,
  String name,
  sw.AssistancePointKind kind,
  double lat,
  double lng,
  sw.OpeningStatus open,
) => sw.AssistancePoint(
  id: id,
  name: name,
  kind: kind,
  coordinates: sw.Coordinates(lat: lat, lng: lng),
  address: null,
  publicPhone: null,
  recognition: sw.UnconfirmedRecognition(
    status: kind == sw.AssistancePointKind.police
        ? sw.UnconfirmedRecognitionStatus.notApplicable
        : sw.UnconfirmedRecognitionStatus.unconfirmed,
    checkedAt: null,
  ),
  availability: open,
  availabilityCheckedAt: null,
  capabilities: const [sw.AssistanceCapability.unknown],
  source: _demoSource(),
);

List<sw.AssistancePoint> demoAssistancePoints() => [
  _point(
    'demo-point-1',
    '公共服務據點',
    sw.AssistancePointKind.publicFacility,
    25.001,
    121.501,
    sw.OpeningStatus.unknown,
  ),
  _point(
    'demo-point-m3-1',
    '派出所',
    sw.AssistancePointKind.police,
    25.0002,
    121.5008,
    sw.OpeningStatus.unknown,
  ),
  _point(
    'demo-point-m3-2',
    '便利商店',
    sw.AssistancePointKind.convenienceStore,
    25.0005,
    121.4997,
    sw.OpeningStatus.unknown,
  ),
];

// ───────── 異常回報（提案型別） ─────────
