import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;
import 'package:town_pass/util/tp_colors.dart';

const _kind = {sw.AssistancePointKind.police: '警察機關', sw.AssistancePointKind.partnerStore: '合作商店', sw.AssistancePointKind.convenienceStore: '便利商店', sw.AssistancePointKind.publicFacility: '公共設施'};
const _open = {sw.OpeningStatus.open: '營業中', sw.OpeningStatus.closed: '未營業', sw.OpeningStatus.unknown: '營業未知'};
const _openLong = {sw.OpeningStatus.open: '資料顯示營業中', sw.OpeningStatus.closed: '資料顯示未營業', sw.OpeningStatus.unknown: '營業狀態未確認'};

enum MapStartView { route, points, report }

/// 求助地點資料的狀態（由 M1 → M4 提供）：載入中、錯誤、或清單（可能是空的）。
class PointsState {
  const PointsState({this.points = const [], this.loading = false, this.error, this.onRetry});
  final List<sw.AssistancePoint> points;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
}

/// 地圖：預設回家路線（繞開異常回報）；「最近求助地點」為中性的第二個目的地；回報狀況直接在地圖上操作。
/// 底部資訊框可收合，讓地圖露出更多。
class SafeWalkMapView extends StatefulWidget {
  const SafeWalkMapView({
    super.key,
    required this.position,
    required this.pointsState,
    required this.anomalies,
    required this.onAnomaliesChanged,
    required this.onBack,
    required this.onCall,
    required this.onEmergency,
    this.onSms,
    this.startView = MapStartView.route,
  });
  final sw.Position? position;
  final PointsState pointsState;
  final List<Anomaly> anomalies;
  final VoidCallback onAnomaliesChanged, onBack, onCall, onEmergency;
  final ValueChanged<Anomaly>? onSms;
  final MapStartView startView;

  @override
  State<SafeWalkMapView> createState() => _SafeWalkMapViewState();
}

class _SafeWalkMapViewState extends State<SafeWalkMapView> {
  /// null = 回家；數字 = 第幾個最近求助地點。
  int? _pointIndex;
  late bool _pointsView = widget.startView == MapStartView.points;
  late bool _picking = widget.startView == MapStartView.report;
  bool _expanded = true;
  bool _legend = false;
  LatLng? _pin;
  String? _detailId, _pickedPointId, _toast;
  bool _stepsOpen = false;
  AnomalyCategory _category = AnomalyCategory.suspicious;
  final _note = TextEditingController();

  LatLng get _start => widget.position == null ? DemoGeo.start : LatLng(widget.position!.coordinates.lat, widget.position!.coordinates.lng);
  LatLng _at(sw.AssistancePoint p) => LatLng(p.coordinates.lat, p.coordinates.lng);

  List<sw.AssistancePoint> get _sorted => [...widget.pointsState.points]..sort((a, b) => metersBetween(_start, _at(a)).compareTo(metersBetween(_start, _at(b))));

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _update(Anomaly a, String text, {required bool bump}) {
    setState(() {
      if (bump) {
        a.reportCount++;
        if (a.status == AnomalyStatus.pending) a.status = AnomalyStatus.multiReported;
      }
      a.updates.add(text);
      _toast = '已更新這個回報（示範，未傳送）';
    });
    widget.onAnomaliesChanged();
  }

