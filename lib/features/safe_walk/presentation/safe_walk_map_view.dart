import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_sources.dart';
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

/// 前往目前目的地的路線狀態（M2 RouteService → M1 提供）。
/// [result] 為 null 且不在計算中＝尚未配置：畫面改用示範路線與示範起點，並標示「示範路線」，不與真實位置混用。
class RouteState {
  const RouteState({this.result, this.loading = false, this.onRetry});
  final sw.RouteResult? result;
  final bool loading;
  final VoidCallback? onRetry;

  bool get configured => loading || result != null;
  sw.RouteCandidate? get best => switch (result) {
    sw.RouteSuccess(:final routes) when routes.isNotEmpty => routes.first,
    _ => null,
  };

  /// 計算失敗，或成功但沒有任何路線。
  bool get failed => !loading && result != null && best == null;
  String get failReason => switch (result) {
    sw.RouteFailure(:final reason) when reason.trim().isNotEmpty => reason,
    _ => '目前找不到可步行的路線。',
  };
  String get failTitle => switch (result) {
    sw.RouteFailure(status: sw.RouteFailureStatus.providerUnavailable) => '路線服務暫時無法使用',
    sw.RouteFailure(status: sw.RouteFailureStatus.invalidInput) => '起點或目的地有問題',
    sw.RouteFailure(status: sw.RouteFailureStatus.cancelled) => '路線計算已取消',
    _ => '找不到回家路線',
  };
  List<LatLng>? get path => best?.geometry.coordinates.map((c) => LatLng(c.latitude, c.longitude)).toList(growable: false);
  int? get meters => best?.distanceMeters.round();
  int? get minutes {
    final b = best;
    if (b == null) return null;
    final sec = b.durationSeconds;
    return sec == null ? walkMinutes(b.distanceMeters.round()) : (sec / 60).ceil().clamp(1, 999);
  }

