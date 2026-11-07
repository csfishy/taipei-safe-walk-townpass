import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/util/tp_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// 求助地點在地圖、圖例與清單上一律用同一個圖示（捧著愛心的手：這裡有人能幫你）；
/// 種類（超商、派出所…）寫在文字裡。
const helpPointIcon = Icons.volunteer_activism_rounded;

/// OpenStreetMap 標準圖磚（不需 API Key）。使用條款要求標示來源並帶有可辨識的 User-Agent。
const _kTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _kUserAgentPackage = 'town_pass';

ll.LatLng _ll(LatLng p) => ll.LatLng(p.lat, p.lng);

/// 犯罪紀錄區用的紫色（臺北通色票沒有紫，取官方輔助色）。
const crimeMarkColor = Color(0xFF7B4BB7);

class DemoMap extends StatelessWidget {
  /// Tests supply a fresh, non-network provider without changing app defaults.
  @visibleForTesting
  static TileProvider Function()? tileProviderFactoryForTesting;

  static TileProvider createTileProvider() =>
      tileProviderFactoryForTesting?.call() ?? NetworkTileProvider();

  const DemoMap({
    super.key,
    required this.start,
    required this.points,
    this.heading,
    this.follow,
    required this.anomalies,
    required this.path,
    this.altPaths = const [],
    this.destination,
    this.showDestination = true,
    this.showStart = true,
    this.showAttribution = true,
    this.showTiles = true,
    this.crimeSpots = const [],
    this.onCrime,
    this.avoidRadiusMeters = 0,
    this.showShortcut = false,
    this.homeActive = true,
    this.selectedPointId,
    this.selectedAnomalyId,
    this.pin,
    this.onAnomaly,
    this.onPoint,
    this.onPick,
    this.compact = false,
  });
  final LatLng start;
  final List<sw.AssistancePoint> points;

  /// 手機朝向（度，從北方順時針）；有值時起點畫成指向箭頭（地圖固定北方朝上）。
  final double? heading;

  /// 導覽中：鏡頭以目前位置為中心（約 10 公尺移動才重新置中）。
  final LatLng? follow;
  final List<Anomaly> anomalies;
  final List<LatLng> path;

  /// Other route options, drawn grey under [path].
  final List<List<LatLng>> altPaths;

  /// 目的地標記位置（預設為示範的家）。
  final LatLng? destination;
  final bool showDestination, showStart;

  /// false 時由外層（例如下方資訊框）顯示 OSM 版權標示。
  final bool showAttribution;
  final bool showTiles;

  /// 紫色參考位置及產品設定的 50 公尺繞行緩衝，並非案發範圍。
  final List<({LatLng at, String label})> crimeSpots;

  /// Tap a purple dot (index into [crimeSpots]) to show its details.
  final ValueChanged<int>? onCrime;