  void _submit() {
    final a = Anomaly(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      category: _category,
      at: _pin!,
      firstReportedAt: DateTime.now(),
      reportCount: 1,
      status: AnomalyStatus.pending,
      updates: [if (_note.text.trim().isNotEmpty) _note.text.trim()],
    );
    widget.anomalies.add(a);
    widget.onAnomaliesChanged();
    setState(() {
      _note.clear();
      _pin = null;
      _picking = false;
      _detailId = a.id;
      _expanded = true;
      _toast = '已標示在地圖上（示範，未傳送）';
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = _sorted;
    final point = _pointIndex != null && points.isNotEmpty ? points[_pointIndex! % points.length] : null;
    final isHome = _pointIndex == null;
    final path = point != null ? DemoGeo.lRoute(_start, _at(point)) : (isHome ? DemoGeo.homeRoute : <LatLng>[]);
    final active = widget.anomalies.where((a) => a.status != AnomalyStatus.cleared).toList();
    final avoided = active.where((a) => (a.at.lng - 121.5).abs() < .00005 || ((a.at.lat - 25.001).abs() < .00005 && a.at.lng < 121.5006)).length;
    final detail = _detailId == null ? null : widget.anomalies.where((a) => a.id == _detailId).firstOrNull;
    final picked = points.where((p) => p.id == _pickedPointId).firstOrNull ?? points.firstOrNull;
    final title = _pointsView ? '附近求助地點' : '${widget.position == null ? '示範起點' : '目前位置'} → ${isHome ? '家' : '求助地點'}';
    final meters = routeMeters(path);

    final (String summary, Widget body) = switch (true) {
      _ when _picking || _pin != null => ('回報狀況', _pin == null ? _pickSheet() : _formSheet()),
      _ when detail != null => ('${anomalyCategoryLabel[detail.category]}・${anomalyStatusLabel[detail.status]}', _detailSheet(detail)),
      _ when _pointsView => ('附近求助地點', _pointsSheet(points, picked)),
      _ => (path.isEmpty ? '最近求助地點' : '${walkMinutes(meters)} 分鐘・${isHome ? '回家・已繞開 $avoided 個異常回報' : point!.name}', _routeSheet(path, meters, isHome, point, avoided)),
    };

    return Scaffold(
      backgroundColor: SwColors.bg,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DemoMap(
                    start: _start,
                    points: points,
                    anomalies: widget.anomalies,
                    path: _pointsView ? const [] : path,
                    showShortcut: isHome && !_pointsView,
                    homeActive: isHome || _pointsView,
                    selectedPointId: _pointsView ? picked?.id : point?.id,
                    selectedAnomalyId: detail?.id,
                    pin: _pin,
                    onAnomaly: (id) => setState(() {
                      _detailId = id;
                      _toast = null;
                      _picking = false;
                      _pin = null;
                      _expanded = true;
                    }),
                    onPoint: _pointsView ? (id) => setState(() => _pickedPointId = id) : null,
                    onPick: _picking
                        ? (at) => setState(() {
                            _pin = at;
                            _expanded = true;
                          })
                        : null,
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwRoundButton(icon: Icons.arrow_back_ios_new_rounded, label: '返回', onTap: widget.onBack),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Container(
                                  height: swTouch,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(color: SwColors.surface, borderRadius: BorderRadius.circular(24), boxShadow: SwShadow.float),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.place_outlined, size: 20, color: SwColors.brandDeep),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: AnimatedSwitcher(
                                          duration: SwMotion.of(context, 200),
                                          child: Text(title, key: ValueKey(title), style: SwText.bodyStrong, overflow: TextOverflow.ellipsis),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const SwMockBadge(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SwRoundButton(icon: _legend ? Icons.close_rounded : Icons.layers_outlined, label: _legend ? '關閉圖例' : '顯示圖例', onTap: () => setState(() => _legend = !_legend)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: MediaQuery.paddingOf(context).top + 64,
                  child: AnimatedSwitcher(
                    duration: SwMotion.of(context, 180),
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: a, alignment: Alignment.topRight, child: c),
                    ),
                    child: _legend ? _Legend(pointsView: _pointsView, showShortcut: isHome && !_pointsView) : const SizedBox.shrink(),
                  ),
                ),
                if (_picking && _pin == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: MediaQuery.paddingOf(context).top + 100,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: SwColors.warnBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: SwColors.warnText),
                        boxShadow: SwShadow.float,
                      ),
                      child: Text(
                        '點地圖選擇要回報的位置，或點 ⚠ 更新既有回報',
                        textAlign: TextAlign.center,
                        style: SwText.bodyStrong.copyWith(color: SwColors.warnText),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _Sheet(expanded: _expanded, summary: summary, onToggle: () => setState(() => _expanded = !_expanded), toast: _toast, child: body),
          _BottomBar(onCall: widget.onCall, onEmergency: widget.onEmergency),
        ],
      ),
    );
  }

  Widget _routeSheet(List<LatLng> path, int meters, bool isHome, sw.AssistancePoint? point, int avoided) {
    final ps = widget.pointsState;
    final destName = isHome ? '家' : point?.name ?? '求助地點';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Segmented(homeSelected: isHome, onHome: () => setState(() => _pointIndex = null), onPoint: () => setState(() => _pointIndex = 0)),
        const SizedBox(height: 12),
        if (!isHome && ps.loading)
          const SwSkeleton(rows: 2)
        else if (!isHome && ps.error != null)
          SwStateMessage(icon: Icons.cloud_off_rounded, title: '求助地點暫時載入失敗', message: ps.error!, actionLabel: '再試一次', onAction: ps.onRetry, error: true)
        else if (!isHome && point == null)
          SwStateMessage(icon: Icons.search_off_rounded, title: '附近還沒有求助地點資料', message: '這不代表附近沒有求助管道。可以先走回家路線，或直接按緊急求助。', actionLabel: '改走回家路線', onAction: () => setState(() => _pointIndex = null))
        else ...[
          Row(
            children: [
              AnimatedSwitcher(
                duration: SwMotion.of(context, 250),
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: Tween(begin: .8, end: 1.0).animate(a),
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: Text.rich(
                  key: ValueKey(meters),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${walkMinutes(meters)}',
                        style: SwText.title.copyWith(fontSize: 44, height: 1, color: SwColors.brandDeep),
                      ),
                      TextSpan(text: ' 分鐘', style: SwText.heading),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${isHome ? '回家' : destName}・約 $meters 公尺', style: SwText.secondary, overflow: TextOverflow.ellipsis),
                    if (isHome) _AvoidBadge(count: avoided) else Text('${_kind[point!.kind]}・${_openLong[point.availability]}', style: SwText.secondary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isHome) SwChip(label: '下一個求助地點', icon: Icons.swap_horiz_rounded, onTap: widget.pointsState.points.length < 2 ? null : () => setState(() => _pointIndex = _pointIndex! + 1)),
              SwChip(
                label: '回報狀況',
                icon: Icons.campaign_outlined,
                onTap: () => setState(() {
                  _picking = true;
                  _toast = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StepsToggle(open: _stepsOpen, count: routeSteps(path).length + 1, onTap: () => setState(() => _stepsOpen = !_stepsOpen)),
          AnimatedSize(
            duration: SwMotion.of(context, 220),
            curve: SwMotion.curve,
            alignment: Alignment.topCenter,
            child: _stepsOpen ? _StepsList(steps: routeSteps(path), arrive: destName, home: isHome) : const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }

  Widget _pickSheet() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('要回報哪裡？', style: SwText.heading),
      const SizedBox(height: 4),
      Text('在地圖上點一下位置，或用你現在的位置。', style: SwText.secondary),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SwChip(label: '用我目前的位置', icon: Icons.my_location_rounded, onTap: () => setState(() => _pin = _start)),
          SwChip(label: '取消回報', icon: Icons.close_rounded, onTap: () => setState(() => _picking = false)),
        ],
      ),
    ],
  );

  Widget _formSheet() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('這裡發生什麼事？', style: SwText.heading),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in AnomalyCategory.values)
            AnimatedContainer(
              duration: SwMotion.of(context, 160),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: _category == c ? SwShadow.card : null),
              child: SwPressable(
                onTap: () => setState(() => _category = c),
                selected: _category == c,
                color: _category == c ? SwColors.warnBg : SwColors.surface,
                border: BorderSide(color: _category == c ? SwColors.warnText : SwColors.border, width: _category == c ? 2 : 1),
                radius: 24,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: swTouch,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_category == c) ...[const Icon(Icons.check_rounded, size: 18, color: SwColors.warnText), const SizedBox(width: 4)],
                      Text(anomalyCategoryLabel[c]!, style: SwText.bodyStrong.copyWith(color: _category == c ? SwColors.warnText : SwColors.text)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _note,
        maxLength: 60,
        style: SwText.body,
        decoration: InputDecoration(
          labelText: '補充一句（選填）',
          labelStyle: SwText.secondary,
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: SwColors.brandDeep, width: 2),
          ),
        ),
      ),
      Text('示範模式：只會標在你的畫面上，不會傳送給任何人。', style: SwText.small),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SwPrimaryButton(label: '標示到地圖', icon: Icons.add_location_alt_outlined, onTap: _submit),
          SwChip(label: '重新選位置', onTap: () => setState(() => _pin = null)),
        ],
      ),
    ],
  );

  Widget _detailSheet(Anomaly a) {
    final at = AnomalyStatus.values.indexOf(a.status);
    final t = a.firstReportedAt.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_rounded, color: SwColors.warnMark),
            const SizedBox(width: 6),
            Expanded(child: Text(anomalyCategoryLabel[a.category]!, style: SwText.heading)),
            SwRoundButton(icon: Icons.close_rounded, label: '關閉回報詳情', onTap: () => setState(() => _detailId = null)),
          ],
        ),
        Text('${a.reportCount} 則回報・首次回報 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}', style: SwText.secondary),
        const SizedBox(height: 12),
        for (final (i, st) in AnomalyStatus.values.indexed)
          _StepRow(
            index: i + 1,
            done: i < at,
            now: i == at,
            last: i == AnomalyStatus.values.length - 1,
            text:
                '${anomalyStatusLabel[st]}${st == AnomalyStatus.forwardedDemo
                    ? '（示範，未實際送出）'
                    : st == AnomalyStatus.cleared
                    ? '（警方確認後移除）'
                    : ''}',
          ),
        if (a.updates.isNotEmpty) ...[const SizedBox(height: 4), for (final u in a.updates) Text('・$u', style: SwText.secondary)],
        if (a.status != AnomalyStatus.cleared) ...[
          const SizedBox(height: 12),
          Text('你現在看到的狀況是？', style: SwText.bodyStrong),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SwChip(label: '仍在發生', icon: Icons.priority_high_rounded, onTap: () => _update(a, '有人回報：仍在發生', bump: true)),
              SwChip(label: '看起來沒事了', icon: Icons.check_circle_outline_rounded, onTap: () => _update(a, '有人回報：現場看起來已經沒事（待確認）', bump: false)),
            ],
          ),
          if (widget.onSms != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => widget.onSms!(a),
              icon: const Icon(Icons.sms_outlined),
              label: Text(
                '需要報警？準備簡訊內容',
                style: SwText.bodyStrong.copyWith(color: SwColors.brandDeep, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _pointsSheet(List<sw.AssistancePoint> points, sw.AssistancePoint? picked) {
    final ps = widget.pointsState;
    if (ps.loading) return const SwSkeleton();
    if (ps.error != null) return SwStateMessage(icon: Icons.cloud_off_rounded, title: '求助地點暫時載入失敗', message: ps.error!, actionLabel: '再試一次', onAction: ps.onRetry, error: true);
    if (points.isEmpty) {
      return const SwStateMessage(icon: Icons.search_off_rounded, title: '附近還沒有求助地點資料', message: '這不代表附近沒有求助管道。遇到危險請直接按緊急求助。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('離你最近的 ${points.length} 個求助地點', style: SwText.heading),
        const SizedBox(height: 8),
        for (final p in points) ...[
          _PlaceCard(
            point: p,
            meters: metersBetween(_start, _at(p)).round(),
            open: p.id == picked?.id,
            onTap: () => setState(() => _pickedPointId = p.id),
            onGo: () => setState(() {
              _pointIndex = points.indexOf(p);
              _pointsView = false;
              _stepsOpen = false;
            }),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 可收合的底部資訊框：點把手或摘要列切換；收合時只留一行摘要，地圖露出更多。
class _Sheet extends StatelessWidget {
  const _Sheet({required this.expanded, required this.summary, required this.onToggle, required this.toast, required this.child});
  final bool expanded;
  final String summary;
  final VoidCallback onToggle;
  final String? toast;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: SwColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      boxShadow: SwShadow.sheet,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: expanded ? '收合資訊框' : '展開資訊框：$summary',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if ((v > 200 && expanded) || (v < -200 && !expanded)) onToggle();
            },
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: SwColors.border, borderRadius: BorderRadius.circular(2)),
                    ),
                    AnimatedSize(
                      duration: SwMotion.of(context, 200),
                      child: expanded
                          ? const SizedBox(height: 8, width: double.infinity)
                          : SizedBox(
                              height: swTouch,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(summary, style: SwText.bodyStrong, overflow: TextOverflow.ellipsis),
                                  ),
                                  const Icon(Icons.expand_less_rounded, color: SwColors.brandDeep),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: SwMotion.of(context, 260),
          curve: SwMotion.curve,
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .5),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: SwMotion.of(context, 220),
                          transitionBuilder: (c, a) => SizeTransition(
                            sizeFactor: a,
                            child: FadeTransition(opacity: a, child: c),
                          ),
                          child: toast == null ? const SizedBox(width: double.infinity) : Padding(key: ValueKey(toast), padding: const EdgeInsets.only(bottom: 8), child: _Toast(toast!)),
                        ),
                        child,
                      ],
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

/// 回家／最近求助地點：選取底塊會滑動到選到的那一邊。
class _Segmented extends StatelessWidget {
  const _Segmented({required this.homeSelected, required this.onHome, required this.onPoint});
  final bool homeSelected;
  final VoidCallback onHome, onPoint;
  @override
  Widget build(BuildContext context) {
    Widget item(String label, IconData icon, bool on, VoidCallback tap) => Expanded(
      child: Semantics(
        button: true,
        selected: on,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: swTouch,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: on ? SwColors.brandDeep : SwColors.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: SwMotion.of(context, 200),
                    style: SwText.bodyStrong.copyWith(color: on ? SwColors.brandDeep : SwColors.textSecondary),
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: SwColors.bg, borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: SwMotion.of(context, 240),
              curve: SwMotion.curve,
              alignment: homeSelected ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: .5,
                child: Container(
                  decoration: BoxDecoration(
                    color: SwColors.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: SwColors.brand),
                    boxShadow: SwShadow.card,
                  ),
                ),
              ),
            ),
          ),
          Row(children: [item('回家', Icons.home_outlined, homeSelected, onHome), item('最近求助地點', Icons.local_police_outlined, !homeSelected, onPoint)]),
        ],
      ),
    );
  }
}

