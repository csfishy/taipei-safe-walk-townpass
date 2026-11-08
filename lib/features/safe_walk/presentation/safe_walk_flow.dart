import 'dart:async';

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_call_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_emergency_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_setting_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_broadcast.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_helper.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_settings_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

enum _Screen {
  home,
  settings,
  map,
  points,
  report,
  call,
  emergency,
  homeSetting,
}

/// 安心行入口（M3）。所有對外動作經由 callback 交給 M1 接線；M3 不取 GPS、不撥號、不 import 其他模組。
/// 一個要避開的回報點（中心）；半徑由路線規劃決定（系統內回報為 [reportAvoidRadiusMeters]）。
typedef ReportSpot = ({String id, sw.Coordinates center});

class SafeWalkFlow extends StatefulWidget {
  const SafeWalkFlow({
    super.key,
    this.mode = sw.DataMode.mock,
    this.allowRealCalls = false,
    this.points,
    this.pointsLoading = false,
    this.pointsError,
    this.onRetryPoints,
    this.pointRoutes = const {},
    this.onSelectPoint,
    this.route,
    this.routeLoading = false,
    this.onPlanRoute,
    this.onReportsChanged,
    this.onSaveReport,
    this.onLoadReports,
    this.onStartChanged,
    this.crimeSpots = const [],
    this.crimeQueryStatus,
    this.onManageCrimeConsent,
    this.onManageRoutingConsent,
    this.routingConsent = false,
    this.crimeConsent = false,
    this.livePosition,
    this.liveHeading,
    this.onLeaveMap,
    this.onStartNavigation,
    this.onEndNavigation,
    this.speaker = const UnavailableSpeaker(),
    this.onLocate,
    this.onEmergency,
    this.onSendSms,
    this.nearbyBroadcast,
    this.onOfficialReport,
    this.nearbyHelper,
    this.homeLocation,
    this.onHomeChanged,
    this.onExit,
    this.reportBuilder,
    this.onLeaveReport,
    this.showMapTiles = true,
  });
  final sw.DataMode mode;
  final bool allowRealCalls;
  final bool showMapTiles;

  /// Reference status only: this entry does not start navigation or read GPS.
  final Widget Function(BuildContext context, VoidCallback onBack)?
  reportBuilder;
  final VoidCallback? onLeaveReport;

  /// 求助地點（M4 → M1 提供）。未配置時只有 Mock 使用 M3 示範資料。
  final List<sw.AssistancePoint>? points;
  final bool pointsLoading;
  final String? pointsError;
  final VoidCallback? onRetryPoints;

  /// Live: walking routes to each point (id → result), same avoiding routes as
  /// a destination; points are already ranked safest, then fastest.
  final Map<String, sw.RouteResult> pointRoutes;

  /// M1: the walker chose this point as the target; navigate there with the
  /// route already planned for it.
  final ValueChanged<String>? onSelectPoint;

  /// 前往目前目的地的路線（M2 RouteService → M1 提供）。未配置時只有 Mock 使用示範路線；Live 顯示 unavailable。
  final sw.RouteResult? route;
  final bool routeLoading;

  /// M1：使用者打開地圖、換目的地、按「再試一次」時呼叫（不會在一進安心行時自動呼叫），請依此目的地呼叫 RouteService.planRoute，
  /// 再把結果傳回 [route]。
  final ValueChanged<sw.Coordinates>? onPlanRoute;

  /// 每次規劃路線前，送出目前尚未解除的回報點（真實路線會避開以它們為中心的圓）。
  final ValueChanged<List<ReportSpot>>? onReportsChanged;

  /// Live reports are shown only after the database confirms the write.
  final Future<Anomaly> Function(Anomaly draft)? onSaveReport;
  final Future<List<Anomaly>> Function()? onLoadReports;

  /// 犯罪參考位置與產品設定的 50 公尺避讓緩衝（非案發範圍）。
  final List<CrimeSpot> crimeSpots;
  final String? crimeQueryStatus;
  final VoidCallback? onManageCrimeConsent, onManageRoutingConsent;
  final bool routingConsent, crimeConsent;

