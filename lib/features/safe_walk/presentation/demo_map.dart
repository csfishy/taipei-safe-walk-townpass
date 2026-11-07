import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;
import 'package:town_pass/util/tp_colors.dart';

const _w = 360.0, _h = 480.0;

/// 示意地圖投影：等比填滿（類似 cover），中心對齊。
class _Proj {
  factory _Proj(Size size) {
    final scale = size.height / _h > size.width / _w ? size.width / _w : size.height / _h;
    return _Proj._(scale, (size.width - _w * scale) / 2, (size.height - _h * scale) / 2);
  }
  _Proj._(this.scale, this.dx, this.dy);
  final double scale, dx, dy;
  Offset of(LatLng p) => Offset(dx + (p.lng - DemoGeo.minLng) / (DemoGeo.maxLng - DemoGeo.minLng) * _w * scale, dy + (DemoGeo.maxLat - p.lat) / (DemoGeo.maxLat - DemoGeo.minLat) * _h * scale);
  LatLng back(Offset o) => LatLng(DemoGeo.maxLat - (o.dy - dy) / (_h * scale) * (DemoGeo.maxLat - DemoGeo.minLat), DemoGeo.minLng + (o.dx - dx) / (_w * scale) * (DemoGeo.maxLng - DemoGeo.minLng));
}

const pointGlyph = {sw.AssistancePointKind.police: '警', sw.AssistancePointKind.partnerStore: '店', sw.AssistancePointKind.convenienceStore: '店', sw.AssistancePointKind.publicFacility: '公'};

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
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final proj = _Proj(size);
        Widget marker(LatLng at, double d, Widget child, {String? label, VoidCallback? onTap}) {
          final o = proj.of(at);
          final hit = onTap == null ? d : math.max(d, swTouch);
          return Positioned(
            left: o.dx - hit / 2,
            top: o.dy - hit / 2,
            width: hit,
            height: hit,
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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onPick == null ? null : (d) => onPick!(proj.back(d.localPosition)),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(path.map((p) => '${p.lat},${p.lng}').join('|')),
                  tween: Tween(begin: compact ? 1 : 0, end: 1),
                  duration: SwMotion.of(context, 900),
                  curve: SwMotion.curve,
                  builder: (_, t, _) => CustomPaint(
                    painter: _MapPainter(proj: proj, path: path, showShortcut: showShortcut, progress: t),
                  ),
                ),
              ),
              for (final a in anomalies)
                marker(
                  a.at,
                  a.id == selectedAnomalyId ? 34 : 26,
                  _AnomalyMark(status: a.status, selected: a.id == selectedAnomalyId, small: compact),
                  label: '${anomalyCategoryLabel[a.category]}，${anomalyStatusLabel[a.status]}，查看與回報新狀況',
                  onTap: onAnomaly == null ? null : () => onAnomaly!(a.id),
                ),
              for (final p in points)
                marker(
                  LatLng(p.coordinates.lat, p.coordinates.lng),
                  p.id == selectedPointId ? 40 : 26,
                  _PointMark(glyph: pointGlyph[p.kind]!, selected: p.id == selectedPointId),
                  label: '${p.name}，查看詳細資訊',
                  onTap: onPoint == null ? null : () => onPoint!(p.id),
                ),
              marker(DemoGeo.home, 32, _HomeMark(active: homeActive)),
              marker(start, 34, const _StartMark()),
              if (pin != null) marker(pin!, 40, const Icon(Icons.location_on, size: 40, color: SwColors.text)),
            ],
          ),
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.proj, required this.path, required this.showShortcut, required this.progress});
  final double progress;
  final _Proj proj;
  final List<LatLng> path;
  final bool showShortcut;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = SwColors.surface);
    // 以示範街道為準往外延伸到填滿畫面（街距 0.0006 經度／0.0005 緯度）。
    final xs = [...DemoGeo.streetsLng];
    while (proj.of(LatLng(0, xs.first)).dx > -60) {
      xs.insert(0, xs.first - .0006);
    }
    while (proj.of(LatLng(0, xs.last)).dx < size.width + 60) {
      xs.add(xs.last + .0006);
    }
    final ys = [...DemoGeo.streetsLat.reversed];
    while (proj.of(LatLng(ys.first, DemoGeo.minLng)).dy > -60) {
      ys.insert(0, ys.first + .0005);
    }
    while (proj.of(LatLng(ys.last, DemoGeo.minLng)).dy < size.height + 60) {
      ys.add(ys.last - .0005);
    }
    final inset = 9 * proj.scale;
    for (var c = 1; c < xs.length; c++) {
      for (var r = 1; r < ys.length; r++) {
        final a = proj.of(LatLng(ys[r - 1], xs[c - 1])), b = proj.of(LatLng(ys[r], xs[c]));
        final rect = Rect.fromPoints(a, b).deflate(inset);
        if (rect.width <= 0 || rect.height <= 0) continue;
        final park = (xs[c - 1] - 121.5).abs() < 1e-7 && (ys[r - 1] - 25.001).abs() < 1e-7;
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        canvas.drawRRect(rr, Paint()..color = park ? TPColors.primary100 : SwColors.bg);
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = park ? TPColors.primary200 : SwColors.border,
        );
      }
    }
    if (showShortcut) {
      _dashed(
        canvas,
        DemoGeo.shortcutRoute.map(proj.of).toList(),
        Paint()
          ..color = TPColors.grayscale500
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    if (path.length > 1) {
      final full = Path()..addPolygon(path.map(proj.of).toList(), false);
      final p = Path();
      for (final m in full.computeMetrics()) {
        p.addPath(m.extractPath(0, m.length * progress), Offset.zero);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = SwColors.surface,
      );
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = SwColors.brandDeep,
      );
    }
  }

  void _dashed(Canvas canvas, List<Offset> pts, Paint paint) {
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += 9) {
        canvas.drawLine(a + dir * t, a + dir * math.min(t + 2, len), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.progress != progress || old.path != path || old.showShortcut != showShortcut || old.proj.scale != proj.scale;
}

class _AnomalyMark extends StatelessWidget {
  const _AnomalyMark({required this.status, required this.selected, required this.small});
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
        shadows: const [Shadow(color: SwColors.warnText, blurRadius: 0, offset: Offset(0, 0))],
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
      color: SwColors.brandDeep,
      border: Border.all(color: selected ? SwColors.brand : SwColors.surface, width: 3),
      boxShadow: SwShadow.float,
    ),
    child: Text(glyph, style: SwText.caption.copyWith(color: SwColors.onDeep, height: 1)),
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
        color: SwColors.brandDeep,
        border: Border.all(color: SwColors.surface, width: 3),
        boxShadow: SwShadow.float,
      ),
      child: const Icon(Icons.home_rounded, size: 16, color: SwColors.onDeep),
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
    decoration: BoxDecoration(shape: BoxShape.circle, color: SwColors.brand.withValues(alpha: .25)),
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SwColors.brandDeep,
        border: Border.all(color: SwColors.surface, width: 3),
      ),
    ),
  );
}