/// 本服務的賣點：已繞開幾個異常回報（出現時輕微放大）。
class _AvoidBadge extends StatelessWidget {
  const _AvoidBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: .85, end: 1),
    duration: SwMotion.of(context, 300),
    curve: Curves.easeOutBack,
    builder: (_, s, child) => Transform.scale(scale: s, alignment: Alignment.centerLeft, child: child),
    child: Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SwColors.brandSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SwColors.brand),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_outlined, size: 18, color: SwColors.brandDeep),
          const SizedBox(width: 4),
          Flexible(
            child: Text('已繞開 $count 個異常回報', style: SwText.bodyStrong.copyWith(color: SwColors.brandDeep)),
          ),
        ],
      ),
    ),
  );
}

class _StepsToggle extends StatelessWidget {
  const _StepsToggle({required this.open, required this.count, required this.onTap});
  final bool open;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    color: SwColors.bg,
    pressedColor: SwColors.brandSoft,
    border: const BorderSide(color: SwColors.border),
    radius: 10,
    semanticsLabel: open ? '收合文字路線' : '展開文字路線，共 $count 個步驟',
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: SizedBox(
      height: swTouch,
      child: Row(
        children: [
          const Icon(Icons.format_list_numbered_rounded, color: SwColors.brandDeep),
          const SizedBox(width: 8),
          Text('文字路線', style: SwText.bodyStrong),
          const Spacer(),
          Text(open ? '收合' : '$count 個步驟', style: SwText.secondary.copyWith(color: SwColors.brandDeep)),
          AnimatedRotation(
            turns: open ? .5 : 0,
            duration: SwMotion.of(context, 200),
            child: const Icon(Icons.expand_more_rounded, color: SwColors.brandDeep),
          ),
        ],
      ),
    ),
  );
}