  bool get live => result?.mode == sw.DataMode.live;
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
    required this.places,
    required this.placeId,
    required this.onSelectPlace,
    required this.onAddPlace,
    required this.onDeletePlace,
    this.onSms,
    this.startView = MapStartView.route,
    this.routeState = const RouteState(),
  });

  /// 前往目前目的地（回家／常用地點）的路線；求助地點的路線仍是示範。
  final RouteState routeState;
  final List<SavedPlace> places;
  final String placeId;
  final ValueChanged<String> onSelectPlace, onDeletePlace;
  final void Function(String name, LatLng at) onAddPlace;
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
  _SheetSize _size = _SheetSize.normal;
  bool _legend = false;
  LatLng? _pin;
  String? _detailId, _pickedPointId, _toast;
  bool _stepsOpen = false;

  /// 正在新增的地點名稱；不為 null 時，點地圖是選這個地點的位置。
  String? _newPlaceName;
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
      _toast = '已更新這個回報';
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
      if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
      _toast = '已標示在地圖上';
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = _sorted;
    final point = _pointIndex != null && points.isNotEmpty ? points[_pointIndex! % points.length] : null;
    final isHome = _pointIndex == null;
    final place = widget.places.firstWhere((p) => p.id == widget.placeId, orElse: () => widget.places.first);
    final atHome = isHome && place.isHome;
    final rs = widget.routeState;
    // 尚未配置路線時用示範起點畫示範路線；計算中或失敗時不畫線。
    final demoHome = isHome && !rs.configured;
    final path = point != null ? DemoGeo.lRoute(_start, _at(point)) : (!isHome ? <LatLng>[] : (rs.path ?? (demoHome ? placeRoute(DemoGeo.start, place) : const <LatLng>[])));
    final avoided = avoidedCount(widget.anomalies);
    final detail = _detailId == null ? null : widget.anomalies.where((a) => a.id == _detailId).firstOrNull;
    final picked = points.where((p) => p.id == _pickedPointId).firstOrNull ?? points.firstOrNull;
    final title = _pointsView ? '附近求助地點' : '${widget.position == null || demoHome ? '起點' : '目前位置'} → ${isHome ? place.label : '求助地點'}';
    final meters = (isHome ? rs.meters : null) ?? routeMeters(path);
    final minutes = (isHome ? rs.minutes : null) ?? walkMinutes(meters);

    final (String summary, Widget body) = switch (true) {
      _ when _newPlaceName != null => ('新增地點', _newPlaceSheet()),
      _ when _picking || _pin != null => ('回報狀況', _pin == null ? _pickSheet() : _formSheet()),
      _ when detail != null => ('${anomalyCategoryLabel[detail.category]}・${anomalyStatusLabel[detail.status]}', _detailSheet(detail)),
      _ when _pointsView => ('附近求助地點', _pointsSheet(points, picked)),
      _ => (
        switch (true) {
          _ when isHome && rs.loading => '路線計算中…',
          _ when isHome && rs.failed => rs.failTitle,
          _ when path.isEmpty => '最近求助地點',
          _ => '$minutes 分鐘・${isHome ? (atHome && demoHome ? '回家・已繞開 $avoided 個異常回報' : (place.isHome ? '回家' : '到${place.label}')) : point!.name}',
        },
        _routeSheet(path, meters, minutes, isHome, point, avoided, place),
      ),
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
                    showShortcut: atHome && demoHome && !_pointsView,
                    homeActive: isHome || _pointsView,
                    selectedPointId: _pointsView ? picked?.id : point?.id,
                    selectedAnomalyId: detail?.id,
                    pin: _pin,
                    onAnomaly: (id) => setState(() {
                      _detailId = id;
                      _toast = null;
                      _picking = false;
                      _pin = null;
                      if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
                    }),
                    onPoint: _pointsView ? (id) => setState(() => _pickedPointId = id) : null,
                    onPick: _newPlaceName != null
                        ? (at) {
                            widget.onAddPlace(_newPlaceName!, at);
                            setState(() {
                              _toast = '已新增「$_newPlaceName」（只存在這支手機）';
                              _newPlaceName = null;
                              _pointIndex = null;
                            });
                          }
                        : _picking
                        ? (at) => setState(() {
                            _pin = at;
                            if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
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
                        // 標題區佔滿中間，圖例／回報固定貼齊右邊。
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: _pointsView ? null : () => _openPlaces(context),
                                child: Semantics(
                                  header: true,
                                  button: !_pointsView,
                                  hint: _pointsView ? null : '點兩下更換目的地',
                                  child: Container(
                                    height: swTouch,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(color: SwColors.surface, borderRadius: BorderRadius.circular(24), boxShadow: SwShadow.float),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.place_outlined, size: 20, color: SwColors.brand),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration: SwMotion.of(context, 200),
                                            child: Text(title, key: ValueKey(title), style: SwText.bodyStrong, overflow: TextOverflow.ellipsis),
                                          ),
                                        ),
                                        if (!_pointsView) const Icon(Icons.expand_more_rounded, color: SwColors.brand),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SwMockBadge(text: '路線僅供參考・請留意實際路況'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_size != _SheetSize.full)
                          Row(
                            children: [
                              _MapTool(
                                icon: _legend ? Icons.close_rounded : Icons.layers_outlined,
                                caption: '圖例',
                                semantics: _legend ? '關閉圖例' : '顯示圖例',
                                selected: _legend,
                                onTap: () => setState(() {
                                  // 圖例與回報一次只開一個，避免疊在一起。
                                  _legend = !_legend;
                                  if (_legend) {
                                    _picking = false;
                                    _pin = null;
                                  }
                                }),
                              ),
                              const SizedBox(width: 8),
                              _MapTool(
                                icon: Icons.campaign_rounded,
                                caption: '回報',
                                semantics: '回報狀況，在地圖上標出異常',
                                selected: _picking,
                                warn: true,
                                onTap: () => setState(() {
                                  _picking = !_picking;
                                  _legend = false;
                                  _pin = null;
                                  _detailId = null;
                                  _toast = null;
                                  if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
                                }),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: MediaQuery.paddingOf(context).top + 72,
                  child: AnimatedSwitcher(
                    duration: SwMotion.of(context, 180),
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: a, alignment: Alignment.topRight, child: c),
                    ),
                    child: _legend ? _Legend(pointsView: _pointsView, showShortcut: atHome && demoHome && !_pointsView) : const SizedBox.shrink(),
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
                        _newPlaceName != null ? '點地圖選擇「$_newPlaceName」的位置' : '點地圖選擇要回報的位置，或點 ⚠ 更新既有回報',
                        textAlign: TextAlign.center,
                        style: SwText.bodyStrong.copyWith(color: SwColors.warnText),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_size == _SheetSize.full)
            Expanded(
              flex: 4,
              child: _Sheet(
                size: _size,
                summary: summary,
                onSize: (v) => setState(() {
                  _size = v;
                  if (v == _SheetSize.full) _stepsOpen = true;
                }),
                toast: _toast,
                child: body,
              ),
            )
          else
            _Sheet(
              size: _size,
              summary: summary,
              onSize: (v) => setState(() {
                _size = v;
                if (v == _SheetSize.full) _stepsOpen = true;
              }),
              toast: _toast,
              child: body,
            ),
          _BottomBar(onCall: widget.onCall, onEmergency: widget.onEmergency),
        ],
      ),
    );
  }

  Widget _routeSheet(List<LatLng> path, int meters, int minutes, bool isHome, sw.AssistancePoint? point, int avoided, SavedPlace place) {
    final ps = widget.pointsState;
    final rs = widget.routeState;
    final destName = isHome ? place.label : point?.name ?? '求助地點';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Segmented(
          firstLabel: place.isHome ? '回家' : '去${place.label}',
          firstIcon: _placeIcon(place),
          homeSelected: isHome,
          onHome: () => setState(() => _pointIndex = null),
          onPoint: () => setState(() => _pointIndex = 0),
        ),
        const SizedBox(height: 12),
        if (isHome && rs.loading)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('正在計算避開異常回報的路線…', style: SwText.bodyStrong),
                const SizedBox(height: 8),
                const ExcludeSemantics(child: SwSkeleton(rows: 2)),
              ],
            ),
          )
        else if (isHome && rs.failed) ...[
          SwStateMessage(icon: Icons.wrong_location_outlined, title: rs.failTitle, message: rs.failReason, actionLabel: rs.onRetry == null ? null : '再試一次', onAction: rs.onRetry, error: true),
          const SizedBox(height: 8),
          SwChip(label: '改去最近求助地點', icon: Icons.local_police_outlined, onTap: () => setState(() => _pointIndex = 0)),
        ] else if (!isHome && ps.loading)
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
                        text: '$minutes',
                        style: SwText.title.copyWith(height: 1, color: SwColors.brand),
                      ),
                      TextSpan(text: ' 分鐘', style: SwText.bodyStrong),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${isHome ? (place.isHome ? '回家' : '到${place.label}') : destName}・約 $meters 公尺', style: SwText.secondary, overflow: TextOverflow.ellipsis),
                    if (isHome && rs.best != null)
                      Text(rs.best!.explanations.firstOrNull ?? (rs.best!.walkingNetworkVerified ? '已規劃步行路線' : '路線未經步行路網驗證'), style: SwText.secondary, maxLines: 2, overflow: TextOverflow.ellipsis)
                    else if (isHome && place.isHome)
                      _AvoidBadge(count: avoided)
                    else if (isHome)
                      Text('路線僅供參考', style: SwText.secondary)
                    else
                      Text('${_kind[point!.kind]}・${_openLong[point.availability]}', style: SwText.secondary),
                  ],
                ),
              ),
              if (!isHome) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: '換下一個求助地點',
                  child: _SwapButton(onTap: widget.pointsState.points.length < 2 ? null : () => setState(() => _pointIndex = _pointIndex! + 1)),
                ),
              ],
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
          const Align(alignment: Alignment.centerLeft, child: SwSourcesLink()),
        ],
      ],
    );
  }

  IconData _placeIcon(SavedPlace p) => switch (p.id) {
    'home' => Icons.home_outlined,
    'work' => Icons.work_outline_rounded,
    _ => Icons.place_outlined,
  };

  /// 目的地選單：常用地點（家、公司…）可切換、刪除、新增（新增後在地圖上點位置）。只存在記憶體。
  Future<void> _openPlaces(BuildContext context) async {
    final name = TextEditingController();
    var adding = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SwColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: SwColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(header: true, child: Text('要去哪裡？', style: SwText.heading)),
                const SizedBox(height: 4),
                Text('常用地點只存在這支手機，不會上傳。', style: SwText.small),
                const SizedBox(height: 12),
                for (final p in widget.places)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SwPressable(
                      onTap: () {
                        widget.onSelectPlace(p.id);
                        setState(() => _pointIndex = null);
                        Navigator.of(sheetContext).pop();
                      },
                      selected: p.id == widget.placeId,
                      color: p.id == widget.placeId ? SwColors.brandSoft : SwColors.bg,
                      border: BorderSide(color: p.id == widget.placeId ? SwColors.brand : SwColors.border),
                      radius: 10,
                      semanticsLabel: '前往${p.label}${p.id == widget.placeId ? '，目前選擇' : ''}',
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            Icon(_placeIcon(p), color: SwColors.brand),
                            const SizedBox(width: 12),
                            Expanded(child: Text(p.label, style: SwText.bodyStrong)),
                            if (p.id == widget.placeId) const Icon(Icons.check_rounded, color: SwColors.brand),
                            if (!p.isHome)
                              IconButton(
                                tooltip: '刪除${p.label}',
                                icon: const Icon(Icons.delete_outline_rounded, color: SwColors.textSecondary),
                                onPressed: () {
                                  widget.onDeletePlace(p.id);
                                  setSheet(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                AnimatedSize(
                  duration: SwMotion.of(sheetContext, 200),
                  child: !adding
                      ? SwChip(label: '新增地點', icon: Icons.add_location_alt_outlined, onTap: () => setSheet(() => adding = true))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: name,
                              autofocus: true,
                              maxLength: 10,
                              style: SwText.body,
                              onChanged: (_) => setSheet(() {}),
                              decoration: InputDecoration(
                                labelText: '地點名稱（例如：學校、爸媽家）',
                                labelStyle: SwText.secondary,
                                counterText: '',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SwPrimaryButton(
                              label: '在地圖上選位置',
                              icon: Icons.touch_app_outlined,
                              onTap: name.text.trim().isEmpty
                                  ? null
                                  : () {
                                      setState(() {
                                        _newPlaceName = name.text.trim();
                                        _picking = false;
                                        _legend = false;
                                        _pin = null;
                                        _detailId = null;
                                        if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
                                      });
                                      Navigator.of(sheetContext).pop();
                                    },
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 等關閉動畫結束（輸入框還在畫面上）再釋放。
    Future.delayed(const Duration(milliseconds: 600), name.dispose);
  }

  Widget _newPlaceSheet() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('新增「$_newPlaceName」', style: SwText.heading),
      const SizedBox(height: 4),
      Text('在地圖上點一下這個地點的位置。', style: SwText.secondary),
      const SizedBox(height: 8),
      SwChip(label: '取消新增', icon: Icons.close_rounded, onTap: () => setState(() => _newPlaceName = null)),
    ],
  );

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
            borderSide: const BorderSide(color: SwColors.brand, width: 2),
          ),
        ),
      ),
      Text('回報會標示在地圖上。', style: SwText.small),
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
                    ? ''
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
                style: SwText.bodyStrong.copyWith(color: SwColors.brandText, decoration: TextDecoration.underline),
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

enum _SheetSize { collapsed, normal, full }

/// 底部資訊框三段：收合（只留一行摘要）、一般、滿版。
/// 點把手：收合↔一般（滿版時點一下回到一般）；往上滑放大一段、往下滑縮小一段。
class _Sheet extends StatelessWidget {
  const _Sheet({required this.size, required this.summary, required this.onSize, required this.toast, required this.child});
  final _SheetSize size;
  final String summary;
  final ValueChanged<_SheetSize> onSize;
  final String? toast;
  final Widget child;

  void _tap() => onSize(size == _SheetSize.normal ? _SheetSize.collapsed : _SheetSize.normal);

  void _drag(double v) {
    if (v < -200) onSize(size == _SheetSize.collapsed ? _SheetSize.normal : _SheetSize.full);
    if (v > 200) onSize(size == _SheetSize.full ? _SheetSize.normal : _SheetSize.collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final label = switch (size) {
      _SheetSize.collapsed => '展開資訊框：$summary',
      _SheetSize.normal => '收合資訊框',
      _SheetSize.full => '資訊框縮回一般大小',
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: SwColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: SwShadow.sheet,
      ),
      child: Column(
        mainAxisSize: size == _SheetSize.full ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: size != _SheetSize.collapsed,
            label: label,
            onIncrease: size == _SheetSize.full ? null : () => _drag(-300),
            onDecrease: size == _SheetSize.collapsed ? null : () => _drag(300),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              onVerticalDragEnd: (d) => _drag(d.primaryVelocity ?? 0),
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
                        child: switch (size) {
                          _SheetSize.collapsed => SizedBox(
                            height: swTouch,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(summary, style: SwText.bodyStrong, overflow: TextOverflow.ellipsis),
                                ),
                                const Icon(Icons.expand_less_rounded, color: SwColors.brand),
                              ],
                            ),
                          ),
                          _SheetSize.normal => const SizedBox(height: 8, width: double.infinity),
                          _SheetSize.full => const SizedBox(
                            height: 28,
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Icon(Icons.expand_more_rounded, color: SwColors.brand),
                            ),
                          ),
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (size == _SheetSize.full)
            Expanded(
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
            )
          else
            AnimatedSize(
              duration: SwMotion.of(context, 280),
              curve: SwMotion.curve,
              alignment: Alignment.topCenter,
              child: size == _SheetSize.collapsed
                  ? const SizedBox(width: double.infinity)
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: h * .5),
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
}

/// 回家／最近求助地點：選取底塊會滑動到選到的那一邊。
class _Segmented extends StatelessWidget {
  const _Segmented({required this.firstLabel, required this.firstIcon, required this.homeSelected, required this.onHome, required this.onPoint});
  final String firstLabel;
  final IconData firstIcon;
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
                Icon(icon, size: 20, color: on ? SwColors.brand : SwColors.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: SwMotion.of(context, 200),
                    style: SwText.bodyStrong.copyWith(color: on ? SwColors.brandText : SwColors.textSecondary),
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
          Row(children: [item(firstLabel, firstIcon, homeSelected, onHome), item('最近求助地點', Icons.local_police_outlined, !homeSelected, onPoint)]),
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
          const Icon(Icons.verified_outlined, size: 18, color: SwColors.brand),
          const SizedBox(width: 4),
          Flexible(
            child: Text('已繞開 $count 個異常回報', style: SwText.bodyStrong.copyWith(color: SwColors.brandText)),
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
          const Icon(Icons.format_list_numbered_rounded, color: SwColors.brand),
          const SizedBox(width: 8),
          // 標題佔滿左側，「N 個步驟／收合」與箭頭固定靠右。
          Expanded(
            child: Text('文字路線', maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: SwText.bodyStrong),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: Text(
              open ? '收合' : '$count 個步驟',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: SwText.secondary.copyWith(color: SwColors.brandText),
            ),
          ),
          AnimatedRotation(
            turns: open ? .5 : 0,
            duration: SwMotion.of(context, 200),
            child: const Icon(Icons.expand_more_rounded, color: SwColors.brand),
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
            decoration: BoxDecoration(shape: BoxShape.circle, color: end ? SwColors.brand : SwColors.brandSoft),
            child: icon,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: SwText.bodyStrong)),
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
                child: const Icon(Icons.arrow_upward_rounded, color: SwColors.brand),
              ),
              '往${stepDirLabel[s.dir]}走',
              meters: '約 ${s.meters} 公尺',
            ),
          row(Icon(home ? Icons.home_rounded : Icons.place_rounded, color: SwColors.onBrand, size: 20), '抵達$arrive', end: true),
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
        ? SwColors.brand
        : now
        ? SwColors.warnBg
        : SwColors.surface;
    final border = done
        ? SwColors.brand
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
                    ? const Icon(Icons.check_rounded, size: 14, color: SwColors.onBrand)
                    : Text('$index', style: SwText.caption.copyWith(height: 1, color: now ? SwColors.warnText : SwColors.textSecondary)),
              ),
              if (!last) Expanded(child: Container(width: 2, color: done ? SwColors.brand : SwColors.border)),
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
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: SwColors.brand),
                    child: Text(pointGlyph[p.kind]!, style: SwText.bodyStrong.copyWith(color: SwColors.onBrand)),
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
                    child: Text(_open[p.availability]!, style: SwText.smallStrong.copyWith(color: known ? SwColors.brandText : SwColors.warnText)),
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
        border: const Border(left: BorderSide(color: SwColors.brand, width: 4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: SwColors.brand, size: 20),
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
                decoration: const BoxDecoration(shape: BoxShape.circle, color: SwColors.brand),
              ),
              '求助地點',
            )
          else
            item(
              Container(
                width: 18,
                height: 5,
                decoration: BoxDecoration(color: SwColors.brand, borderRadius: BorderRadius.circular(3)),
              ),
              '建議路線',
            ),
          if (showShortcut) item(Text('···', style: SwText.bodyStrong.copyWith(color: TPColors.grayscale500)), '較短但經過異常'),
          item(const Icon(Icons.warning_rounded, size: 18, color: SwColors.warnMark), '異常回報'),
          item(const Icon(Icons.home_rounded, size: 18, color: SwColors.brand), '家'),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onCall, required this.onEmergency});
  final VoidCallback onCall, onEmergency;
  @override
  Widget build(BuildContext context) => SwActionBar(
    secondary: SwSecondaryAction(icon: Icons.phone_in_talk_outlined, label: '模擬來電', onTap: onCall),
    onEmergency: onEmergency,
  );
}