  /// 使用者指定起點（null＝改回 GPS）；之後的路線規劃從這裡出發。
  final ValueChanged<sw.Coordinates?>? onStartChanged;

  /// 導航中持續更新的目前位置（只在地圖開著時由 M1 提供）。
  final sw.Position? livePosition;

  /// 手機朝向（從北方順時針的度數），地圖上的位置點畫成箭頭；null＝只畫圓點。
  final double? liveHeading;

  /// 離開地圖時呼叫，讓 M1 停止持續定位與路線請求。
  final VoidCallback? onLeaveMap;
  final VoidCallback? onStartNavigation, onEndNavigation;
  final SafeWalkSpeaker speaker;

  /// M1：使用者按「取得目前位置」時呼叫 PlatformService.getCurrentPosition(userInitiated: true)。
  final Future<sw.LocationResult> Function()? onLocate;

  /// M1：使用者選 110／119 時呼叫 PlatformService.requestEmergency(userInitiated: true)。
  final Future<sw.EmergencyActionResult> Function(sw.EmergencyChannel channel)?
  onEmergency;

  /// M1：使用者確認簡訊內容後，交給手機開啟簡訊 App；null 時只模擬傳送畫面。
  final Future<bool> Function(String body)? onSendSms;

  /// M1：緊急求助頁的「通知附近的人」；null 時不顯示。
  final SafeWalkNearbyBroadcast? nearbyBroadcast;

  /// M1：附近協助者（加入／退出、收到求助的橫幅）；null 時不顯示。
  final SafeWalkNearbyHelper? nearbyHelper;

  /// M1：開啟官方線上報案；null 時求助頁不顯示該按鈕。
  final VoidCallback? onOfficialReport;
  final VoidCallback? onExit;

  /// M1：使用者已儲存在裝置上的「家」。null＝尚未設定；只有 Mock 可沿用示範的家。
  final sw.Coordinates? homeLocation;

  /// M1：使用者在「設定家」按儲存（帶座標）或移除（null）時呼叫，由 M1 寫入裝置儲存。
  /// null 時不顯示「設定家」入口。
  final Future<void> Function(sw.Coordinates? home)? onHomeChanged;

  @override
  State<SafeWalkFlow> createState() => _SafeWalkFlowState();
}