  /// When > 0, each unresolved report gets a circle of this real-world radius.
  final double avoidRadiusMeters;
  final bool showShortcut, homeActive, compact;
  final String? selectedPointId, selectedAnomalyId;
  final LatLng? pin;
  final ValueChanged<String>? onAnomaly, onPoint;
  final ValueChanged<LatLng>? onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _buildMap(context, constraints.biggest),
  );

  Widget _buildMap(BuildContext context, Size viewport) {
    final interactive = !compact;
    // 初始視野：涵蓋起點、回家、所有求助地點與異常回報（避開上方標題與下方資訊框）。
    // 有真實路線時只框路線，避免把遠處的示範資料一起框進來。
    final live = avoidRadiusMeters > 0 && path.length > 1;
    final fit = LatLngBounds.fromPoints([
      _ll(start),
      for (final at in path) _ll(at),
      if (!live) ...[
        if (showDestination) _ll(destination ?? DemoGeo.home),
        for (final p in points) ll.LatLng(p.coordinates.lat, p.coordinates.lng),
        for (final a in anomalies) _ll(a.at),
      ],
    ]);

    Marker marker(
      LatLng at,
      double d,
      Widget child, {
      String? label,
      VoidCallback? onTap,
    }) {
      final hit = onTap == null ? d : (d > swTouch ? d : swTouch);
      return Marker(
        point: _ll(at),
        width: hit,
        height: hit,
        alignment: Alignment.center,
        child: onTap == null
            ? Semantics(
                label: label,
                child: ExcludeSemantics(child: Center(child: child)),
              )
            : Semantics(
                button: true,
                label: label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Center(child: child),
                ),
              ),
      );
    }

    final markers = <Marker>[
      for (final a in anomalies)
        marker(
          a.at,
          a.id == selectedAnomalyId ? 34 : 26,
          _AnomalyMark(
            status: a.status,
            selected: a.id == selectedAnomalyId,
            small: compact,
          ),
          label:
              '${anomalyCategoryLabel[a.category]}，${anomalyStatusLabel[a.status]}，查看與回報新狀況',
          onTap: onAnomaly == null ? null : () => onAnomaly!(a.id),
        ),
      for (final (i, c) in crimeSpots.indexed)
        marker(
          c.at,
          onCrime == null ? 12 : 20,
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: crimeMarkColor,
              shape: BoxShape.circle,
              border: Border.all(color: SwColors.surface, width: 1.5),
            ),
          ),
          label: '50 公尺避讓緩衝區：${c.label}（產品設定的繞行距離；參考位置不是精確案發點或官方犯罪範圍）',
          onTap: onCrime == null ? null : () => onCrime!(i),
        ),
      for (final p in points)
        marker(
          LatLng(p.coordinates.lat, p.coordinates.lng),
          p.id == selectedPointId ? 40 : 26,
          HelpPointMark(selected: p.id == selectedPointId),
          label: '${p.name}，查看詳細資訊',
          onTap: onPoint == null ? null : () => onPoint!(p.id),
        ),
      if (showDestination)
        marker(destination ?? DemoGeo.home, 32, _HomeMark(active: homeActive)),
      if (showStart) marker(start, 44, _StartMark(heading: heading)),
      if (pin != null)
        marker(
          pin!,
          40,
          const Icon(Icons.location_on, size: 40, color: SwColors.text),
        ),
    ];

    final lines = <Polyline>[
      if (showShortcut)
        Polyline(
          points: DemoGeo.shortcutRoute.map(_ll).toList(),
          strokeWidth: 3,
          color: TPColors.grayscale500,
          pattern: StrokePattern.dashed(segments: [2.0, 7.0]),
        ),
      for (final alt in altPaths)
        if (alt.length > 1)
          Polyline(
            points: alt.map(_ll).toList(),
            strokeWidth: 5,
            color: TPColors.grayscale400,
            borderStrokeWidth: 2,
            borderColor: SwColors.surface,
          ),
      if (path.length > 1) ...[
        Polyline(
          points: path.map(_ll).toList(),
          strokeWidth: 7,
          color: SwColors.brand,
          borderStrokeWidth: 3,
          borderColor: SwColors.surface,
        ),
      ],
    ];

    // Keep fitted markers above the opaque attribution footer, including in a
    // short viewport. Leave at least one logical pixel for the camera fit.
    final bottomInset = math.min(
      math.max(0.0, viewport.height - 1),
      math.max(swTouch + 20, math.min(160.0, viewport.height * .28)),
    );
    final topInset = math.min(
      math.min(140.0, viewport.height * .24),
      math.max(0.0, viewport.height - bottomInset - 1),
    );

    final map = FlutterMap(
      // A changed destination gets a fresh fit. Unchanged route values retain
      // the user's current pan/zoom through other view rebuilds.
      key: ValueKey(
        follow != null
            ? 'follow ${follow!.lat.toStringAsFixed(4)},${follow!.lng.toStringAsFixed(4)}'
            : path.map((at) => '${at.lat},${at.lng}').join('|'),
      ),
      options: MapOptions(
        initialCenter: follow == null
            ? const ll.LatLng(50.5, 30.51)
            : _ll(follow!),
        initialZoom: follow == null ? 13 : 17,
        initialCameraFit: follow != null
            ? null
            : CameraFit.bounds(
                bounds: fit,
                padding: compact
                    ? const EdgeInsets.all(16)
                    : EdgeInsets.fromLTRB(
                        math.min(40, viewport.width * .1),
                        topInset,
                        math.min(40, viewport.width * .1),
                        bottomInset,
                      ),
                maxZoom: 18,
              ),
        minZoom: 3,
        maxZoom: 19,
        backgroundColor: SwColors.surface,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.flingAnimation |
                    // 電腦預覽可用滑鼠滾輪縮放；不開雙擊縮放，點地圖設點才不會延遲。
                    InteractiveFlag.scrollWheelZoom
              : InteractiveFlag.none,
        ),
        onTap: onPick == null
            ? null
            : (_, at) => onPick!(LatLng(at.latitude, at.longitude)),
      ),
      children: [
        if (showTiles)
          TileLayer(
            urlTemplate: _kTileUrl,
            userAgentPackageName: _kUserAgentPackage,
            maxNativeZoom: 19,
            // Native uses flutter_map's HTTP-aware built-in cache; web uses the
            // browser cache. Tests inject tiles without changing these defaults.
            tileProvider: createTileProvider(),
          ),
        if (avoidRadiusMeters > 0)
          CircleLayer(
            circles: [
              for (final c in crimeSpots)
                CircleMarker(
                  point: _ll(c.at),
                  radius: avoidRadiusMeters,
                  useRadiusInMeter: true,
                  color: crimeMarkColor.withValues(alpha: .14),
                  borderColor: crimeMarkColor,
                  borderStrokeWidth: 1.5,
                ),
              for (final a in anomalies)
                if (a.status != AnomalyStatus.cleared)
                  CircleMarker(
                    point: _ll(a.at),
                    radius: avoidRadiusMeters,
                    useRadiusInMeter: true,
                    color: SwColors.warnMark.withValues(alpha: .18),
                    borderColor: SwColors.warnMark,
                    borderStrokeWidth: 2,
                  ),
            ],
          ),
        // 路線淡入（保留原本換路線時的過場動畫）。
        TweenAnimationBuilder<double>(
          key: ValueKey(path.map((p) => '${p.lat},${p.lng}').join('|')),
          tween: Tween(begin: compact ? 1 : 0, end: 1),
          duration: SwMotion.of(context, 900),
          curve: SwMotion.curve,
          builder: (_, t, child) => Opacity(opacity: t, child: child),
          child: PolylineLayer(polylines: lines),
        ),
        MarkerLayer(markers: markers),
      ],
    );
    // 版權標示（OSM 使用條款要求）；獨立放在地圖上方，避免套件 Attribution 在窄寬度溢出。
    return Stack(
      children: [
        Positioned.fill(child: map),
        // 小而半透明，只佔右下角；地圖維持滿版（仍可點開 OSM 授權頁）。
        if (showAttribution)
          Positioned(
            right: 0,
            bottom: 0,
            child: Semantics(
              link: true,
              label: 'OpenStreetMap 地圖來源與授權',
              onTap: () => unawaited(openAttribution(context)),
              child: ExcludeSemantics(
                child: Material(
                  color: SwColors.surface.withValues(alpha: .7),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                  ),
                  child: InkWell(
                    onTap: () => unawaited(openAttribution(context)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text(
                        '© OpenStreetMap',
                        style: TextStyle(
                          fontSize: 10,
                          color: TPColors.grayscale700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 開啟 OSM 版權頁；放在地圖外的版權標示也用這個。
  static Future<void> openAttribution(BuildContext context) async {
    const url = 'https://www.openstreetmap.org/copyright';
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Missing/failed launchers must not escape an asynchronous tap handler.
    }
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('無法開啟授權說明，請瀏覽 $url')));
    }
  }
}

class _AnomalyMark extends StatelessWidget {
  const _AnomalyMark({
    required this.status,
    required this.selected,
    required this.small,
  });
  final AnomalyStatus status;
  final bool selected, small;
  @override
  Widget build(BuildContext context) {
    final cleared = status == AnomalyStatus.cleared;
    final s = (selected ? 30.0 : 24.0) * (small ? .7 : 1);
    return Container(
      decoration: selected
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SwColors.warnText, width: 2),
            )
          : null,
      padding: selected ? const EdgeInsets.all(2) : null,
      child: Icon(
        Icons.warning_rounded,
        size: s,
        color: cleared ? TPColors.grayscale400 : SwColors.warnMark,
        shadows: const [
          Shadow(color: SwColors.warnText, blurRadius: 0, offset: Offset(0, 0)),
        ],
      ),
    );
  }
}

/// 求助地點標記：主色圓底白色求助圖示；地圖與圖例共用。
class HelpPointMark extends StatelessWidget {
  const HelpPointMark({super.key, this.selected = false, this.size = 26});
  final bool selected;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: selected ? size + 10 : size,
    height: selected ? size + 10 : size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: SwColors.brand,
      border: Border.all(
        color: selected ? SwColors.brand : SwColors.surface,
        width: size < 24 ? 2 : 3,
      ),
      boxShadow: SwShadow.float,
    ),
    child: Icon(helpPointIcon, size: size * .55, color: SwColors.onBrand),
  );
}

