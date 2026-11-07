import 'dart:async';
import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_call_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_emergency_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_setting_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

enum _Screen { home, map, points, report, call, emergency, homeSetting }

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
    this.route,
    this.routeLoading = false,
    this.onPlanRoute,
    this.onReportsChanged,
    this.onStartChanged,
    this.crimeSpots = const [],
    this.crimeQueryStatus,
    this.onManageCrimeConsent,
    this.onManageRoutingConsent,
    this.routingConsent = false,
    this.crimeConsent = false,
    this.livePosition,
    this.onLeaveMap,
    this.speaker = const UnavailableSpeaker(),
    this.onLocate,
    this.onEmergency,
    this.onSendSms,
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

  /// 前往目前目的地的路線（M2 RouteService → M1 提供）。未配置時只有 Mock 使用示範路線；Live 顯示 unavailable。
  final sw.RouteResult? route;
  final bool routeLoading;

  /// M1：使用者打開地圖、換目的地、按「再試一次」時呼叫（不會在一進安心行時自動呼叫），請依此目的地呼叫 RouteService.planRoute，
  /// 再把結果傳回 [route]。
  final ValueChanged<sw.Coordinates>? onPlanRoute;

  /// 每次規劃路線前，送出目前尚未解除的回報點（真實路線會避開以它們為中心的圓）。
  final ValueChanged<List<ReportSpot>>? onReportsChanged;

  /// 犯罪參考位置與產品設定的 50 公尺避讓緩衝（非案發範圍）。
  final List<CrimeSpot> crimeSpots;
  final String? crimeQueryStatus;
  final VoidCallback? onManageCrimeConsent, onManageRoutingConsent;
  final bool routingConsent, crimeConsent;

  /// 使用者指定起點（null＝改回 GPS）；之後的路線規劃從這裡出發。
  final ValueChanged<sw.Coordinates?>? onStartChanged;

  /// 導航中持續更新的目前位置（只在地圖開著時由 M1 提供）。
  final sw.Position? livePosition;

  /// 離開地圖時呼叫，讓 M1 停止持續定位與路線請求。
  final VoidCallback? onLeaveMap;
  final SafeWalkSpeaker speaker;

  /// M1：使用者按「取得目前位置」時呼叫 PlatformService.getCurrentPosition(userInitiated: true)。
  final Future<sw.LocationResult> Function()? onLocate;

  /// M1：使用者選 110／119 時呼叫 PlatformService.requestEmergency(userInitiated: true)。
  final Future<sw.EmergencyActionResult> Function(sw.EmergencyChannel channel)? onEmergency;

  /// M1：使用者確認簡訊內容後，交給手機開啟簡訊 App；null 時只模擬傳送畫面。
  final Future<bool> Function(String body)? onSendSms;
  final VoidCallback? onExit;

  /// M1：使用者已儲存在裝置上的「家」。null＝尚未設定；只有 Mock 可沿用示範的家。
  final sw.Coordinates? homeLocation;

  /// M1：使用者在「設定家」按儲存（帶座標）或移除（null）時呼叫，由 M1 寫入裝置儲存。
  /// null 時不顯示「設定家」入口。
  final Future<void> Function(sw.Coordinates? home)? onHomeChanged;

  @override
  State<SafeWalkFlow> createState() => _SafeWalkFlowState();
}

class _SafeWalkFlowState extends State<SafeWalkFlow> with WidgetsBindingObserver {
  _Screen _screen = _Screen.home;
  _Screen _back = _Screen.home;
  bool _forward = true;
  sw.Position? _position;
  LatLng? _manualStart;
  int _editGeneration = 0;
  bool _mapTileConsent = false;