/// 換下一個求助地點：圖示鈕（交換箭頭），旁邊就是地點名稱，語意清楚；讀屏與長按提示「換下一個求助地點」。
class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: onTap == null ? null : SwShadow.card),
    child: SwPressable(
      onTap: onTap,
      color: onTap == null ? TPColors.grayscale100 : SwColors.brandSoft,
      pressedColor: TPColors.primary100,
      border: BorderSide(color: onTap == null ? SwColors.border : SwColors.brand),
      radius: swTouch / 2,
      semanticsLabel: '換下一個求助地點',
      child: SizedBox(
        width: swTouch,
        height: swTouch,
        child: Icon(Icons.swap_horiz_rounded, color: onTap == null ? SwColors.textSecondary : SwColors.brand),
      ),
    ),
  );
}

/// 地圖右上工具（像地圖 App 的圖層鈕）：圖示＋兩字說明，56×56，選取時換底色。
class _MapTool extends StatelessWidget {
  const _MapTool({required this.icon, required this.caption, required this.semantics, required this.onTap, this.selected = false, this.warn = false});
  final IconData icon;
  final String caption, semantics;
  final VoidCallback onTap;
  final bool selected, warn;
  @override
  Widget build(BuildContext context) {
    final fg = warn ? SwColors.warnText : SwColors.brandText;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: SwShadow.float),
      child: SwPressable(
        onTap: onTap,
        selected: selected,
        color: selected ? (warn ? SwColors.warnBg : SwColors.brandSoft) : SwColors.surface,
        pressedColor: warn ? SwColors.warnBg : SwColors.brandSoft,
        border: selected ? BorderSide(color: fg, width: 2) : null,
        radius: 14,
        semanticsLabel: semantics,
        child: SizedBox(
          width: 52,
          height: 52,
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 24),
                Text(caption, maxLines: 1, style: SwText.caption.copyWith(color: fg, height: 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
