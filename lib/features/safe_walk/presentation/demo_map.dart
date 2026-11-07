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
  /// Tests supply a fresh, non-network provider without changing app defaults.
  @visibleForTesting
  static TileProvider Function()? tileProviderFactoryForTesting;

  static TileProvider createTileProvider() =>
      tileProviderFactoryForTesting?.call() ?? NetworkTileProvider();

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
    this.liveRendering = false,
    this.hasStart = true,
  });
  final LatLng start;
  final List<sw.AssistancePoint> points;
  final List<Anomaly> anomalies;
  final List<LatLng> path;
  final bool showShortcut, homeActive, compact;

  /// Neutral renderer: no Demo home, shortcut or anomaly overlays.
  final bool liveRendering, hasStart;
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
    final fitPoints = [
      if (hasStart || !liveRendering || (path.isEmpty && pin == null))
        _ll(start),
      if (!liveRendering) _ll(DemoGeo.home),
      for (final at in path) _ll(at),
      if (liveRendering && pin != null) _ll(pin!),
      for (final p in points)
        if (!liveRendering || p.source.dataMode == sw.DataMode.live)
          ll.LatLng(p.coordinates.lat, p.coordinates.lng),
      if (!liveRendering)
        for (final a in anomalies) _ll(a.at),
    ];
    final fit = LatLngBounds.fromPoints(fitPoints);
    final singlePoint = fitPoints.every((p) => p == fitPoints.first);

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
      if (!liveRendering)
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
        if (!liveRendering || p.source.dataMode == sw.DataMode.live)
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
      if (!liveRendering)
        marker(DemoGeo.home, 32, _HomeMark(active: homeActive)),
      if (hasStart) marker(start, 34, const _StartMark()),
      if (pin != null)
        marker(
          pin!,
          40,
          const Icon(Icons.location_on, size: 40, color: SwColors.text),
        ),
    ];

    final lines = <Polyline>[
      if (showShortcut && !liveRendering)
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
        liveRendering
            ? '$hasStart:${start.lat},${start.lng}:${pin?.lat},${pin?.lng}:${path.map((at) => '${at.lat},${at.lng}').join('|')}'
            : path.map((at) => '${at.lat},${at.lng}').join('|'),
      ),
      options: MapOptions(
        initialCenter: fitPoints.first,
        initialZoom: 14,
        initialCameraFit: liveRendering && singlePoint
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
          // Native uses flutter_map's HTTP-aware built-in cache; web uses the
          // browser cache. Tests inject tiles without changing these defaults.
          tileProvider: createTileProvider(),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Semantics(
            link: true,
            label: 'OpenStreetMap 地圖來源與授權',
            onTap: () => unawaited(_openAttribution(context)),
            child: ExcludeSemantics(
              child: Material(
                color: SwColors.surface,
                child: InkWell(
                  onTap: () => unawaited(_openAttribution(context)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: swTouch),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Align(
                        alignment: Alignment.centerRight,
                        heightFactor: 1,
                        child: Text(
                          '© OpenStreetMap contributors',
                          textAlign: TextAlign.right,
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
          ),
        ),
      ],
    );
  }

  Future<void> _openAttribution(BuildContext context) async {
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