class _StepsList extends StatelessWidget {
  const _StepsList({required this.steps, required this.arrive, required this.home});
  final List<RouteStep> steps;
  final String arrive;
  final bool home;
  static const _turn = {StepDir.north: 0.0, StepDir.east: .25, StepDir.south: .5, StepDir.west: .75};
  @override
  Widget build(BuildContext context) {
    Widget row(Widget icon, String text, {String? meters, bool end = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: end ? SwColors.brandDeep : SwColors.brandSoft),
            child: icon,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: SwText.heading.copyWith(fontSize: 20))),
          if (meters != null) Text(meters, style: SwText.secondary),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (final s in steps)
            row(
              RotationTransition(
                turns: AlwaysStoppedAnimation(_turn[s.dir]!),
                child: const Icon(Icons.arrow_upward_rounded, color: SwColors.brandDeep),
              ),
              '往${stepDirLabel[s.dir]}走',
              meters: '約 ${s.meters} 公尺',
            ),
          row(Icon(home ? Icons.home_rounded : Icons.place_rounded, color: SwColors.onDeep, size: 20), '抵達$arrive', end: true),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.done, required this.now, required this.last, required this.text});
  final int index;
  final bool done, now, last;
  final String text;
  @override
  Widget build(BuildContext context) {
    final circleColor = done
        ? SwColors.brandDeep
        : now
        ? SwColors.warnBg
        : SwColors.surface;
    final border = done
        ? SwColors.brandDeep
        : now
        ? SwColors.warnText
        : SwColors.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: circleColor,
                  border: Border.all(color: border, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded, size: 14, color: SwColors.onDeep)
                    : Text('$index', style: SwText.small.copyWith(fontSize: 12, height: 1, color: now ? SwColors.warnText : SwColors.textSecondary)),
              ),
              if (!last) Expanded(child: Container(width: 2, color: done ? SwColors.brandDeep : SwColors.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(text, style: now ? SwText.bodyStrong : SwText.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.point, required this.meters, required this.open, required this.onTap, required this.onGo});
  final sw.AssistancePoint point;
  final int meters;
  final bool open;
  final VoidCallback onTap, onGo;
  @override
  Widget build(BuildContext context) {
    final p = point;
    final known = p.availability == sw.OpeningStatus.open;
    return AnimatedContainer(
      duration: SwMotion.of(context, 200),
      decoration: BoxDecoration(
        color: SwColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: open ? SwColors.brand : SwColors.border, width: open ? 2 : 1),
        boxShadow: open ? SwShadow.float : SwShadow.card,
      ),
      child: Column(
        children: [
          SwPressable(
            onTap: onTap,
            radius: 12,
            selected: open,
            semanticsLabel: '${p.name}，${_kind[p.kind]}，約 $meters 公尺，${_open[p.availability]}',
            padding: const EdgeInsets.all(12),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: SwColors.brandDeep),
                    child: Text(pointGlyph[p.kind]!, style: SwText.bodyStrong.copyWith(color: SwColors.onDeep)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: SwText.bodyStrong),
                        Text('${_kind[p.kind]}・約 $meters 公尺・步行 ${walkMinutes(meters)} 分鐘', style: SwText.secondary),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: known ? SwColors.brandSoft : SwColors.warnBg, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      _open[p.availability]!,
                      style: SwText.small.copyWith(color: known ? SwColors.brandDeep : SwColors.warnText, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: SwMotion.of(context, 220),
            curve: SwMotion.curve,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwPrimaryButton(label: '帶我去這裡', icon: Icons.directions_walk_rounded, onTap: onGo),
                        const Divider(color: SwColors.border, height: 24),
                        _Fact('地址', p.address ?? '尚未提供'),
                        _Fact('電話', p.publicPhone ?? '尚未提供'),
                        _Fact('營業資訊', '${_openLong[p.availability]}（確認時間：${p.availabilityCheckedAt ?? '尚未提供'}）'),
                        _Fact('合作認可', switch (p.recognition) {
                          sw.ConfirmedRecognition() => '認可資料附有證據',
                          _ => '尚無已確認的認可資料',
                        }),
                        _Fact('資料來源', '${p.source.title}・${p.source.dataMode == sw.DataMode.mock ? '示範資料' : '真實資料'}'),
                        _Fact('資料更新', p.source.dataUpdatedAt ?? '尚未提供'),
                        const SizedBox(height: 4),
                        Text('顯示據點不代表已通知、有人值勤或已受理求助。', style: SwText.small),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text(label, style: SwText.secondary)),
        Expanded(child: Text(value, style: SwText.body)),
      ],
    ),
  );
}