  void _setStart(LatLng? at) {
    ++_editGeneration;
    setState(() => _manualStart = at);
    widget.onStartChanged?.call(at == null ? null : sw.Coordinates(lat: at.lat, lng: at.lng));
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      ++_editGeneration;
      if (mounted) setState(() => _mapTileConsent = false);
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
      _anomalies = widget.mode == sw.DataMode.mock ? demoAnomalies() : <Anomaly>[];
      _demoPoints = widget.mode == sw.DataMode.mock ? demoAssistancePoints() : const <sw.AssistancePoint>[];
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
      (screen == _Screen.points &&
          !(widget.mode == sw.DataMode.live && widget.pointsError != null)) ||
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
      savedDestination: id == 'home' ? sw.Coordinates(lat: at.lat, lng: at.lng) : null,
    );
  }

  SavedPlace get _place => _places.firstWhere((p) => p.id == _placeId, orElse: () => _places.first);
  // Live mode never shows invented danger points or stand-in assistance points.
  late List<Anomaly> _anomalies = widget.mode == sw.DataMode.mock ? demoAnomalies() : <Anomaly>[];
  late List<sw.AssistancePoint> _demoPoints = widget.mode == sw.DataMode.mock ? demoAssistancePoints() : const <sw.AssistancePoint>[];

  String? get _nearestPointName {
    final pts = _pointsState.points;
    if (pts.isEmpty) return null;
    final position = widget.livePosition ?? _position;
    if (position == null && widget.mode == sw.DataMode.live) return null;
    final from = position == null ? DemoGeo.start : LatLng(position.coordinates.lat, position.coordinates.lng);
    final sorted = [...pts]..sort((a, b) => metersBetween(from, LatLng(a.coordinates.lat, a.coordinates.lng)).compareTo(metersBetween(from, LatLng(b.coordinates.lat, b.coordinates.lng))));
    return sorted.first.name;
  }

  bool get _missingLiveHome => widget.mode == sw.DataMode.live && _place.isHome && widget.homeLocation == null;

  RouteState get _routeState {
    if (_missingLiveHome) {
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
    return RouteState(result: widget.route, loading: widget.routeLoading, allowDemoFallback: widget.mode == sw.DataMode.mock, onRetry: widget.onPlanRoute == null ? null : _planRoute);
  }

  void _planRoute({sw.Coordinates? savedDestination}) {
    if (_missingLiveHome && savedDestination == null) return;
    final placeAt = _place.at;
    if (savedDestination == null && placeAt == null) return;
    widget.onReportsChanged?.call([
      for (final a in _anomalies)
        if (a.status != AnomalyStatus.cleared) (id: a.id, center: sw.Coordinates(lat: a.at.lat, lng: a.at.lng)),
    ]);
    widget.onPlanRoute?.call(
      savedDestination ?? sw.Coordinates(lat: placeAt!.lat, lng: placeAt.lng),
    );
  }

  void _selectPlace(String id) {
    if (id == _placeId) return;
    ++_editGeneration;
    setState(() => _placeId = id);
    _planRoute();
  }

  PointsState get _pointsState => PointsState(
    points: widget.points ?? (widget.pointsLoading || widget.pointsError != null ? const [] : _demoPoints),
    loading: widget.pointsLoading,
    error: widget.pointsError,
    onRetry: widget.onRetryPoints,
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
    if (_isMapScreen(s) && !_isMapScreen(_screen)) _planRoute();
    if (!_isMapScreen(s) && _isMapScreen(_screen)) {
      ++_editGeneration;
      _mapTileConsent = false;
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

  void _openEmergency() {
    ++_editGeneration;
    _mapTileConsent = false;
    widget.onLeaveReport?.call();
    if (_isMapScreen(_screen)) widget.onLeaveMap?.call();
    _call = null;
    _callKey.currentState?.leave();
    widget.speaker.stop();
    setState(() {
      _forward = true;
      _back = _screen == _Screen.call || _screen == _Screen.emergency ? _Screen.home : _screen;
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
        sw.LocationSuccess() => widget.mode == sw.DataMode.mock ? '已取得示範位置；不是真實定位，未傳送給任何人。' : '已取得位置；尚未傳送給任何人。',
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

  /// Same agree/decline dialog as the route and crime query settings.
  Future<void> _askMapTileConsent() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('地圖載入設定'),
        content: const Text('載入地圖會向 OpenStreetMap（tile.openstreetmap.org）請求目前檢視範圍的圖磚，對方會看到檢視範圍與 IP。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('不載入')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('同意載入')),
        ],
      ),
    );
    if (agreed != null && mounted) setState(() => _mapTileConsent = agreed);
  }

  @override
  Widget build(BuildContext context) {
    Widget map({MapStartView start = MapStartView.route}) => SafeWalkMapView(
      key: ValueKey(start),
      position: widget.livePosition ?? _position,
      showMapTiles:
          widget.showMapTiles &&
          (widget.mode == sw.DataMode.mock || _mapTileConsent),
      onMapTileConsent: widget.showMapTiles && widget.mode == sw.DataMode.live
          ? () => unawaited(_askMapTileConsent())
          : null,
      pointsState: _pointsState,
      routeState: _routeState,
      manualStart: _manualStart,
      crimeSpots: widget.crimeSpots,
      crimeQueryStatus: widget.crimeQueryStatus,
      onManageCrimeConsent: widget.onManageCrimeConsent,
      onManageRoutingConsent: widget.onManageRoutingConsent,
      routingConsent: widget.routingConsent,
      crimeConsent: widget.crimeConsent,
      destinationConfigured: !_missingLiveHome,
      onStartChanged: widget.onStartChanged == null ? null : _setStart,
      anomalies: _anomalies,
      startView: start,
      onAnomaliesChanged: () {
        setState(() {});
        // 新增或解除回報後立刻重新規劃，路線馬上改道。
        _planRoute();
      },
      places: _places,
      placeId: _placeId,
      onSelectPlace: _selectPlace,
      onAddPlace: (name, at) {
        final p = SavedPlace('place-${DateTime.now().microsecondsSinceEpoch}', name, at);
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
        destination: _place.label,
        homeSet: widget.homeLocation != null,
        onEditHome: widget.onHomeChanged == null ? null : () => _go(_Screen.homeSetting),
        avoided: avoidedCount(_anomalies),
        onBack: widget.onExit,
        onEmergency: _openEmergency,
        onOpen: (e) => _go(switch (e) {
          SafeWalkEntry.map => _Screen.map,
          SafeWalkEntry.call => _Screen.call,
          SafeWalkEntry.points => _Screen.points,
          SafeWalkEntry.report => _Screen.report,
        }),
      ),
      _Screen.homeSetting => SafeWalkHomeSettingView(
        initial: widget.homeLocation == null ? null : LatLng(widget.homeLocation!.lat, widget.homeLocation!.lng),
        onSave: (at) => widget.onHomeChanged!(sw.Coordinates(lat: at.lat, lng: at.lng)),
        onClear: widget.homeLocation == null ? null : () => widget.onHomeChanged!(null),
        onBack: () => _go(_Screen.home),
      ),
      _Screen.map => map(),
      _Screen.points =>
        widget.mode == sw.DataMode.live && widget.pointsError != null
            ? Scaffold(
                appBar: AppBar(
                  title: const Text('附近求助地點'),
                  leading: BackButton(onPressed: () => _go(_Screen.home)),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(widget.pointsError!),
                ),
              )
            : map(start: MapStartView.points),
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
        nearbyPointName: _nearestPointName,
        onChannel: _channel,
        onLocate: _locate,
        onClose: () => _go(_back),
      ),
    };
    return PopScope(
      canPop: _screen == _Screen.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _go(_screen == _Screen.emergency || _screen == _Screen.call ? _back : _Screen.home);
        }
      },
      // 換頁：往深一層由右滑入，返回由左滑入；緊急求助由下方升起，強調「這是另一種狀態」。
      child: AnimatedSwitcher(
        duration: SwMotion.of(context, 280),
        switchInCurve: SwMotion.curve,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (c, a) {
          final begin = _screen == _Screen.emergency ? const Offset(0, .12) : Offset(_forward ? .12 : -.12, 0);
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
  }
}
