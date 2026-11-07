import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_call_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_emergency_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

enum _Screen { home, map, points, report, call, emergency }

/// 安心行入口（M3）。所有對外動作經由 callback 交給 M1 接線；M3 不取 GPS、不撥號、不 import 其他模組。
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
    this.speaker = const UnavailableSpeaker(),
    this.onLocate,
    this.onEmergency,
    this.onSendSms,
    this.onExit,
  });
  final sw.DataMode mode;
  final bool allowRealCalls;

  /// 求助地點（M4 → M1 提供）。null 且沒有載入中／錯誤時，使用 M3 示範資料。
  final List<sw.AssistancePoint>? points;
  final bool pointsLoading;
  final String? pointsError;
  final VoidCallback? onRetryPoints;

  /// 前往目前目的地的路線（M2 RouteService → M1 提供）。null 且不在計算中＝尚未配置，使用示範路線並標示。
  final sw.RouteResult? route;
  final bool routeLoading;

  /// M1：使用者打開地圖、換目的地、按「再試一次」時呼叫（不會在一進安心行時自動呼叫），請依此目的地呼叫 RouteService.planRoute，
  /// 再把結果傳回 [route]。null 時畫面一律用示範路線。
  final ValueChanged<sw.Coordinates>? onPlanRoute;
  final SafeWalkSpeaker speaker;

  /// M1：使用者按「取得目前位置」時呼叫 PlatformService.getCurrentPosition(userInitiated: true)。
  final Future<sw.LocationResult> Function()? onLocate;

  /// M1：使用者選 110／119 時呼叫 PlatformService.requestEmergency(userInitiated: true)。
  final Future<sw.EmergencyActionResult> Function(sw.EmergencyChannel channel)? onEmergency;

  /// M1：使用者確認簡訊內容後，交給手機開啟簡訊 App；null 時只模擬傳送畫面。
  final Future<bool> Function(String body)? onSendSms;
  final VoidCallback? onExit;

  @override
  State<SafeWalkFlow> createState() => _SafeWalkFlowState();
}

class _SafeWalkFlowState extends State<SafeWalkFlow> {
  _Screen _screen = _Screen.home;
  _Screen _back = _Screen.home;
  bool _forward = true;
  sw.Position? _position;
  String? _emergencyMessage;
  bool _emergencyError = false, _locating = false;
  final _callKey = GlobalKey<SafeWalkCallViewState>();

  /// 進行中的模擬來電；去地圖看路再回來會接續。結束通話、拒絕、緊急求助、回首頁時丟棄。
  SafeWalkCallSession? _call;
  late final List<SavedPlace> _places = [...demoPlaces()];
  String _placeId = 'home';
  SavedPlace get _place => _places.firstWhere((p) => p.id == _placeId, orElse: () => _places.first);
  // Live mode never shows invented danger points or stand-in assistance points.
  late final List<Anomaly> _anomalies = widget.mode == sw.DataMode.mock ? demoAnomalies() : <Anomaly>[];
  late final List<sw.AssistancePoint> _demoPoints = widget.mode == sw.DataMode.mock ? demoAssistancePoints() : const <sw.AssistancePoint>[];

  String? get _nearestPointName {
    final pts = _pointsState.points;
    if (pts.isEmpty) return null;
    final from = _position == null ? DemoGeo.start : LatLng(_position!.coordinates.lat, _position!.coordinates.lng);
    final sorted = [...pts]..sort((a, b) => metersBetween(from, LatLng(a.coordinates.lat, a.coordinates.lng)).compareTo(metersBetween(from, LatLng(b.coordinates.lat, b.coordinates.lng))));
    return sorted.first.name;
  }

  RouteState get _routeState => RouteState(result: widget.route, loading: widget.routeLoading, onRetry: widget.onPlanRoute == null ? null : _planRoute);

  void _planRoute() => widget.onPlanRoute?.call(sw.Coordinates(lat: _place.at.lat, lng: _place.at.lng));

  void _selectPlace(String id) {
    if (id == _placeId) return;
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
    if (_screen == _Screen.call && s != _Screen.call) _callKey.currentState?.leave();
    // 使用者明確打開地圖（點「安心行」主卡）時才請 M1 規劃路線；一進安心行不自動送出。
    if (s == _Screen.map && _screen != _Screen.map) _planRoute();
    if (s == _Screen.home) _call = null;
    setState(() {
      _forward = s != _Screen.home && s != _back;
      if (s == _Screen.call || s == _Screen.emergency) _back = _screen == _Screen.call ? _back : _screen;
      _screen = s;
    });
  }

  void _openEmergency() {
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
        _emergencyMessage = '示範模式不會取得位置；請說出附近的路名或地標。';
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
      _emergencyMessage = r?.message ?? '示範：沒有撥號，也沒有通知任何人。';
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget map({MapStartView start = MapStartView.route}) => SafeWalkMapView(
      key: ValueKey(start),
      position: _position,
      pointsState: _pointsState,
      routeState: _routeState,
      anomalies: _anomalies,
      startView: start,
      onAnomaliesChanged: () => setState(() {}),
      places: _places,
      placeId: _placeId,
      onSelectPlace: _selectPlace,
      onAddPlace: (name, at) {
        final p = SavedPlace('place-${DateTime.now().microsecondsSinceEpoch}', name, at);
        setState(() => _places.add(p));
        _selectPlace(p.id);
      },
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
        destination: _place.label,
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
      _Screen.map => map(),
      _Screen.points => map(start: MapStartView.points),
      _Screen.report => map(start: MapStartView.report),
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
        mode: widget.mode,
        allowRealCalls: widget.allowRealCalls,
        position: _position,
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
        if (!didPop) _go(_screen == _Screen.emergency || _screen == _Screen.call ? _back : _Screen.home);
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
