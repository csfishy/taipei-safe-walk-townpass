import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/route_instructions.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/util/tp_colors.dart';

const _kind = {
  sw.AssistancePointKind.police: '警察機關',
  sw.AssistancePointKind.partnerStore: '合作商店',
  sw.AssistancePointKind.convenienceStore: '便利商店',
  sw.AssistancePointKind.publicFacility: '公共設施',
};
const _open = {
  sw.OpeningStatus.open: '營業中',
  sw.OpeningStatus.closed: '未營業',
  sw.OpeningStatus.unknown: '營業未知',
};
const _openLong = {
  sw.OpeningStatus.open: '資料顯示營業中',
  sw.OpeningStatus.closed: '資料顯示未營業',
  sw.OpeningStatus.unknown: '營業時間不確定',
};

enum MapStartView { route, points, report }

/// 求助地點資料的狀態（由 M1 → M4 提供）：載入中、錯誤、或清單（可能是空的）。
class PointsState {
  const PointsState({
    this.points = const [],
    this.loading = false,
    this.error,
    this.onRetry,
    this.routes = const {},
  });
  final List<sw.AssistancePoint> points;
  final bool loading;
  final String? error;

  /// Mock：重新載入；Live：查附近營業中的店家並比較路線。
  final VoidCallback? onRetry;

  /// Live：到每個地點的步行路線（id → 結果）；有路線時 [points] 已依
  /// 「最安全、再最快」排好，不再依直線距離重排。
  final Map<String, sw.RouteResult> routes;
}

/// 前往目前目的地的路線狀態（M2 RouteService → M1 提供）。
/// 未配置時只有 Mock 可使用示範路線；Live 明確顯示尚未配置，不補示範路徑。
class RouteState {
  const RouteState({
    this.result,
    this.loading = false,
    this.allowDemoFallback = true,
    this.onRetry,
    this.selected = 0,
  });
  final sw.RouteResult? result;
  final bool loading;
  final bool allowDemoFallback;
  final VoidCallback? onRetry;

  /// 使用者選的路線（[options] 的索引）。
  final int selected;
  RouteState select(int i) => RouteState(
    result: result,
    loading: loading,
    allowDemoFallback: allowDemoFallback,
    onRetry: onRetry,
    selected: i,
  );

  bool get configured => !allowDemoFallback || loading || result != null;

  /// 可選的路線；真實避讓時依「完全避開 → 不經過中心 → 最短」排列。
  List<sw.RouteCandidate> get options => switch (result) {
    sw.RouteSuccess(:final routes) => routes,
    _ => const [],
  };
  sw.RouteCandidate? get best =>
      options.isEmpty ? null : options[selected.clamp(0, options.length - 1)];

  /// 起點或終點已在回報範圍內時的提醒。
  String? get insideWarning => switch (result) {
    sw.RouteSuccess(:final warnings) =>
      warnings
          .where((w) => w.contains('緩衝區內') || w.contains('回報範圍內'))
          .firstOrNull,
    _ => null,
  };

  /// 計算失敗，或成功但沒有任何路線。
  bool get failed => !loading && configured && best == null;
  String get failReason => switch (result) {
    null when !allowDemoFallback => '尚未配置步行路線服務，請稍後再試。',
    sw.RouteFailure(:final reason) when reason.trim().isNotEmpty => reason,
    _ => '目前找不到可步行的路線。',
  };
  String get failTitle => switch (result) {
    null when !allowDemoFallback => '路線服務尚未配置',
    sw.RouteFailure(status: sw.RouteFailureStatus.providerUnavailable) =>
      '路線服務暫時無法使用',
    sw.RouteFailure(status: sw.RouteFailureStatus.invalidInput) => '起點或目的地有問題',
    sw.RouteFailure(status: sw.RouteFailureStatus.cancelled) => '路線計算已取消',
    _ => '找不到回家路線',
  };
  List<LatLng>? get path => best?.geometry.coordinates
      .map((c) => LatLng(c.latitude, c.longitude))
      .toList(growable: false);
  int? get meters => best?.distanceMeters.round();
  int? get minutes {
    final b = best;
    if (b == null) return null;
    final sec = b.durationSeconds;
    return sec == null
        ? (live ? null : walkMinutes(b.distanceMeters.round()))
        : (sec / 60).ceil().clamp(1, 999);
  }

  bool get live => result?.mode == sw.DataMode.live;

  List<String> get warnings => {
    ...switch (result) {
      sw.RouteSuccess(:final warnings) => warnings,
      sw.RouteFailure(:final warnings) => warnings,
      _ => const <String>[],
    },
    ...?best?.warnings,
  }.toList(growable: false);
}

/// 地圖：預設回家路線（繞開異常回報）；「最近求助地點」為中性的第二個目的地；回報狀況直接在地圖上操作。
/// 底部資訊框可收合，讓地圖露出更多。
class SafeWalkMapView extends StatefulWidget {
  const SafeWalkMapView({
    super.key,
    required this.position,
    this.heading,
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
    this.onEditPlace,
    this.onSms,
    this.startView = MapStartView.route,
    this.routeState = const RouteState(),
    this.manualStart,
    this.onStartChanged,
    this.crimeSpots = const [],
    this.crimeQueryStatus,
    this.onManageCrimeConsent,
    this.onManageRoutingConsent,
    this.routingConsent = false,
    this.crimeConsent = false,
    this.destinationConfigured = true,
    this.canSetHome = false,
    this.showMapTiles = true,
    this.targetPointId,
    this.onTarget,
    this.onStartNavigation,
    this.onEndNavigation,
  });

  /// 目前導航目標的求助地點 id；null＝目的地。是它時 [routeState] 就是往這個地點的路線。
  final String? targetPointId;

  /// 使用者換了導航目標（求助地點；null＝回目的地）。
  final ValueChanged<sw.AssistancePoint?>? onTarget;
  final VoidCallback? onStartNavigation, onEndNavigation;

  /// 犯罪參考位置及產品設定的避讓緩衝（紫色，非案發範圍）。
  final List<CrimeSpot> crimeSpots;
  final String? crimeQueryStatus;
  final VoidCallback? onManageCrimeConsent, onManageRoutingConsent;

  /// Whether the walker currently allows the third-party route query.
  final bool routingConsent;

  /// Whether the walker currently allows the crime reference query.
  final bool crimeConsent;
  final bool destinationConfigured;

  /// 還沒設定家時，能不能直接在地圖上點選並儲存「家」。
  final bool canSetHome;
  final bool showMapTiles;

  /// 使用者在地圖上指定的起點；null＝用目前位置（GPS）。
  final LatLng? manualStart;

  /// 設定（或改回 GPS＝null）起點；null 時選單不顯示起點設定。
  final ValueChanged<LatLng?>? onStartChanged;

  /// 前往目前目的地（回家／常用地點）的路線；求助地點的路線仍是示範。
  final RouteState routeState;
  final List<SavedPlace> places;
  final String placeId;
  final ValueChanged<String> onSelectPlace, onDeletePlace;
  final void Function(String name, LatLng at) onAddPlace;

  /// 編輯常用地點的名稱與位置；null 時不顯示編輯。
  final Future<void> Function(String id, String name, LatLng at)? onEditPlace;
  final sw.Position? position;

  /// 手機朝向（度，從北方順時針）；有值時目前位置畫成指向箭頭。
  final double? heading;
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

  /// 文字路線先隱藏（保留程式，之後要再打開改成 true）。
  static const _showTextSteps = false;

  /// 開始導覽：鏡頭跟著目前位置，資訊框顯示下一個指示。
  bool _navigating = false;

  /// 選了第幾條路線；路線結果更新時回到預設（第一條＝最能避開回報的）。
  int _routeChoice = 0;
  RouteState get _rs => widget.routeState.select(_routeChoice);

