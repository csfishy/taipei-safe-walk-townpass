import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/util/tp_colors.dart';

const pointGlyph = {
  sw.AssistancePointKind.police: '警',
  sw.AssistancePointKind.partnerStore: '店',
  sw.AssistancePointKind.convenienceStore: '店',
  sw.AssistancePointKind.publicFacility: '公',
};

/// OpenStreetMap 標準圖磚（不需 API Key）。使用條款要求標示來源並帶有可辨識的 User-Agent。
const _kTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _kUserAgentPackage = 'town_pass';

ll.LatLng _ll(LatLng p) => ll.LatLng(p.lat, p.lng);

class DemoMap extends StatelessWidget {
  const DemoMap({
    super.key,
    required this.start,
    required this.points,
    required this.anomalies,
    required this.path,
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
  final List<Anomaly> anomalies;
  final List<LatLng> path;
  final bool showShortcut, homeActive, compact;
  final String? selectedPointId, selectedAnomalyId;
  final LatLng? pin;
  final ValueChanged<String>? onAnomaly, onPoint;
  final ValueChanged<LatLng>? onPick;

  @override
  Widget build(BuildContext context) {
    final interactive = !compact;
    // 初始視野：涵蓋起點、回家、所有求助地點與異常回報（避開上方標題與下方資訊框）。
    final fit = LatLngBounds.fromPoints([
      _ll(start),
      _ll(DemoGeo.home),
      for (final p in points) ll.LatLng(p.coordinates.lat, p.coordinates.lng),
      for (final a in anomalies) _ll(a.at),
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
            ? ExcludeSemantics(child: Center(child: child))
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
      for (final p in points)
        marker(
          LatLng(p.coordinates.lat, p.coordinates.lng),
          p.id == selectedPointId ? 40 : 26,
          _PointMark(
            glyph: pointGlyph[p.kind]!,
            selected: p.id == selectedPointId,
          ),
          label: '${p.name}，查看詳細資訊',
          onTap: onPoint == null ? null : () => onPoint!(p.id),
        ),
      marker(DemoGeo.home, 32, _HomeMark(active: homeActive)),
      marker(start, 34, const _StartMark()),
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

    final map = FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: fit,
          padding: compact
              ? const EdgeInsets.all(16)
              : const EdgeInsets.fromLTRB(40, 140, 40, 160),
          maxZoom: 18,
        ),
        minZoom: 3,
        maxZoom: 19,
        backgroundColor: SwColors.surface,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.flingAnimation
              : InteractiveFlag.none,
        ),
        onTap: onPick == null
            ? null
            : (_, at) => onPick!(LatLng(at.latitude, at.longitude)),
      ),
      children: [
        TileLayer(
          urlTemplate: _kTileUrl,
          userAgentPackageName: _kUserAgentPackage,
          maxNativeZoom: 19,
          // 示範用：不寫入磁碟快取，避免測試環境缺少 path_provider；正式版再接快取。
          tileProvider: NetworkTileProvider(
            cachingProvider: DisabledMapCachingProvider(),
          ),
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
    if (compact) return map;
    // 版權標示（OSM 使用條款要求）；獨立放在地圖上方，避免套件 Attribution 在窄寬度溢出。
    return Stack(
      children: [
        Positioned.fill(child: map),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: ColoredBox(
              color: Color(0xB3FFFFFF),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '© OpenStreetMap contributors',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10, color: Color(0xFF555555)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
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

class _PointMark extends StatelessWidget {
  const _PointMark({required this.glyph, required this.selected});
  final String glyph;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    width: selected ? 36 : 26,
    height: selected ? 36 : 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: SwColors.brand,
      border: Border.all(
        color: selected ? SwColors.brand : SwColors.surface,
        width: 3,
      ),
      boxShadow: SwShadow.float,
    ),
    child: Text(
      glyph,
      style: SwText.caption.copyWith(color: SwColors.onBrand, height: 1),
    ),
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
  const _StartMark();
  @override
  Widget build(BuildContext context) => Container(
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