class _Toast extends StatelessWidget {
  const _Toast(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SwColors.brandSoft,
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: SwColors.brandDeep, width: 4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: SwColors.brandDeep, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: SwText.bodyStrong)),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.pointsView, required this.showShortcut});
  final bool pointsView, showShortcut;
  @override
  Widget build(BuildContext context) {
    Widget item(Widget key, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 22, child: Center(child: key)),
          const SizedBox(width: 6),
          Text(text, style: SwText.body),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: SwColors.surface, borderRadius: BorderRadius.circular(12), boxShadow: SwShadow.float),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('圖例', style: SwText.bodyStrong),
          if (pointsView)
            item(
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: SwColors.brandDeep),
              ),
              '求助地點',
            )
          else
            item(
              Container(
                width: 18,
                height: 5,
                decoration: BoxDecoration(color: SwColors.brandDeep, borderRadius: BorderRadius.circular(3)),
              ),
              '建議路線',
            ),
          if (showShortcut)
            item(
              const Text(
                '···',
                style: TextStyle(color: TPColors.grayscale500, fontWeight: FontWeight.w900),
              ),
              '較短但經過異常',
            ),
          item(const Icon(Icons.warning_rounded, size: 18, color: SwColors.warnMark), '異常回報'),
          item(const Icon(Icons.home_rounded, size: 18, color: SwColors.brandDeep), '家'),
          Text('示範地圖，非實際路網', style: SwText.small),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onCall, required this.onEmergency});
  final VoidCallback onCall, onEmergency;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: SwColors.surface,
      border: Border(top: BorderSide(color: SwColors.border)),
    ),
    padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
    child: Row(
      children: [
        SwPressable(
          onTap: onCall,
          color: SwColors.surface,
          pressedColor: SwColors.brandSoft,
          border: const BorderSide(color: SwColors.border),
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: swTouchLarge,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_in_talk_outlined, color: SwColors.text),
                const SizedBox(width: 8),
                Text('模擬來電', style: SwText.bodyStrong),
              ],
            ),
          ),
        ),
        const Spacer(),
        const SizedBox(width: 24),
        SwSosButton(onTap: onEmergency),
      ],
    ),
  );
}