  @override
  void didUpdateWidget(SafeWalkMapView old) {
    super.didUpdateWidget(old);
    final currentPoint = _pointIndex == null || old.pointsState.points.isEmpty
        ? null
        : old
              .pointsState
              .points[_pointIndex! % old.pointsState.points.length]
              .id;
    final oldRoute = currentPoint == null || old.targetPointId == currentPoint
        ? old.routeState.result
        : old.pointsState.routes[currentPoint];
    final nextRoute =
        currentPoint == null || widget.targetPointId == currentPoint
        ? widget.routeState.result
        : widget.pointsState.routes[currentPoint];
    if (oldRoute != nextRoute || old.placeId != widget.placeId) {
      _routeChoice = 0;
    }
    // 地點陸續出現、最後再依安全與時間重排：畫面停在使用者正在看的那一個。
    final target = widget.targetPointId;
    if (target != null && _pointIndex != null) {
      final i = _sorted.indexWhere((p) => p.id == target);
      if (i >= 0) _pointIndex = i;
    }
    final detail = _crimeDetail;
    if (detail != null) {
      _crimeDetail = widget.crimeSpots
          .where((spot) => spot.id == detail.id)
          .firstOrNull;
    }
    // 店家結果更新時，同一店家的新路線也交回共用導航控制器。
    if (!mapEquals(old.pointsState.routes, widget.pointsState.routes) &&
        widget.pointsState.routes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _targetCurrentPoint();
      });
    }
  }

  /// 還沒設定家、而且可以在地圖上直接設定。
  bool get _homeUnset =>
      !widget.destinationConfigured &&
      widget.canSetHome &&
      widget.onEditPlace != null &&
      widget.placeId == 'home';

  /// 正在新增的地點名稱；不為 null 時，點地圖是選這個地點的位置。
  /// 還沒設定家時，一進地圖就直接請使用者點選家的位置。
  late String? _newPlaceName = _homeUnset ? '家' : null;

  /// 正在看的犯罪參考位置（點紫點）。
  CrimeSpot? _crimeDetail;

  /// 正在編輯的常用地點（null＝新增）。
  late String? _editingPlaceId = _homeUnset ? 'home' : null;

  bool get _settingHome => _editingPlaceId == 'home' && !widget.destinationConfigured;

  void _startSetHome() => setState(() {
    _newPlaceName = '家';
    _editingPlaceId = 'home';
    _picking = false;
    _legend = false;
    _pin = null;
    _detailId = null;
    if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
  });

  /// 正在地圖上選起點。
  bool _pickingStart = false;
  AnomalyCategory _category = AnomalyCategory.suspicious;
  final _note = TextEditingController();

  LatLng get _start {
    final position = widget.position;
    if (position != null) {
      return LatLng(position.coordinates.lat, position.coordinates.lng);
    }
    if (widget.manualStart != null) return widget.manualStart!;
    final path = widget.routeState.path;
    if (path != null && path.isNotEmpty) return path.first;
    // A default city viewport is not a location fix. Live mode hides its start
    // marker until an actual GPS fix, manual origin, or route is available.
    return widget.routeState.allowDemoFallback
        ? DemoGeo.start
        : const LatLng(25.033, 121.5654);
  }

  LatLng _at(sw.AssistancePoint p) =>
      LatLng(p.coordinates.lat, p.coordinates.lng);

  List<sw.AssistancePoint> get _sorted => widget.pointsState.routes.isNotEmpty
      ? widget.pointsState.points
      : ([...widget.pointsState.points]..sort(
          (a, b) => metersBetween(
            _start,
            _at(a),
          ).compareTo(metersBetween(_start, _at(b))),
        ));

  /// 改看最近求助地點；Live 還沒有結果時才去查（使用者主動點了才查）。
  void _showPoints() {
    setState(() {
      _pointIndex = 0;
      _routeChoice = 0;
      _stepsOpen = false;
    });
    _loadPointsIfNeeded();
    _targetCurrentPoint();
  }

  /// 正在看某個求助地點的路線時，把它設為導航目標（有真實路線才需要）。
  void _targetCurrentPoint() {
    final points = _sorted;
    final i = _pointIndex;
    if (i == null || _pointsView || points.isEmpty) return;
    final p = points[i % points.length];
    final route = widget.pointsState.routes[p.id];
    if (route != null &&
        (widget.targetPointId != p.id ||
            !identical(widget.routeState.result, route))) {
      widget.onTarget?.call(p);
    }
  }

  void _targetDestination() {
    setState(() {
      _pointIndex = null;
      _routeChoice = 0;
    });
    if (widget.targetPointId != null) widget.onTarget?.call(null);
  }

  void _loadPointsIfNeeded() {
    final ps = widget.pointsState;
    if (ps.points.isEmpty && !ps.loading && ps.error == null) {
      ps.onRetry?.call();
    }
  }

  /// 導覽中的資訊框：下一個指示、距離，和剩餘距離與時間。
  Widget _navSheet(RouteState rs, String destination) {
    final best = rs.best;
    final position = widget.position;
    final instructions = best == null ? null : routeInstructions[best];
    final hasInstructions = instructions != null && instructions.isNotEmpty;
    final progress = position == null || best == null
        ? null
        : routeProgress(
            best.geometry.coordinates,
            instructions ?? const [],
            position.coordinates,
          );
    String distance(double m) => m >= 1000
        ? '${(m / 1000).toStringAsFixed(1)} 公里'
        : '${(m / 10).round() * 10} 公尺';
    final next = progress?.next;
    final (String now, String then) = switch (progress) {
      _ when best == null => (
        rs.loading ? '路線重新規劃中…' : '暫時無法導覽',
        rs.loading ? '可隨時結束導覽。' : rs.failReason,
      ),
      null => ('等待定位…', '請確認已開啟定位；位置更新後就會顯示下一個指示。'),
      _ when !hasInstructions => ('此路線未提供轉向指示', '請依地圖路線及現場路況行走。'),
      _ when next == null => (
        '前往$destination',
        '${distance(progress.toNextMeters)}後抵達',
      ),
      _ => (
        '${distance(progress.toNextMeters)}後 ${next.action}',
        '接著${next.follow}',
      ),
    };
    final line = best?.geometry.coordinates;
    final totalMeters = line == null || line.isEmpty
        ? 0.0
        : routeProgress(
            line,
            const [],
            sw.Coordinates(lat: line.first.latitude, lng: line.first.longitude),
          ).remainingMeters;
    final duration = best?.durationSeconds;
    final remainingMinutes =
        duration == null || progress == null || totalMeters <= 0
        ? null
        : (duration *
                  (progress.remainingMeters / totalMeters).clamp(0.0, 1.0) /
                  60)
              .ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: SwColors.brand,
                ),
                child: Icon(
                  next == null
                      ? Icons.place_rounded
                      : _StepsList._turnIcon[next.turn],
                  color: SwColors.onBrand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(now, style: SwText.heading),
                    Text(then, style: SwText.secondary),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 8),
          Text(
            '剩 ${distance(progress.remainingMeters)}・${remainingMinutes == null ? '時間未知' : '約 $remainingMinutes 分鐘'}',
            style: SwText.bodyStrong,
          ),
          Text('偏離路線會自動重新規劃', style: SwText.small),
        ],
        const SizedBox(height: 12),
        SwSecondaryAction(
          label: '結束導覽',
          icon: Icons.close_rounded,
          onTap: () {
            widget.onEndNavigation?.call();
            setState(() => _navigating = false);
          },
        ),
      ],
    );
  }

  /// 定位不到時，改在地圖上選起點，選好就從那裡重新找求助地點。
  List<Widget> _pickStartChip() => [
    if (widget.onStartChanged != null) ...[
      const SizedBox(height: 8),
      SwChip(
        label: '在地圖上選起點',
        icon: Icons.edit_location_alt_outlined,
        onTap: () => setState(() {
          _pickingStart = true;
          if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
        }),
      ),
    ],
  ];

  /// 路線服務給的逐路口文字（Valhalla 路名）；沒有時用幾何推算方向。
  List<RouteInstruction>? _instructions(RouteState rs) {
    final best = rs.best;
    final list = best == null ? null : routeInstructions[best];
    return list == null || list.isEmpty ? null : list;
  }

  /// 經過幾個避讓緩衝區（未解除的回報＋犯罪參考位置）。
  int _passes(sw.RouteCandidate r) =>
      widget.anomalies
          .where(
            (a) =>
                a.status != AnomalyStatus.cleared &&
                routePassesWithin(
                  r.geometry.coordinates,
                  a.at,
                  reportAvoidRadiusMeters,
                ),
          )
          .length +
      widget.crimeSpots
          .where(
            (c) => routePassesWithin(
              r.geometry.coordinates,
              c.at,
              reportAvoidRadiusMeters,
            ),
          )
          .length;

  /// 一個店家的代表路線：經過最少緩衝區，再來最快。
  sw.RouteCandidate? _bestOf(sw.RouteResult? result) {
    if (result is! sw.RouteSuccess || result.routes.isEmpty) return null;
    double secs(sw.RouteCandidate r) =>
        r.durationSeconds ?? r.distanceMeters / 1.2;
    return result.routes.reduce((a, b) {
      final pa = _passes(a), pb = _passes(b);
      return pa != pb ? (pa < pb ? a : b) : (secs(a) <= secs(b) ? a : b);
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _update(Anomaly a, String text, {required bool bump}) {
    HapticFeedback.lightImpact(); // 送出成功的觸覺回饋
    setState(() {
      if (bump) {
        a.reportCount++;
        if (a.status == AnomalyStatus.pending) {
          a.status = AnomalyStatus.multiReported;
        }
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
    HapticFeedback.lightImpact(); // 送出成功的觸覺回饋
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
    final point = _pointIndex != null && points.isNotEmpty
        ? points[_pointIndex! % points.length]
        : null;
    final isHome = _pointIndex == null;
    final place = widget.places.firstWhere(
      (p) => p.id == widget.placeId,
      orElse: () => widget.places.first,
    );
    final atHome = isHome && place.isHome;
    // Live 求助地點：和目的地一樣的真實避讓路線。
    final targeted = point != null && widget.targetPointId == point.id;
    final storeResult = point == null
        ? null
        : widget.pointsState.routes[point.id];
    final rs = targeted || storeResult == null
        ? _rs
        : RouteState(
            result: storeResult,
            allowDemoFallback: false,
            selected: _routeChoice,
          );
    final routed = isHome || targeted || storeResult != null;
    // 尚未配置路線時用示範起點畫示範路線；計算中或失敗時不畫線。
    // 真實路線模式：起點與目的地確定、路線算出來之前，不畫示範路線也不顯示時間。
    final liveWired = widget.onStartChanged != null;
    final waitingRoute =
        isHome && liveWired && rs.result == null && !rs.loading;
    final demoHome = isHome && !rs.configured && !liveWired;
    final path = point != null
        ? (routed
              ? rs.path ?? const <LatLng>[]
              : DemoGeo.lRoute(_start, _at(point)))
        : (!isHome
              ? <LatLng>[]
              : (rs.path ??
                    (demoHome
                        ? placeRoute(DemoGeo.start, place)
                        : const <LatLng>[])));
    final avoided = avoidedCount(widget.anomalies);
    final detail = _detailId == null
        ? null
        : widget.anomalies.where((a) => a.id == _detailId).firstOrNull;
    final picked =
        points.where((p) => p.id == _pickedPointId).firstOrNull ??
        points.firstOrNull;
    final from = widget.manualStart != null
        ? '指定起點'
        : (!rs.live && (widget.position == null || demoHome) ? '起點' : '目前位置');
    final title = _pointsView
        ? (widget.onStartChanged == null
              ? '附近求助地點'
              : '${widget.manualStart != null ? '指定起點' : '目前位置'} → 附近求助地點')
        : '$from → ${isHome ? place.label : '求助地點'}';
    final meters = (routed ? rs.meters : null) ?? routeMeters(path);
    final int? minutes = routed && rs.live ? rs.minutes : walkMinutes(meters);

    final (String summary, Widget body) = switch (true) {
      _ when _newPlaceName != null => (
        _settingHome ? '設定「家」' : '新增地點',
        _newPlaceSheet(),
      ),
      _ when _pickingStart => ('設定起點', _startPickSheet()),
      _ when _crimeDetail != null => ('犯罪參考位置', _crimeSheet(_crimeDetail!)),
      _ when _picking || _pin != null => (
        '回報狀況',
        _pin == null ? _pickSheet() : _formSheet(),
      ),
      _ when detail != null => (
        '${anomalyCategoryLabel[detail.category]}・${anomalyStatusLabel[detail.status]}',
        _detailSheet(detail),
      ),
      _ when _navigating => (
        '導覽中',
        _navSheet(rs, isHome ? place.label : point?.name ?? '求助地點'),
      ),
      _ when _pointsView => ('附近求助地點', _pointsSheet(points, picked)),
      _ => (
        switch (true) {
          _ when waitingRoute => '設定起點與目的地',
          _ when isHome && rs.loading => '路線計算中…',
          _ when isHome && rs.failed => rs.failTitle,
          _ when path.isEmpty => '最近求助地點',
          _ =>
            '${minutes == null ? '時間未知' : '$minutes 分鐘'}・${isHome ? (atHome && demoHome ? '回家・示範：已繞開 $avoided 個示範回報' : (place.isHome ? '回家' : '到${place.label}')) : point!.name}',
        },
        _routeSheet(
          path,
          meters,
          minutes,
          isHome,
          point,
          avoided,
          place,
          rs: rs,
          points: points,
          routed: routed,
        ),
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
                    showTiles: widget.showMapTiles,
                    // 真實路線從使用者實際位置出發。
                    start:
                        widget.manualStart ??
                        (rs.live &&
                                routed &&
                                path.isNotEmpty &&
                                widget.position == null
                            ? path.first
                            : _start),
                    points: points,
                    heading: widget.position == null ? null : widget.heading,
                    follow: _navigating && widget.position != null
                        ? LatLng(
                            widget.position!.coordinates.lat,
                            widget.position!.coordinates.lng,
                          )
                        : null,
                    anomalies: widget.anomalies,
                    path: _pointsView ? const [] : path,
                    destination: place.at,
                    showDestination:
                        widget.destinationConfigured && place.at != null,
                    showStart:
                        widget.routeState.allowDemoFallback ||
                        widget.manualStart != null ||
                        widget.position != null ||
                        path.isNotEmpty,
                    onCrime: (i) => setState(() {
                      _crimeDetail = widget.crimeSpots[i];
                      _detailId = null;
                      _picking = false;
                      _pin = null;
                      _toast = null;
                      if (_size == _SheetSize.collapsed) {
                        _size = _SheetSize.normal;
                      }
                    }),
                    crimeSpots: rs.live
                        ? [
                            for (final c in widget.crimeSpots)
                              (at: c.at, label: c.label),
                          ]
                        : const [],
                    showAttribution: false,
                    altPaths: _pointsView || !routed
                        ? const []
                        : [
                            for (final (i, r) in rs.options.indexed)
                              if (i != rs.selected)
                                [
                                  for (final c in r.geometry.coordinates)
                                    LatLng(c.latitude, c.longitude),
                                ],
                          ],
                    avoidRadiusMeters: rs.live ? reportAvoidRadiusMeters : 0,
                    showShortcut: atHome && demoHome && !_pointsView,
                    homeActive: isHome || _pointsView,
                    selectedPointId: _pointsView ? picked?.id : point?.id,
                    selectedAnomalyId: detail?.id,
                    pin: _pin,
                    onAnomaly: (id) => setState(() {
                      _crimeDetail = null;
                      _detailId = id;
                      _toast = null;
                      _picking = false;
                      _pin = null;
                      if (_size == _SheetSize.collapsed) {
                        _size = _SheetSize.normal;
                      }
                    }),
                    onPoint: _pointsView
                        ? (id) => setState(() => _pickedPointId = id)
                        : null,
                    onPick: _pickingStart
                        ? (at) {
                            widget.onStartChanged?.call(at);
                            // 起點已顯示在頂部列，不再另外跳「已設定起點」提示。
                            setState(() => _pickingStart = false);
                            // 正在找求助地點：從新的起點重新查。
                            if (_pointsView || _pointIndex != null) {
                              widget.pointsState.onRetry?.call();
                            }
                          }
                        : _newPlaceName != null
                        ? (at) async {
                            final editing = _editingPlaceId;
                            if (editing != null) {
                              try {
                                await widget.onEditPlace?.call(
                                  editing,
                                  _newPlaceName!,
                                  at,
                                );
                              } catch (_) {
                                if (mounted) {
                                  setState(() => _toast = '儲存失敗，請再試一次。');
                                }
                                return;
                              }
                            } else {
                              widget.onAddPlace(_newPlaceName!, at);
                            }
                            if (!mounted) return;
                            setState(() {
                              _toast = editing != null
                                  ? '已更新「$_newPlaceName」'
                                  : '已新增「$_newPlaceName」（本次使用期間保留）';
                              _editingPlaceId = null;
                              _newPlaceName = null;
                              _pointIndex = null;
                            });
                          }
                        : _picking
                        ? (at) => setState(() {
                            _pin = at;
                            if (_size == _SheetSize.collapsed) {
                              _size = _SheetSize.normal;
                            }
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
                        SwRoundButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          label: '返回',
                          onTap: widget.onBack,
                        ),
                        const SizedBox(width: 8),
                        // 標題區佔滿中間，圖例／回報固定貼齊右邊。
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: !_pointsView
                                    ? () => _openPlaces(context)
                                    : widget.onStartChanged == null
                                    ? null
                                    : () => _openStart(context),
                                child: Semantics(
                                  header: true,
                                  button:
                                      !_pointsView ||
                                      widget.onStartChanged != null,
                                  hint: !_pointsView
                                      ? '點兩下更換目的地'
                                      : widget.onStartChanged == null
                                      ? null
                                      : '點兩下更換起點',
                                  child: Container(
                                    height: swTouch,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SwColors.surface,
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: SwShadow.float,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.place_outlined,
                                          size: 20,
                                          color: SwColors.brand,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration: SwMotion.of(context, 200),
                                            child: Text(
                                              title,
                                              key: ValueKey(title),
                                              style: SwText.bodyStrong,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        if (!_pointsView ||
                                            widget.onStartChanged != null)
                                          const Icon(
                                            Icons.expand_more_rounded,
                                            color: SwColors.brand,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_size != _SheetSize.full)
                          Row(
                            children: [
                              _MapTool(
                                icon: _legend
                                    ? Icons.close_rounded
                                    : Icons.layers_outlined,
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
                                  if (_size == _SheetSize.collapsed) {
                                    _size = _SheetSize.normal;
                                  }
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
                      child: ScaleTransition(
                        scale: a,
                        alignment: Alignment.topRight,
                        child: c,
                      ),
                    ),
                    child: _legend
                        ? _Legend(
                            pointsView: _pointsView,
                            showShortcut: atHome && demoHome && !_pointsView,
                            live: rs.live,
                            crime: rs.live || widget.crimeSpots.isNotEmpty,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                if (_picking && _pin == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: MediaQuery.paddingOf(context).top + 100,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: SwColors.warnBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: SwColors.warnText),
                        boxShadow: SwShadow.float,
                      ),
                      child: Text(
                        _pickingStart
                            ? '點地圖選擇起點'
                            : _newPlaceName != null
                            ? '點地圖選擇「$_newPlaceName」的位置'
                            : '點地圖選擇要回報的位置，或點 ⚠ 更新既有回報',
                        textAlign: TextAlign.center,
                        style: SwText.bodyStrong.copyWith(
                          color: SwColors.warnText,
                        ),
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

  Widget _routeSheet(
    List<LatLng> path,
    int meters,
    int? minutes,
    bool isHome,
    sw.AssistancePoint? point,
    int avoided,
    SavedPlace place, {
    required RouteState rs,
    required List<sw.AssistancePoint> points,
    required bool routed,
  }) {
    final ps = widget.pointsState;
    final stores = !isHome && ps.routes.isNotEmpty;
    final destName = isHome ? place.label : point?.name ?? '求助地點';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Segmented(
          firstLabel: '目的地',
          firstIcon: _placeIcon(place),
          homeSelected: isHome,
          onHome: _targetDestination,
          onPoint: _showPoints,
        ),
        const SizedBox(height: 12),
        if (isHome &&
            widget.onStartChanged != null &&
            rs.result == null &&
            !rs.loading)
          SwStateMessage(
            icon: Icons.alt_route_rounded,
            title: '設定起點與目的地',
            message: '點上方「起點 → 目的地」選好出發地與要去的地方，就會顯示步行路線、時間與文字路線。',
            actionLabel: '選擇起點與目的地',
            onAction: () => _openPlaces(context),
          )
        else if (routed && rs.loading)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('正在計算步行路線…', style: SwText.bodyStrong),
                const SizedBox(height: 8),
                const ExcludeSemantics(child: SwSkeleton(rows: 2)),
              ],
            ),
          )
        else if (isHome && _homeUnset)
          SwStateMessage(
            icon: Icons.home_outlined,
            title: '還沒設定「家」',
            message: '在地圖上點一下家的位置，就會規劃回家路線。',
            actionLabel: '在地圖上設定家',
            onAction: _startSetHome,
          )
        else if (routed && rs.failed) ...[
          SwStateMessage(
            icon: Icons.wrong_location_outlined,
            title: rs.failTitle,
            message: rs.failReason,
            actionLabel: rs.onRetry == null ? null : '再試一次',
            onAction: rs.onRetry,
            error: true,
          ),
          if (isHome) ...[
            const SizedBox(height: 8),
            SwChip(
              label: '改去最近求助地點',
              icon: Icons.local_police_outlined,
              onTap: _showPoints,
            ),
          ],
        ] else if (!isHome && ps.loading && points.isEmpty)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.pointsState.onRetry == null || rs.allowDemoFallback
                      ? '正在載入求助地點…'
                      : '正在找附近的求助地點並比較路線…',
                  style: SwText.bodyStrong,
                ),
                const SizedBox(height: 8),
                const ExcludeSemantics(child: SwSkeleton(rows: 2)),
              ],
            ),
          )
        else if (!isHome && ps.error != null) ...[
          SwStateMessage(
            icon: Icons.cloud_off_rounded,
            title: '求助地點暫時載入失敗',
            message: ps.error!,
            actionLabel: '再試一次',
            onAction: ps.onRetry,
            error: true,
          ),
          ..._pickStartChip(),
        ] else if (!isHome && point == null)
          SwStateMessage(
            icon: Icons.search_off_rounded,
            title: '附近還沒有求助地點資料',
            message: '這不代表附近沒有求助管道。可以先走回家路線，或直接按緊急求助。',
            actionLabel: '改走回家路線',
            onAction: _targetDestination,
          )
        else ...[
          if (stores) ...[
            Semantics(
              header: true,
              child: Text('附近的求助地點', style: SwText.smallStrong),
            ),
            Text(
              ps.loading ? '先顯示最近的地點，其他地點的路線還在計算…' : '離你最近、資料標示營業中的地點；點一下可切換。',
              style: SwText.small,
            ),
            const SizedBox(height: 6),
            for (final (i, p) in points.indexed)
              if (_bestOf(ps.routes[p.id]) case final best?)
                _RouteOption(
                  label: p.availability == sw.OpeningStatus.unknown
                      ? '${p.name}（營業時間不確定）'
                      : p.name,
                  minutes: best.durationSeconds == null
                      ? null
                      : (best.durationSeconds! / 60).ceil(),
                  meters: best.distanceMeters.round(),
                  passes: _passes(best),
                  selected: p.id == point?.id,
                  onTap: () {
                    setState(() {
                      _pointIndex = i;
                      _routeChoice = 0;
                      _stepsOpen = false;
                    });
                    widget.onTarget?.call(p);
                  },
                ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              // 換路線或改道時，分鐘數從舊值滾到新值，看得出「改道了」。
              TweenAnimationBuilder<double>(
                tween: Tween(end: (minutes ?? 0).toDouble()),
                duration: SwMotion.of(context, 700),
                curve: SwMotion.curve,
                builder: (_, value, _) => Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: minutes == null ? '時間未知' : '${value.round()}',
                        style: SwText.title.copyWith(
                          height: 1,
                          color: SwColors.brand,
                        ),
                      ),
                      if (minutes != null)
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
                    Text(
                      '${isHome ? (place.isHome ? '回家' : '到${place.label}') : destName}・約 $meters 公尺',
                      style: SwText.secondary,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isHome && minutes != null && rs.options.length > 1)
                      _ExtraMinutes(
                        extra: minutes - rs.options
                            .map((r) => r.durationSeconds)
                            .whereType<num>()
                            .map((d) => (d / 60).ceil())
                            .fold(minutes, (a, b) => a < b ? a : b),
                      ),
                    if (isHome && rs.best != null && rs.options.length < 2)
                      Text(
                        rs.best!.explanations.firstOrNull ??
                            (rs.best!.walkingNetworkVerified
                                ? '已規劃步行路線'
                                : '路線未經步行路網驗證'),
                        style: SwText.secondary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (isHome && rs.best != null)
                      const SizedBox.shrink() // 路線卡片已列出各路線說明
                    else if (isHome && place.isHome && !rs.configured)
                      _AvoidBadge(count: avoided)
                    else if (isHome && place.isHome)
                      Text('路線未經步行路網驗證，不代表安全', style: SwText.secondary)
                    else if (isHome)
                      Text('路線僅供參考', style: SwText.secondary)
                    else
                      Text(
                        point!.name == _kind[point.kind]
                            ? _openLong[point.availability]!
                            : '${_kind[point.kind]}・${_openLong[point.availability]}',
                        style: SwText.secondary,
                      ),
                  ],
                ),
              ),
              if (!isHome && !stores) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: '換下一個求助地點',
                  child: _SwapButton(
                    onTap: widget.pointsState.points.length < 2
                        ? null
                        : () => setState(() => _pointIndex = _pointIndex! + 1),
                  ),
                ),
              ],
            ],
          ),
          if ((isHome || stores) && rs.live) ..._avoidSection(rs, home: isHome),
          if (routed && rs.live && rs.best != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SwPrimaryButton(
                label: '開始導覽',
                icon: Icons.navigation_rounded,
                onTap: () => setState(() {
                  widget.onStartNavigation?.call();
                  _navigating = true;
                  _size = _SheetSize.normal;
                }),
              ),
            ),
          ],
          if (_showTextSteps) ...[
            const SizedBox(height: 12),
            _StepsToggle(
              open: _stepsOpen,
              count: (_instructions(rs) ?? routeSteps(path)).length + 1,
              onTap: () => setState(() => _stepsOpen = !_stepsOpen),
            ),
            AnimatedSize(
              duration: SwMotion.of(context, 220),
              curve: SwMotion.curve,
              alignment: Alignment.topCenter,
              child: _stepsOpen
                  ? _StepsList(
                      steps: routeSteps(path),
                      instructions: _instructions(rs),
                      arrive: destName,
                      home: isHome,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ],
        // 一般的 OpenStreetMap 說明放在首頁「資料來源與授權」；這裡只留跟這條路線有關的提醒。
        for (final warning in rs.warnings)
          if (!warning.startsWith('依 OpenStreetMap 步行路網計算'))
            Text(warning, style: SwText.small),
        if (rs.live && widget.crimeQueryStatus != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              widget.crimeQueryStatus!,
              key: const Key('crime-query-status'),
              style: SwText.small,
            ),
          ),
        ],
      ],
    );
  }

  /// 真實路線：起訖在回報範圍內的提醒、可選路線、找不到避讓路線時改去求助地點。
  List<Widget> _avoidSection(RouteState rs, {bool home = true}) {
    final open = widget.anomalies
        .where((a) => a.status != AnomalyStatus.cleared)
        .toList();
    final passes = _passes;
    final noClear =
        (open.isNotEmpty || widget.crimeSpots.isNotEmpty) &&
        rs.options.isNotEmpty &&
        rs.options.every((r) => passes(r) > 0);
    return [
      if (rs.insideWarning != null) ...[
        const SizedBox(height: 8),
        SwMockBadge(text: rs.insideWarning!),
      ],
      if (rs.options.isNotEmpty) ...[
        const SizedBox(height: 12),
        Semantics(header: true, child: Text('選擇路線', style: SwText.smallStrong)),
        const SizedBox(height: 6),
        for (final (i, r) in rs.options.indexed)
          _RouteOption(
            label: r.explanations.firstOrNull ?? '步行路線',
            minutes: r.durationSeconds == null
                ? null
                : (r.durationSeconds! / 60).ceil(),
            meters: r.distanceMeters.round(),
            passes: passes(r),
            selected: i == rs.selected,
            onTap: () => setState(() => _routeChoice = i),
          ),
      ],
      if (noClear) ...[
        const SizedBox(height: 8),
        SwStateMessage(
          icon: Icons.wrong_location_outlined,
          title: '找不到避開緩衝區的路線',
          message: home
              ? '目前每條路線都會經過避讓緩衝區。可以改去最近的求助地點，或選一條經過較少緩衝區的路線。'
              : '目前每條路線都會經過避讓緩衝區。可以換一間店，或選一條經過較少緩衝區的路線。',
        ),
        if (home) ...[
          const SizedBox(height: 8),
          SwChip(
            label: '看最近求助地點',
            icon: Icons.local_police_outlined,
            onTap: _showPoints,
          ),
        ],
      ],
    ];
  }

  IconData _placeIcon(SavedPlace p) => switch (p.id) {
    'home' => Icons.home_outlined,
    'work' => Icons.work_outline_rounded,
    _ => Icons.place_outlined,
  };

  /// 點紫點：類別、日期、地點、來源、精度與限制（不放在路線資訊下方）。
  Widget _crimeSheet(CrimeSpot c) {
    final lines = c.label.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: crimeMarkColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(lines.first, style: SwText.bodyStrong)),
            IconButton(
              tooltip: '關閉',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _crimeDetail = null),
            ),
          ],
        ),
        for (final line in lines.skip(1)) Text(line, style: SwText.small),
        const SizedBox(height: 8),
        Text('50 公尺避讓緩衝區', style: SwText.smallStrong),
        Text(
          '紫色圓是產品設定的繞行距離；參考位置並非精確案發點，圓形不是官方認定的犯罪範圍，也不保證沿途安全。',
          style: SwText.small,
        ),
      ],
    );
  }

  Widget _startPickSheet() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('設定起點', style: SwText.heading),
      const SizedBox(height: 4),
      Text('在地圖上點一下你要出發的位置。', style: SwText.secondary),
      const SizedBox(height: 12),
      SwChip(
        label: '取消',
        icon: Icons.close_rounded,
        onTap: () => setState(() => _pickingStart = false),
      ),
    ],
  );

  /// 目的地選單：常用地點（家、公司…）可切換、刪除、新增（新增後在地圖上點位置）。只存在記憶體。
  /// 起點選項（目前位置／指定起點），路線與附近求助地點共用同一個設定。
  List<Widget> _startChoices(BuildContext sheetContext) => [
    _StartChoice(
      icon: Icons.my_location_rounded,
      label: '目前位置（GPS）',
      selected: widget.manualStart == null,
      onTap: () {
        widget.onStartChanged!(null);
        Navigator.of(sheetContext).pop();
        if (_pointsView || _pointIndex != null) {
          widget.pointsState.onRetry?.call();
        }
      },
    ),
    _StartChoice(
      icon: Icons.touch_app_outlined,
      label: widget.manualStart == null ? '在地圖上選起點' : '指定起點（點此重新選）',
      selected: widget.manualStart != null,
      onTap: () {
        setState(() {
          _pickingStart = true;
          _newPlaceName = null;
          _picking = false;
          _legend = false;
          _pin = null;
          _detailId = null;
          if (_size == _SheetSize.collapsed) _size = _SheetSize.normal;
        });
        Navigator.of(sheetContext).pop();
      },
    ),
  ];

  /// 附近求助地點頁：只選起點（和路線頁同一個起點設定）。
  Future<void> _openStart(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: SwColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('從哪裡出發？', style: SwText.heading),
            ),
            const SizedBox(height: 4),
            Text('沒有即時定位時，用指定起點找附近的店家。', style: SwText.small),
            const SizedBox(height: 8),
            ..._startChoices(sheetContext),
          ],
        ),
      ),
    ),
  );

  Future<void> _openPlaces(BuildContext context) async {
    final name = TextEditingController();
    var adding = false;
    String? editingId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SwColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
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
                    decoration: BoxDecoration(
                      color: SwColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.onStartChanged != null) ...[
                  Semantics(
                    header: true,
                    child: Text('從哪裡出發？', style: SwText.heading),
                  ),
                  const SizedBox(height: 8),
                  ..._startChoices(sheetContext),
                  const SizedBox(height: 12),
                ],
                Semantics(
                  header: true,
                  child: Text('要去哪裡？', style: SwText.heading),
                ),
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
                      color: p.id == widget.placeId
                          ? SwColors.brandSoft
                          : SwColors.bg,
                      border: BorderSide(
                        color: p.id == widget.placeId
                            ? SwColors.brand
                            : SwColors.border,
                      ),
                      radius: 10,
                      semanticsLabel:
                          '前往${p.label}${p.id == widget.placeId ? '，目前選擇' : ''}',
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            Icon(_placeIcon(p), color: SwColors.brand),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(p.label, style: SwText.bodyStrong),
                            ),
                            if (p.id == widget.placeId)
                              const Icon(
                                Icons.check_rounded,
                                color: SwColors.brand,
                              ),
                            if (widget.onEditPlace != null)
                              IconButton(
                                tooltip: '編輯${p.label}',
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: SwColors.textSecondary,
                                ),
                                onPressed: () => setSheet(() {
                                  adding = true;
                                  editingId = p.id;
                                  name.text = p.label;
                                }),
                              ),
                            if (!p.isHome)
                              IconButton(
                                tooltip: '刪除${p.label}',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: SwColors.textSecondary,
                                ),
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
                      ? SwChip(
                          label: '新增地點',
                          icon: Icons.add_location_alt_outlined,
                          onTap: () => setSheet(() => adding = true),
                        )
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
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SwPrimaryButton(
                              label: editingId != null
                                  ? '在地圖上重新選位置'
                                  : '在地圖上選位置',
                              icon: Icons.touch_app_outlined,
                              onTap: name.text.trim().isEmpty
                                  ? null
                                  : () {
                                      setState(() {
                                        _newPlaceName = name.text.trim();
                                        _editingPlaceId = editingId;
                                        _picking = false;
                                        _legend = false;
                                        _pin = null;
                                        _detailId = null;
                                        if (_size == _SheetSize.collapsed) {
                                          _size = _SheetSize.normal;
                                        }
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
      Text(
        _settingHome
            ? '家在哪裡？'
            : '${_editingPlaceId != null ? '編輯' : '新增'}「$_newPlaceName」',
        style: SwText.heading,
      ),
      const SizedBox(height: 4),
      Text(
        _settingHome
            ? '在地圖上點一下家的位置，就會規劃回家路線。位置只存在這支手機。'
            : '在地圖上點一下這個地點的位置。',
        style: SwText.secondary,
      ),
      const SizedBox(height: 8),
      SwChip(
        label: _settingHome
            ? '稍後再設定'
            : _editingPlaceId != null
            ? '取消編輯'
            : '取消新增',
        icon: Icons.close_rounded,
        onTap: () => setState(() {
          _newPlaceName = null;
          _editingPlaceId = null;
        }),
      ),
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
          SwChip(
            label: '用我目前的位置',
            icon: Icons.my_location_rounded,
            onTap: () => setState(() => _pin = _start),
          ),
          SwChip(
            label: '取消回報',
            icon: Icons.close_rounded,
            onTap: () => setState(() => _picking = false),
          ),
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
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: _category == c ? SwShadow.card : null,
              ),
              child: SwPressable(
                onTap: () => setState(() => _category = c),
                selected: _category == c,
                color: _category == c ? SwColors.warnBg : SwColors.surface,
                border: BorderSide(
                  color: _category == c ? SwColors.warnText : SwColors.border,
                  width: _category == c ? 2 : 1,
                ),
                radius: 24,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: swTouch,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_category == c) ...[
                        const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: SwColors.warnText,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        anomalyCategoryLabel[c]!,
                        style: SwText.bodyStrong.copyWith(
                          color: _category == c
                              ? SwColors.warnText
                              : SwColors.text,
                        ),
                      ),
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
      Row(
        children: [
          Expanded(
            child: SwPrimaryButton(
              label: '標示到地圖',
              icon: Icons.add_location_alt_outlined,
              onTap: _submit,
            ),
          ),
          const SizedBox(width: 8),
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
            Expanded(
              child: Text(
                anomalyCategoryLabel[a.category]!,
                style: SwText.heading,
              ),
            ),
            SwRoundButton(
              icon: Icons.close_rounded,
              label: '關閉回報詳情',
              onTap: () => setState(() => _detailId = null),
            ),
          ],
        ),
        Text(
          '${a.reportCount} 則回報・首次回報 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          style: SwText.secondary,
        ),
        const SizedBox(height: 12),
        for (final (i, st) in AnomalyStatus.values.indexed)
          _StepRow(
            index: i + 1,
            done: i < at,
            now: i == at,
            last: i == AnomalyStatus.values.length - 1,
            text:
                '${anomalyStatusLabel[st]}${st == AnomalyStatus.forwardedDemo
                    ? '（未發送任何通報）'
                    : st == AnomalyStatus.cleared
                    ? '（警方確認後移除）'
                    : ''}',
          ),
        if (a.updates.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final u in a.updates) Text('・$u', style: SwText.secondary),
        ],
        if (a.status != AnomalyStatus.cleared) ...[
          const SizedBox(height: 12),
          Text('你現在看到的狀況是？', style: SwText.bodyStrong),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SwChip(
                label: '仍在發生',
                icon: Icons.priority_high_rounded,
                onTap: () => _update(a, '有人回報：仍在發生', bump: true),
              ),
              SwChip(
                label: '看起來沒事了',
                icon: Icons.check_circle_outline_rounded,
                onTap: () => _update(a, '有人回報：現場看起來已經沒事（待確認）', bump: false),
              ),
            ],
          ),
          if (widget.onSms != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => widget.onSms!(a),
              icon: const Icon(Icons.sms_outlined),
              label: Text(
                '需要報警？準備簡訊內容',
                style: SwText.bodyStrong.copyWith(
                  color: SwColors.brandText,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _pointsSheet(
    List<sw.AssistancePoint> points,
    sw.AssistancePoint? picked,
  ) {
    final ps = widget.pointsState;
    if (ps.loading && points.isEmpty) return const SwSkeleton();
    if (ps.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwStateMessage(
            icon: Icons.cloud_off_rounded,
            title: '求助地點暫時載入失敗',
            message: ps.error!,
            actionLabel: '再試一次',
            onAction: ps.onRetry,
            error: true,
          ),
          ..._pickStartChip(),
        ],
      );
    }
    if (points.isEmpty) {
      return const SwStateMessage(
        icon: Icons.search_off_rounded,
        title: '附近還沒有求助地點資料',
        message: '這不代表附近沒有求助管道。遇到危險請直接按緊急求助。',
      );
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
            onGo: () {
              setState(() {
                _pointIndex = points.indexOf(p);
                _pointsView = false;
                _stepsOpen = false;
                _routeChoice = 0;
              });
              if (widget.pointsState.routes.containsKey(p.id)) {
                widget.onTarget?.call(p);
              }
            },
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
  const _Sheet({
    required this.size,
    required this.summary,
    required this.onSize,
    required this.toast,
    required this.child,
  });
  final _SheetSize size;
  final String summary;
  final ValueChanged<_SheetSize> onSize;
  final String? toast;
  final Widget child;

  void _tap() => onSize(
    size == _SheetSize.normal ? _SheetSize.collapsed : _SheetSize.normal,
  );

  void _drag(double v) {
    if (v < -200) {
      onSize(
        size == _SheetSize.collapsed ? _SheetSize.normal : _SheetSize.full,
      );
    }
    if (v > 200) {
      onSize(
        size == _SheetSize.full ? _SheetSize.normal : _SheetSize.collapsed,
      );
    }
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
        mainAxisSize: size == _SheetSize.full
            ? MainAxisSize.max
            : MainAxisSize.min,
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
                      // 灰色把手置中；OSM 版權標示放在同一行最右側（點了開授權頁）。
                      SizedBox(
                        height: 4,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: SwColors.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    unawaited(DemoMap.openAttribution(context)),
                                child: Text(
                                  '© OpenStreetMap',
                                  style: SwText.small.copyWith(
                                    color: SwColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSize(
                        duration: SwMotion.of(context, 200),
                        child: switch (size) {
                          _SheetSize.collapsed => SizedBox(
                            height: swTouch,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    summary,
                                    style: SwText.bodyStrong,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(
                                  Icons.expand_less_rounded,
                                  color: SwColors.brand,
                                ),
                              ],
                            ),
                          ),
                          _SheetSize.normal => const SizedBox(
                            height: 8,
                            width: double.infinity,
                          ),
                          _SheetSize.full => const SizedBox(
                            height: 28,
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Icon(
                                Icons.expand_more_rounded,
                                color: SwColors.brand,
                              ),
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
                      child: toast == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              key: ValueKey(toast),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _Toast(toast!),
                            ),
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
                              child: toast == null
                                  ? const SizedBox(width: double.infinity)
                                  : Padding(
                                      key: ValueKey(toast),
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _Toast(toast!),
                                    ),
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
  const _Segmented({
    required this.firstLabel,
    required this.firstIcon,
    required this.homeSelected,
    required this.onHome,
    required this.onPoint,
  });
  final String firstLabel;
  final IconData firstIcon;
  final bool homeSelected;
  final VoidCallback onHome, onPoint;
  @override
  Widget build(BuildContext context) {
    Widget item(String label, IconData icon, bool on, VoidCallback tap) =>
        Expanded(
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
                    Icon(
                      icon,
                      size: 20,
                      color: on ? SwColors.brand : SwColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: SwMotion.of(context, 200),
                        style: SwText.bodyStrong.copyWith(
                          color: on
                              ? SwColors.brandText
                              : SwColors.textSecondary,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
      decoration: BoxDecoration(
        color: SwColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: SwMotion.of(context, 240),
              curve: SwMotion.curve,
              alignment: homeSelected
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
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
          Row(
            children: [
              item(firstLabel, firstIcon, homeSelected, onHome),
              item(
                '最近求助地點',
                Icons.local_police_outlined,
                !homeSelected,
                onPoint,
              ),
            ],
          ),
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
    builder: (_, s, child) => Transform.scale(
      scale: s,
      alignment: Alignment.centerLeft,
      child: child,
    ),
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
            child: Text(
              '示範：已繞開 $count 個示範回報',
              style: SwText.bodyStrong.copyWith(color: SwColors.brandText),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StepsToggle extends StatelessWidget {
  const _StepsToggle({
    required this.open,
    required this.count,
    required this.onTap,
  });
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
            child: Text(
              '文字路線',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: SwText.bodyStrong,
            ),
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
  const _StepsList({
    required this.steps,
    required this.arrive,
    required this.home,
    this.instructions,
  });
  final List<RouteStep> steps;

  /// 有路名的逐路口文字；有的話取代只有方向的 [steps]。
  final List<RouteInstruction>? instructions;
  static const _turnIcon = {
    TurnKind.start: Icons.straight_rounded,
    TurnKind.straight: Icons.straight_rounded,
    TurnKind.slightLeft: Icons.turn_slight_left_rounded,
    TurnKind.left: Icons.turn_left_rounded,
    TurnKind.sharpLeft: Icons.turn_sharp_left_rounded,
    TurnKind.slightRight: Icons.turn_slight_right_rounded,
    TurnKind.right: Icons.turn_right_rounded,
    TurnKind.sharpRight: Icons.turn_sharp_right_rounded,
    TurnKind.uTurn: Icons.u_turn_left_rounded,
  };
  final String arrive;
  final bool home;
  static const _icon = {
    StepTurn.start: Icons.straight_rounded,
    StepTurn.straight: Icons.straight_rounded,
    StepTurn.slightLeft: Icons.turn_slight_left_rounded,
    StepTurn.left: Icons.turn_left_rounded,
    StepTurn.sharpLeft: Icons.turn_sharp_left_rounded,
    StepTurn.slightRight: Icons.turn_slight_right_rounded,
    StepTurn.right: Icons.turn_right_rounded,
    StepTurn.sharpRight: Icons.turn_sharp_right_rounded,
    StepTurn.uTurn: Icons.u_turn_left_rounded,
  };
  @override
  Widget build(BuildContext context) {
    Widget row(Widget icon, String text, {String? meters, bool end = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: end ? SwColors.brand : SwColors.brandSoft,
                ),
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
          if (instructions case final list?)
            for (final s in list)
              row(Icon(_turnIcon[s.turn], color: SwColors.brand), s.text)
          else
            for (final s in steps)
              row(
                Icon(_icon[s.turn], color: SwColors.brand),
                stepTurnLabel[s.turn]!,
                meters: '約 ${s.meters} 公尺',
              ),
          row(
            Icon(
              home ? Icons.home_rounded : Icons.place_rounded,
              color: SwColors.onBrand,
              size: 20,
            ),
            '抵達$arrive',
            end: true,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.done,
    required this.now,
    required this.last,
    required this.text,
  });
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
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: SwColors.onBrand,
                      )
                    : Text(
                        '$index',
                        style: SwText.caption.copyWith(
                          height: 1,
                          color: now
                              ? SwColors.warnText
                              : SwColors.textSecondary,
                        ),
                      ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? SwColors.brand : SwColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                text,
                style: now ? SwText.bodyStrong : SwText.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.point,
    required this.meters,
    required this.open,
    required this.onTap,
    required this.onGo,
  });
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
        border: Border.all(
          color: open ? SwColors.brand : SwColors.border,
          width: open ? 2 : 1,
        ),
        boxShadow: open ? SwShadow.float : SwShadow.card,
      ),
      child: Column(
        children: [
          SwPressable(
            onTap: onTap,
            radius: 12,
            selected: open,
            semanticsLabel:
                '${p.name}，${_kind[p.kind]}，約 $meters 公尺，${_open[p.availability]}',
            padding: const EdgeInsets.all(12),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: SwColors.brand,
                    ),
                    child: const Icon(
                      helpPointIcon,
                      size: 22,
                      color: SwColors.onBrand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: SwText.bodyStrong),
                        Text(
                          [
                            if (p.name != _kind[p.kind]) _kind[p.kind],
                            '$meters 公尺',
                            '${walkMinutes(meters)} 分鐘',
                          ].join('・'),
                          style: SwText.secondary,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: known ? SwColors.brandSoft : SwColors.warnBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _open[p.availability]!,
                      style: SwText.smallStrong.copyWith(
                        color: known ? SwColors.brandText : SwColors.warnText,
                      ),
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
                        SwPrimaryButton(
                          label: '帶我去這裡',
                          icon: Icons.directions_walk_rounded,
                          onTap: onGo,
                        ),
                        const Divider(color: SwColors.border, height: 24),
                        // 只列出有資料的欄位，空白欄位不顯示「尚未提供」。
                        if (p.address != null) _Fact('地址', p.address!),
                        if (p.publicPhone != null) _Fact('電話', p.publicPhone!),
                        _Fact(
                          '營業資訊',
                          p.availabilityCheckedAt == null
                              ? _openLong[p.availability]!
                              : '${_openLong[p.availability]}（確認時間：${p.availabilityCheckedAt}）',
                        ),
                        if (p.recognition is sw.ConfirmedRecognition)
                          const _Fact('合作認可', '認可資料附有證據'),
                        _Fact(
                          '資料來源',
                          '${p.source.title}・${p.source.dataMode == sw.DataMode.mock ? '示範資料' : '真實資料'}',
                        ),
                        if (p.source.dataUpdatedAt != null)
                          _Fact('資料更新', p.source.dataUpdatedAt!),
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

/// 選了較長的避讓路線時，提示比最短路線多走幾分鐘；數值改變時淡入。
class _ExtraMinutes extends StatelessWidget {
  const _ExtraMinutes({required this.extra});
  final int extra;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: SwMotion.of(context, 300),
    child: extra <= 0
        ? const SizedBox(key: ValueKey(0), width: double.infinity)
        : Semantics(
            key: ValueKey(extra),
            liveRegion: true,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: SwColors.brandSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '比最短路線多 $extra 分鐘',
                style: SwText.smallStrong.copyWith(color: SwColors.brandText),
              ),
            ),
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
          const Icon(
            Icons.check_circle_rounded,
            color: SwColors.brand,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: SwText.bodyStrong)),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.pointsView,
    required this.showShortcut,
    this.live = false,
    this.crime = false,
  });
  final bool pointsView, showShortcut, live, crime;
  @override
  Widget build(BuildContext context) {
    Widget group(String title) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        title,
        style: SwText.small.copyWith(color: SwColors.textSecondary),
      ),
    );
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
      decoration: BoxDecoration(
        color: SwColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: SwShadow.float,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('圖例', style: SwText.bodyStrong),
          // 依類別分組：路線、避讓範圍、地點。
          if (!pointsView) ...[
            group('路線'),
            item(
              Container(
                width: 18,
                height: 5,
                decoration: BoxDecoration(
                  color: SwColors.brand,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              '建議路線',
            ),
            if (live)
              item(
                Container(
                  width: 18,
                  height: 4,
                  decoration: BoxDecoration(
                    color: TPColors.grayscale400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                '其他可選路線',
              ),
            if (showShortcut)
              item(
                Text(
                  '···',
                  style: SwText.bodyStrong.copyWith(
                    color: TPColors.grayscale500,
                  ),
                ),
                '較短但經過異常',
              ),
          ],
          group('避讓範圍'),
          item(
            const Icon(
              Icons.warning_rounded,
              size: 18,
              color: SwColors.warnMark,
            ),
            live ? '異常回報（50 公尺避讓）' : '異常回報',
          ),
          if (crime)
            item(
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: crimeMarkColor.withValues(alpha: .14),
                  border: Border.all(color: crimeMarkColor),
                ),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: crimeMarkColor,
                  ),
                ),
              ),
              '犯罪參考位置（50 公尺避讓緩衝區）',
            ),
          group('地點'),
          item(
            const Icon(Icons.home_rounded, size: 18, color: SwColors.brand),
            '家',
          ),
          item(const HelpPointMark(size: 20), '求助地點（超商、派出所）'),
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
    secondary: SwSecondaryAction(
      icon: Icons.phone_in_talk_outlined,
      label: '模擬來電',
      onTap: onCall,
    ),
    onEmergency: onEmergency,
  );
}

/// 換下一個求助地點：圖示鈕（交換箭頭），旁邊就是地點名稱，語意清楚；讀屏與長按提示「換下一個求助地點」。
class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: onTap == null ? null : SwShadow.card,
    ),
    child: SwPressable(
      onTap: onTap,
      color: onTap == null ? TPColors.grayscale100 : SwColors.brandSoft,
      pressedColor: TPColors.primary100,
      border: BorderSide(
        color: onTap == null ? SwColors.border : SwColors.brand,
      ),
      radius: swTouch / 2,
      semanticsLabel: '換下一個求助地點',
      child: SizedBox(
        width: swTouch,
        height: swTouch,
        child: Icon(
          Icons.swap_horiz_rounded,
          color: onTap == null ? SwColors.textSecondary : SwColors.brand,
        ),
      ),
    ),
  );
}

/// 地圖右上工具（像地圖 App 的圖層鈕）：圖示＋兩字說明，56×56，選取時換底色。
class _MapTool extends StatelessWidget {
  const _MapTool({
    required this.icon,
    required this.caption,
    required this.semantics,
    required this.onTap,
    this.selected = false,
    this.warn = false,
  });
  final IconData icon;
  final String caption, semantics;
  final VoidCallback onTap;
  final bool selected, warn;
  @override
  Widget build(BuildContext context) {
    final fg = warn ? SwColors.warnText : SwColors.brandText;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: SwShadow.float,
      ),
      child: SwPressable(
        onTap: onTap,
        selected: selected,
        color: selected
            ? (warn ? SwColors.warnBg : SwColors.brandSoft)
            : SwColors.surface,
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
                Text(
                  caption,
                  maxLines: 1,
                  style: SwText.caption.copyWith(color: fg, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一條可選的路線：分鐘、距離、會經過幾個回報點。整列可點，≥ 56 高。
class _RouteOption extends StatelessWidget {
  const _RouteOption({
    required this.label,
    required this.minutes,
    required this.meters,
    required this.passes,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int? minutes;
  final int meters, passes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SwPressable(
      onTap: onTap,
      radius: 12,
      semanticsLabel:
          '$label，${minutes == null ? '時間未知' : '$minutes 分鐘'}，$meters 公尺，${passes == 0 ? '不經過避讓緩衝區' : '經過 $passes 個避讓緩衝區'}${selected ? '，已選擇' : ''}',
      child: AnimatedContainer(
        duration: SwMotion.of(context, 180),
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SwColors.brandSoft : SwColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? SwColors.brand : SwColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? SwColors.brand : SwColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: SwText.bodyStrong),
                  Text(
                    passes == 0 ? '不經過避讓緩衝區' : '經過 $passes 個避讓緩衝區',
                    style: SwText.small.copyWith(
                      color: passes == 0
                          ? SwColors.brandText
                          : SwColors.warnText,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${minutes == null ? '時間未知' : '$minutes 分'}・$meters 公尺',
              style: SwText.secondary,
            ),
          ],
        ),
      ),
    ),
  );
}

/// 起點選項（目前位置／在地圖上選）。整列可點，56 高。
class _StartChoice extends StatelessWidget {
  const _StartChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SwPressable(
      onTap: onTap,
      selected: selected,
      color: selected ? SwColors.brandSoft : SwColors.bg,
      border: BorderSide(color: selected ? SwColors.brand : SwColors.border),
      radius: 10,
      semanticsLabel: '$label${selected ? '，目前選擇' : ''}',
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Icon(icon, color: SwColors.brand),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: SwText.bodyStrong)),
            if (selected)
              const Icon(Icons.check_rounded, color: SwColors.brand),
          ],
        ),
      ),
    ),
  );
}