class _HomeMark extends StatelessWidget {
  const _HomeMark({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: active ? 1 : .55,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SwColors.brand,
        border: Border.all(color: SwColors.surface, width: 3),
        boxShadow: SwShadow.float,
      ),
      child: const Icon(Icons.home_rounded, size: 16, color: SwColors.onBrand),
    ),
  );
}

class _StartMark extends StatelessWidget {
  const _StartMark({this.heading});
  final double? heading;
  @override
  Widget build(BuildContext context) => heading == null
      ? _dot()
      // 導航箭頭（像 Google 地圖導航）：尖端指向使用者面對的方向。
      : Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SwColors.brand.withValues(alpha: .18),
          ),
          child: Transform.rotate(
            angle: heading! * math.pi / 180,
            child: CustomPaint(
              size: const Size(30, 30),
              painter: _ArrowPainter(),
            ),
          ),
        );

  Widget _dot() => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: SwColors.brand.withValues(alpha: .25),
    ),
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SwColors.brand,
        border: Border.all(color: SwColors.surface, width: 3),
      ),
    ),
  );
}

/// 朝上（北方，旋轉前）的導航箭頭：主色填滿、白色描邊、底部內凹。
class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * .5, h * .06)
      ..lineTo(w * .9, h * .9)
      ..lineTo(w * .5, h * .7)
      ..lineTo(w * .1, h * .9)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = SwColors.brand);
    canvas.drawPath(
      path,
      Paint()
        ..color = SwColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}