class _SafeWalkFlowState extends State<SafeWalkFlow>
    with WidgetsBindingObserver {
  _Screen _screen = _Screen.home;
  _Screen _back = _Screen.home;
  bool _forward = true;
  sw.Position? _position;
  LatLng? _manualStart;
  int _editGeneration = 0;
  int _reportsGeneration = 0;
  bool _reportsLoading = false;
  String? _reportsError;
  final Map<String, Anomaly> _confirmedReports = {};
  String? _lastPlannedReports;
  bool _appActive = true;

  /// 目前導航的目標：null＝目的地（家／常用地點）；否則是求助地點 id。
  String? _targetPointId;

  void _setTarget(sw.AssistancePoint? point) {
    if (point == null && _targetPointId == null) return;
    if (point?.id != _targetPointId) {
      setState(() => _targetPointId = point?.id);
    }
    if (point == null) {
      _planRoute();
    } else {
      widget.onSelectPoint?.call(point.id);
    }
  }

  void _setStart(LatLng? at) {
    ++_editGeneration;
    setState(() => _manualStart = at);
    widget.onStartChanged?.call(
      at == null ? null : sw.Coordinates(lat: at.lat, lng: at.lng),
    );
    _planRoute();
  }

  String? _emergencyMessage;
  bool _emergencyError = false, _locating = false;
  final _callKey = GlobalKey<SafeWalkCallViewState>();

  /// 進行中的模擬來電；去地圖看路再回來會接續。結束通話、拒絕、緊急求助、回首頁時丟棄。
  SafeWalkCallSession? _call;
  late final List<SavedPlace> _places = widget.mode == sw.DataMode.mock
      ? [...demoPlaces()]
      : [const SavedPlace('home', '家', null)];
  String _placeId = 'home';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyHome();
  }

  @override
  void dispose() {
    ++_editGeneration;
    ++_reportsGeneration;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _appActive = true;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ++_editGeneration;
      _appActive = false;
      ++_reportsGeneration;
      if (_reportsLoading) {
        setState(() {
          _reportsLoading = false;
          _reportsError = '回報資料載入已中斷，請重新載入；目前清單可能不完整。';
        });
      }
    }
  }

  @override
  void didUpdateWidget(SafeWalkFlow old) {
    super.didUpdateWidget(old);
    if (old.homeLocation != widget.homeLocation || old.mode != widget.mode) {
      _applyHome();
    }
    if (old.mode != widget.mode) {
      ++_editGeneration;
      ++_reportsGeneration;
      _reportsLoading = false;
      _reportsError = null;
      _confirmedReports.clear();
      _anomalies = widget.mode == sw.DataMode.mock
          ? demoAnomalies()
          : <Anomaly>[];
      _demoPoints = widget.mode == sw.DataMode.mock
          ? demoAssistancePoints()
          : const <sw.AssistancePoint>[];
    }
  }

  /// Live 的家只使用已儲存座標；未設定時沒有可供導航或顯示的目的地。
  void _applyHome() {
    if (widget.mode == sw.DataMode.live) {
      _places.removeWhere((p) => p.id == 'work');
    }
    final i = _places.indexWhere((p) => p.isHome);
    final h = widget.homeLocation;
    final next = h != null
        ? SavedPlace('home', '家', LatLng(h.lat, h.lng))
        : widget.mode == sw.DataMode.mock
        ? demoPlaces().first
        : const SavedPlace('home', '家', null);
    if (i >= 0) {
      _places[i] = next;
    }
  }

  bool _isMapScreen(_Screen screen) =>
      screen == _Screen.map ||
      screen == _Screen.points ||
      (screen == _Screen.report && widget.reportBuilder == null);

  Future<void> _editPlace(String id, String name, LatLng at) async {
    final generation = ++_editGeneration;
    if (id == 'home') {
      final save = widget.onHomeChanged;
      if (save == null && widget.mode == sw.DataMode.live) {
        throw StateError('Home storage unavailable');
      }
      if (save != null) await save(sw.Coordinates(lat: at.lat, lng: at.lng));
    }
    if (!mounted || generation != _editGeneration || !_isMapScreen(_screen)) {
      return;
    }
    final i = _places.indexWhere((p) => p.id == id);
    if (i < 0) return;
    setState(() {
      _places[i] = SavedPlace(id, name, at);
      _placeId = id;
    });
    _planRoute(
      savedDestination: id == 'home'
          ? sw.Coordinates(lat: at.lat, lng: at.lng)
          : null,
    );
  }

  SavedPlace get _place =>
      _places.firstWhere((p) => p.id == _placeId, orElse: () => _places.first);
  // Live mode never shows invented danger points or stand-in assistance points.
  late List<Anomaly> _anomalies = widget.mode == sw.DataMode.mock
      ? demoAnomalies()
      : <Anomaly>[];
  late List<sw.AssistancePoint> _demoPoints = widget.mode == sw.DataMode.mock
      ? demoAssistancePoints()
      : const <sw.AssistancePoint>[];

  Future<void> _loadReports() async {
    if (widget.mode != sw.DataMode.live) return;
    final load = widget.onLoadReports;
    if (load == null) {
      setState(() => _reportsError = '回報資料庫尚未配置，無法載入已儲存的回報。');
      return;
    }
    final generation = ++_reportsGeneration;
    setState(() {
      _reportsLoading = true;
      _reportsError = null;
    });
    try {
      final reports = await load();
      if (!mounted || generation != _reportsGeneration) return;
      setState(() {
        _anomalies = {
          for (final report in reports) report.id: report,
          ..._confirmedReports,
        }.values.toList();
        _reportsLoading = false;
      });
      _planRoute();
    } catch (_) {
      if (!mounted || generation != _reportsGeneration) return;
      setState(() {
        _reportsLoading = false;
        _reportsError = '回報資料載入失敗，請再試一次；目前清單可能不完整。';
      });
    }
  }

  Future<Anomaly> _saveReport(Anomaly draft) async {
    final save = widget.onSaveReport;
    if (save == null) throw StateError('Report storage unavailable');
    final mode = widget.mode;
    final report = await save(draft);
    // Overlay confirmed writes on query results without cancelling the query:
    // it may still contain other persisted reports needed for avoidance.
    if (mounted && widget.mode == mode) {
      setState(() {
        _confirmedReports[report.id] = report;
        _anomalies.removeWhere((item) => item.id == report.id);
        _anomalies.add(report);
      });
      if (_isMapScreen(_screen) && _appActive) {
        _planRoute();
      } else {
        widget.onReportsChanged?.call(_reportSpots);
      }
    }
    return report;
  }

  String? get _nearestPointName {
    final pts = _pointsState.points;
    if (pts.isEmpty) return null;
    final position = widget.livePosition ?? _position;
    if (position == null && widget.mode == sw.DataMode.live) return null;
    final from = position == null
        ? DemoGeo.start
        : LatLng(position.coordinates.lat, position.coordinates.lng);
    final sorted = [...pts]
      ..sort(
        (a, b) =>
            metersBetween(
              from,
              LatLng(a.coordinates.lat, a.coordinates.lng),
            ).compareTo(
              metersBetween(from, LatLng(b.coordinates.lat, b.coordinates.lng)),
            ),
      );
    return sorted.first.name;
  }

  bool get _missingLiveHome =>
      widget.mode == sw.DataMode.live &&
      _place.isHome &&
      widget.homeLocation == null;

  RouteState get _routeState {
    if (_missingLiveHome && _targetPointId == null) {
      return RouteState(
        result: sw.RouteFailure(
          requestId: 'home-not-set',
          mode: widget.mode,
          generatedAt: DateTime.now().toUtc().toIso8601String(),
          status: sw.RouteFailureStatus.invalidInput,
          reason: '請先返回首頁設定「家」的位置，再規劃回家路線。',
          warnings: const ['尚未設定家的位置；未送出路線查詢。'],
        ),
        allowDemoFallback: false,
      );
    }
    return RouteState(
      result: widget.route,
      loading: widget.routeLoading,
      allowDemoFallback: widget.mode == sw.DataMode.mock,
      onRetry: widget.onPlanRoute == null ? null : _planRoute,
    );
  }

  List<ReportSpot> get _reportSpots => [
    for (final a in _anomalies)
      if (a.status != AnomalyStatus.cleared)
        (id: a.id, center: sw.Coordinates(lat: a.at.lat, lng: a.at.lng)),
  ];

  String get _reportSignature => _anomalies
      .map((a) => '${a.id}:${a.status.name}:${a.reportCount}')
      .join('|');

  void _planRoute({sw.Coordinates? savedDestination}) {
    _lastPlannedReports = _reportSignature;
    widget.onReportsChanged?.call(_reportSpots);
    if (savedDestination != null) _targetPointId = null;
    // 目標是求助地點時，重新規劃（例如回報變了）也是往那個地點。
    final target = _targetPointId == null
        ? null
        : _pointsState.points.where((p) => p.id == _targetPointId).firstOrNull;
    if (target != null) {
      widget.onPlanRoute?.call(target.coordinates);
      return;
    }
    if (_missingLiveHome && savedDestination == null) return;
    final placeAt = _place.at;
    if (savedDestination == null && placeAt == null) return;
    widget.onPlanRoute?.call(
      savedDestination ?? sw.Coordinates(lat: placeAt!.lat, lng: placeAt.lng),
    );
  }

  void _selectPlace(String id) {
    if (id == _placeId && _targetPointId == null) return;
    ++_editGeneration;
    setState(() {
      _placeId = id;
      _targetPointId = null;
    });
    _planRoute();
  }

  PointsState get _pointsState => PointsState(
    points:
        widget.points ??
        (widget.pointsLoading || widget.pointsError != null
            ? const []
            : _demoPoints),
    loading: widget.pointsLoading,
    error: widget.pointsError,
    onRetry: widget.onRetryPoints,
    routes: widget.pointRoutes,
  );

  void _go(_Screen s) {
    if (_screen == _Screen.emergency && s != _Screen.emergency) {
      widget.onLeaveMap?.call();
      _position = null;
    }
    if (_screen == _Screen.report && s != _Screen.report) {
      widget.onLeaveReport?.call();
    }
    if (_screen == _Screen.call && s != _Screen.call) {
      _callKey.currentState?.leave();
    }
    // 使用者明確打開地圖（點「安心行」主卡）時才請 M1 規劃路線；一進安心行不自動送出。
    if (_isMapScreen(s) && !_isMapScreen(_screen)) {
      _afterMapOpened(s);
    }
    if (!_isMapScreen(s) && _isMapScreen(_screen)) {
      ++_editGeneration;
      ++_reportsGeneration;
      _reportsLoading = false;
      _targetPointId = null;
      widget.onLeaveMap?.call();
    }
    if (s == _Screen.home) _call = null;
    setState(() {
      _forward = s != _Screen.home && s != _back;
      if (s == _Screen.call || s == _Screen.emergency) {
        _back = _screen == _Screen.call ? _back : _screen;
      }
      _screen = s;
    });
  }

  /// 打開地圖後的第一個查詢；路線與犯罪資料的同意會依序在這裡問。
  void _afterMapOpened(_Screen s) {
    if (widget.mode == sw.DataMode.live && widget.onLoadReports != null) {
      unawaited(_loadReportsThenPlan(s));
      return;
    }
    unawaited(_loadReports());
    _planOpenedMap(s);
  }

  Future<void> _loadReportsThenPlan(_Screen s) async {
    await _loadReports();
    if (!mounted || _screen != s) return;
    // _loadReports also replans on success; retry failures still allow the user
    // to navigate with an explicit incomplete-report disclosure.
    if (_reportsError != null || s == _Screen.points) _planOpenedMap(s);
  }

  void _planOpenedMap(_Screen s) {
    if (s == _Screen.points && widget.mode == sw.DataMode.live) {
      widget.onRetryPoints?.call();
    } else {
      _planRoute();
    }
  }

  void _openEmergency() {
    ++_editGeneration;
    ++_reportsGeneration;
    _reportsLoading = false;
    widget.onLeaveReport?.call();
    if (_isMapScreen(_screen)) widget.onLeaveMap?.call();
    _call = null;
    _callKey.currentState?.leave();
    widget.speaker.stop();
    setState(() {
      _forward = true;
      _back = _screen == _Screen.call || _screen == _Screen.emergency
          ? _Screen.home
          : _screen;
      _emergencyMessage = null;
      _screen = _Screen.emergency;
    });
  }

  Future<void> _locate() async {
    if (widget.onLocate == null) {
      setState(() {
        _emergencyMessage = '目前無法取得位置；請說出附近的路名或地標。';
        _emergencyError = false;
      });
      return;
    }
    setState(() => _locating = true);
    final result = await widget.onLocate!();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _position = result is sw.LocationSuccess ? result.position : null;
      _emergencyError = result is sw.LocationFailure;
      _emergencyMessage = switch (result) {
        sw.LocationSuccess() =>
          widget.mode == sw.DataMode.mock
              ? '已取得示範位置；不是真實定位，未傳送給任何人。'
              : '已取得位置；尚未傳送給任何人。',
        sw.LocationFailure(:final message) => message,
      };
    });
  }

  Future<void> _channel(sw.EmergencyChannel c) async {
    final r = await widget.onEmergency?.call(c);
    if (!mounted) return;
    setState(() {
      _emergencyError = r?.action == sw.EmergencyAction.failed;
      _emergencyMessage = r?.message ?? '目前沒有撥號設定；沒有撥號，也沒有通知任何人。';
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget map({MapStartView start = MapStartView.route}) => SafeWalkMapView(
      key: ValueKey(start),
      position: widget.livePosition ?? _position,
      heading: widget.liveHeading,
      showMapTiles: widget.showMapTiles,
      pointsState: _pointsState,
      routeState: _routeState,
      targetPointId: _targetPointId,
      onTarget: _setTarget,
      onStartNavigation: widget.onStartNavigation,
      onEndNavigation: widget.onEndNavigation,
      manualStart: _manualStart,
      crimeSpots: widget.crimeSpots,
      crimeQueryStatus: widget.crimeQueryStatus,
      onManageCrimeConsent: widget.onManageCrimeConsent,
      onManageRoutingConsent: widget.onManageRoutingConsent,
      routingConsent: widget.routingConsent,
      crimeConsent: widget.crimeConsent,
      destinationConfigured: !_missingLiveHome,
      canSetHome: widget.onHomeChanged != null,
      onStartChanged: widget.onStartChanged == null ? null : _setStart,
      anomalies: _anomalies,
      isLive: widget.mode == sw.DataMode.live,
      onSaveReport: widget.onSaveReport == null ? null : _saveReport,
      reportsLoading: _reportsLoading,
      reportsError: _reportsError,
      onRetryReports: () => unawaited(_loadReports()),
      startView: start,
      onAnomaliesChanged: () {
        setState(() {});
        // 新增或解除回報後立刻重新規劃，路線馬上改道。
        if (_lastPlannedReports != _reportSignature) {
          if (_isMapScreen(_screen) && _appActive) {
            _planRoute();
          } else {
            widget.onReportsChanged?.call(_reportSpots);
          }
        }
      },
      places: _places,
      placeId: _placeId,
      onSelectPlace: _selectPlace,
      onAddPlace: (name, at) {
        final p = SavedPlace(
          'place-${DateTime.now().microsecondsSinceEpoch}',
          name,
          at,
        );
        setState(() => _places.add(p));
        _selectPlace(p.id);
      },
      onEditPlace: _editPlace,
      onDeletePlace: (id) {
        final wasCurrent = _placeId == id;
        setState(() => _places.removeWhere((p) => p.id == id));
        if (wasCurrent) _selectPlace('home');
      },
      onBack: () => _go(_Screen.home),
      onCall: () => _go(_Screen.call),
      onEmergency: _openEmergency,
    );
    final child = switch (_screen) {
      _Screen.home => SafeWalkHomeView(
        isLive: widget.mode == sw.DataMode.live,
        settings: [
          if (widget.onManageRoutingConsent != null)
            (
              icon: Icons.alt_route_rounded,
              label: '路線查詢設定',
              status: widget.routingConsent
                  ? '已同意路線查詢；可在此撤回。系統定位權限另行設定，地圖圖磚自動載入。'
                  : '未同意路線查詢；不會傳送起點、目的地與避讓緩衝。',
              onTap: widget.onManageRoutingConsent!,
            ),
          if (widget.onManageCrimeConsent != null)
            (
              icon: Icons.policy_outlined,
              label: '犯罪資料查詢設定',
              status: [
                widget.crimeConsent ? '已同意行程範圍查詢；可在此撤回。' : '未同意行程範圍查詢。',
                if (widget.crimeQueryStatus != null) widget.crimeQueryStatus!,
              ].join('\n'),
              onTap: widget.onManageCrimeConsent!,
            ),
          // 首頁不再放「回報狀況」；正式模式的回報資料說明頁改從這裡進入。
          if (widget.reportBuilder != null)
            (
              icon: Icons.campaign_outlined,
              label: '回報資料說明',
              status: '歷史資料來源、更新日期與限制',
              onTap: () => _go(_Screen.report),
            ),
        ],
        destination: _place.label,
        avoided: avoidedCount(_anomalies),
        onBack: widget.onExit,
        onOpenSettings: () => _go(_Screen.settings),
        onEmergency: _openEmergency,
        onOpen: (e) => _go(switch (e) {
          SafeWalkEntry.map => _Screen.map,
          SafeWalkEntry.call => _Screen.call,
          SafeWalkEntry.points => _Screen.points,
          SafeWalkEntry.report => _Screen.report,
        }),
      ),
      _Screen.settings => SafeWalkSettingsView(
        onBack: () => _go(_Screen.home),
        homeSet: widget.homeLocation != null,
        onEditHome: widget.onHomeChanged == null
            ? null
            : () => _go(_Screen.homeSetting),
        nearbyHelper: widget.nearbyHelper,
      ),
      // 儲存或移除家之後回到「安心行設定」，不直接跳回首頁。
      _Screen.homeSetting => SafeWalkHomeSettingView(
        initial: widget.homeLocation == null
            ? null
            : LatLng(widget.homeLocation!.lat, widget.homeLocation!.lng),
        onSave: (at) =>
            widget.onHomeChanged!(sw.Coordinates(lat: at.lat, lng: at.lng)),
        onClear: widget.homeLocation == null
            ? null
            : () => widget.onHomeChanged!(null),
        onBack: () => _go(_Screen.settings),
      ),
      _Screen.map => map(),
      _Screen.points => map(start: MapStartView.points),
      _Screen.report =>
        widget.reportBuilder?.call(context, () => _go(_Screen.home)) ??
            map(start: MapStartView.report),
      _Screen.call => SafeWalkCallView(
        key: _callKey,
        speaker: widget.speaker,
        session: _call ??= SafeWalkCallSession(),
        onEnd: () {
          _call = null;
          _go(_back);
        },
        onEmergency: _openEmergency,
      ),
      _Screen.emergency => SafeWalkEmergencyView(
        // The official entry with real routes is Live: no simulated SMS success.
        mode: widget.onPlanRoute != null ? sw.DataMode.live : widget.mode,
        allowRealCalls: widget.allowRealCalls,
        position: widget.livePosition ?? _position,
        statusMessage: _emergencyMessage,
        statusIsError: _emergencyError,
        locating: _locating,
        onSendSms: widget.onSendSms,
        nearbyBroadcast: widget.nearbyBroadcast,
        onOfficialReport: widget.onOfficialReport,
        nearbyPointName: _nearestPointName,
        onChannel: _channel,
        onLocate: _locate,
        onClose: () => _go(_back),
      ),
    };
    final screen = PopScope(
      canPop: _screen == _Screen.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _go(
            _screen == _Screen.emergency || _screen == _Screen.call
                ? _back
                : _screen == _Screen.homeSetting
                ? _Screen.settings
                : _Screen.home,
          );
        }
      },
      // 換頁：往深一層由右滑入，返回由左滑入；緊急求助由下方升起，強調「這是另一種狀態」。
      child: AnimatedSwitcher(
        duration: SwMotion.of(context, 280),
        switchInCurve: SwMotion.curve,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (c, a) {
          final begin = _screen == _Screen.emergency
              ? const Offset(0, .12)
              : Offset(_forward ? .12 : -.12, 0);
          return FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: begin, end: Offset.zero).animate(a),
              child: c,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(_screen), child: child),
      ),
    );
    final helper = widget.nearbyHelper;
    if (helper == null) return screen;
    // Alerts from nearby people appear over whichever screen is open.
    return Stack(
      children: [
        screen,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeWalkNearbyAlertBanner(
            helper: helper,
            onOpenEmergency: _openEmergency,
          ),
        ),
      ],
    );
  }
}
