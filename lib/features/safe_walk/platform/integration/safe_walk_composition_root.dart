import 'dart:async';

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/default_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/route_follower.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/valhalla_avoiding_route_planner.dart';
import 'package:town_pass/features/safe_walk/platform/integration/avoiding_route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/platform/position_watch.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// M1's single composition boundary. The first native demo is explicitly mock.
/// Live location/data require M3's live-state presentation and approved providers
/// before this route can expose them; no flag silently mixes live and demo data.
class SafeWalkCompositionRoot extends StatefulWidget {
  const SafeWalkCompositionRoot({
    super.key,
    this.platform,
    this.safetyData,
    this.speaker,
    this.routeService,
    this.routeTransport,
    this.onExit,
    this.liveRoutes = false,
    this.watchPosition,
  });

  /// Continuous positions while the map is open; defaults to the device GPS.
  final Stream<sw.Position> Function()? watchPosition;

  /// Real walking routes: opening the map reads the device position (after the
  /// user agrees to share it with the OSM routing service) and asks OSRM for a
  /// route to the chosen place. Points, SOS and companion stay in Mock.
  final bool liveRoutes;

  final PlatformService? platform;
  final SafetyDataRepository? safetyData;

  /// Defaults to M2's service. Injection never changes the route's Mock mode.
  final RouteService? routeService;

  /// Optional transport for provider verification without public requests.
  final JsonTransport? routeTransport;

  /// Ownership transfers to this route, which disposes the speaker once.
  /// Defaults to on-device TTS; it stays text-only until a voice is confirmed.
  final SafeWalkRouteSpeaker? speaker;
  final VoidCallback? onExit;

  @override
  State<SafeWalkCompositionRoot> createState() =>
      _SafeWalkCompositionRootState();
}

class _SafeWalkCompositionRootState extends State<SafeWalkCompositionRoot>
    with WidgetsBindingObserver {
  final _lifetime = _RouteCancellation();
  _RouteCancellation? _pointsRequest;
  late final PlatformService _platform;
  late final SafetyDataRepository _safetyData;
  late final SafeWalkRouteSpeaker _speaker;
  late final SafeWalkNavigationController _navigation;
  int _routeSequence = 0;
  bool _navigationActive = false;
  List<sw.AssistancePoint> _points = const [];
  bool _pointsLoading = true;
  String? _pointsError;

  /// Unresolved reports to route around (50 m circles), sent by the map.
  List<AvoidArea> _areas = const [];

  /// Start point the user picked on the map; null = device GPS.
  sw.Coordinates? _manualOrigin;
  bool _askingConsent = false;

  // Route following: one follower per option; re-plan only when off all of them.
  sw.Coordinates? _destination;
  sw.RouteResult? _followed;
  List<RouteFollower> _followers = const [];
  StreamSubscription<sw.Position>? _watch;
  sw.Position? _livePosition;
  DateTime? _lastReplan;
  static const _replanGap = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platform =
        widget.platform ??
        TownPassPlatformAdapter(
          mockPosition: sw.Position.fromJson({
            'schemaVersion': '1.0.0',
            'coordinates': {'lat': DemoGeo.start.lat, 'lng': DemoGeo.start.lng},
            'source': 'mock',
            'accuracyMeters': null,
            'observedAt': null,
          }),
        );
    _safetyData =
        widget.safetyData ??
        MockSafetyDataRepository(
          assistancePoints: demoAssistancePoints(),
          areaStatistics: const [],
        );
    _speaker = widget.speaker ?? _deviceSpeaker();
    final transport = widget.routeTransport ?? createDefaultJsonTransport();
    bool hasConsent() =>
        _navigation.hasRoutingConsent &&
        _navigation.liveNavigationAvailable &&
        !_lifetime.isCancelled;
    final osrm = DefaultRouteService(
      pointLookup: _lookupRoutePoints,
      liveProvider: OsrmWalkingRouteProvider(
        transport: transport,
        hasConsent: hasConsent,
        pointLookup: _lookupRoutePoints,
      ),
    );
    _navigation = SafeWalkNavigationController(
      routeService:
          widget.routeService ??
          (widget.liveRoutes
              ? AvoidingRouteService(
                  planner: ValhallaAvoidingRoutePlanner(
                    transport: transport,
                    hasConsent: hasConsent,
                  ),
                  fallback: osrm,
                  areas: () => _areas,
                )
              : osrm),
      // M3 still draws demo geometry/ETA/PiP. M2 lifecycle fixes are included,
      // but real-provider/native validation remains pending. This UI cannot
      // enable either readiness gate.
      mode: widget.liveRoutes ? sw.DataMode.live : sw.DataMode.mock,
      livePresentationReady: widget.liveRoutes,
      liveProviderReady: widget.liveRoutes,
    );
    _navigation.addListener(_syncFollowing);
    unawaited(_loadPoints());
  }

  /// A new live route starts (or restarts) following; anything else stops it.
  void _syncFollowing() {
    final result = _navigation.routeResult;
    if (identical(result, _followed)) return;
    _followed = result;
    if (!widget.liveRoutes ||
        _manualOrigin != null ||
        !_navigationActive ||
        result is! sw.RouteSuccess ||
        result.mode != sw.DataMode.live) {
      if (result == null || result is sw.RouteFailure) return;
      _stopFollowing();
      return;
    }
    _followers = [for (final r in result.routes) RouteFollower(r)];
    _watch ??= (widget.watchPosition ?? watchDevicePosition)().listen(
      _onPosition,
      onError: (_) => _stopFollowing(),
    );
  }

  void _onPosition(sw.Position position) {
    if (!mounted || _followers.isEmpty) return;
    setState(() => _livePosition = position);
    final updates = [for (final f in _followers) f.update(position)];
    final offAll = updates.every((u) => u.shouldReroute);
    final destination = _destination;
    final now = DateTime.now();
    if (!offAll ||
        destination == null ||
        _navigation.routeLoading ||
        (_lastReplan != null && now.difference(_lastReplan!) < _replanGap)) {
      return;
    }
    _lastReplan = now;
    unawaited(
      _planRoute(
        _createRouteRequest(origin: position, destination: destination),
      ),
    );
  }

  void _stopFollowing() {
    unawaited(_watch?.cancel());
    _watch = null;
    _followers = const [];
    _livePosition = null;
  }

  Future<List<sw.AssistancePoint>> _lookupRoutePoints(
    List<String> ids, {
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    _lifetime.throwIfCancelled();
    // Only the already validated, same-mode M4 snapshot is available here.
    // No additional lookup, GPS request or Overpass query is started.
    return _points
        .where((point) => ids.contains(point.id))
        .toList(growable: false);
  }

  Future<void> _planRoute(sw.RouteRequest request) async {
    if (_lifetime.isCancelled || !_navigationActive) return;
    await _navigation.planRoute(request);
  }

  /// Map opened, destination changed or retry: consent → GPS → OSRM route.
  Future<void> _planTo(sw.Coordinates destination) async {
    if (_lifetime.isCancelled || _askingConsent) return;
    if (!_navigation.hasRoutingConsent) {
      _askingConsent = true;
      final agreed = await _askRoutingConsent();
      _askingConsent = false;
      if (agreed != true || !mounted) return;
      _navigation.setRoutingConsent(true);
    }
    _destination = destination;
    _openNavigation();
    final manual = _manualOrigin;
    if (manual != null) {
      await _planRoute(
        _createRouteRequest(
          origin: sw.Position(
            coordinates: manual,
            source: sw.PositionSource.manual,
            accuracyMeters: null,
            observedAt: DateTime.now().toUtc().toIso8601String(),
          ),
          destination: destination,
        ),
      );
      return;
    }
    final sw.LocationResult located;
    try {
      located = await _platform.getCurrentPosition(
        mode: _navigation.mode,
        userInitiated: true,
        cancellation: _lifetime,
      );
    } on SafeWalkCancelledException {
      return;
    }
    if (!mounted || _lifetime.isCancelled) return;
    if (located is! sw.LocationSuccess) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text((located as sw.LocationFailure).message)),
      );
      return;
    }
    await _planRoute(
      _createRouteRequest(origin: located.position, destination: destination),
    );
  }

  Future<bool?> _askRoutingConsent() => showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('規劃路線需要你的位置'),
      content: const Text(
        '會把你目前的位置、目的地和要避開的回報點，傳給 OpenStreetMap 步行路線服務'
        '（valhalla1.openstreetmap.de、routing.openstreetmap.de）來計算路線，不會傳給其他人。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('不要'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('同意'),
        ),
      ],
    ),
  );

  void _openNavigation() {
    if (!_lifetime.isCancelled) _navigationActive = true;
  }

  void _closeNavigation() {
    _stopFollowing();
    _navigationActive = false;
    _navigation.cancelRoute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _speaker.setLifecycleActive(active);
    // `inactive` is transient (a system dialog, or the browser window losing
    // focus on web); only really leaving the app clears the route.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _closeNavigation();
    }
    if (mounted) setState(() {});
  }

  SafeWalkRouteSpeaker _deviceSpeaker() {
    final speaker = TtsSafeWalkSpeaker.device();
    // Rebuild once the device answers, so the view's voice notice is accurate.
    unawaited(
      speaker.prepare().then((_) {
        if (mounted) setState(() {});
      }),
    );
    return speaker;
  }

  sw.RouteRequest _createRouteRequest({
    required sw.Position origin,
    required sw.Coordinates destination,
    sw.RouteKind? preference,
    int? maxExtraDistanceMeters,
    List<String>? assistancePointIds,
  }) => sw.RouteRequest(
    requestId: 'm1-route-${++_routeSequence}',
    mode: _navigation.mode,
    origin: origin,
    destination: destination,
    departAt: DateTime.now().toUtc().toIso8601String(),
    preference: preference ?? sw.RouteKind.direct,
    maxExtraDistanceMeters: maxExtraDistanceMeters ?? 500,
    assistancePointIds: assistancePointIds ?? const [],
  );

  void _exit() {
    _closeNavigation();
    _lifetime.cancel();
    _pointsRequest?.cancel();
    _speaker.stop();
    if (widget.onExit != null) {
      widget.onExit!();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  Future<void> _loadPoints() async {
    _pointsRequest?.cancel();
    final request = _pointsRequest = _RouteCancellation();
    setState(() {
      _points = const [];
      _pointsLoading = true;
      _pointsError = null;
    });
    try {
      final points = await _safetyData.getAssistancePoints(
        mode: sw.DataMode.mock,
        cancellation: request,
      );
      request.throwIfCancelled();
      const parser = ContractSafetyDataParser();
      final checked = points
          .map((point) {
            if (point.source.dataMode != sw.DataMode.mock) {
              throw const FormatException(
                'Live points cannot enter the mock demo',
              );
            }
            return parser.parseAssistancePoint(point.toJson());
          })
          .toList(growable: false);
      if (!mounted || request.isCancelled) return;
      setState(() => _points = List.unmodifiable(checked));
    } on SafeWalkCancelledException {
      return;
    } catch (_) {
      if (!mounted || request.isCancelled) return;
      setState(() => _pointsError = '求助地點暫時無法載入，請稍後重試。');
    } finally {
      if (mounted && !request.isCancelled) {
        setState(() => _pointsLoading = false);
      }
    }
  }

  Future<sw.LocationResult> _locate() async {
    try {
      final result = await _platform.getCurrentPosition(
        mode: sw.DataMode.mock,
        userInitiated: true,
        cancellation: _lifetime,
      );
      _lifetime.throwIfCancelled();
      if (result is sw.LocationSuccess &&
          result.position.source != sw.PositionSource.mock) {
        return _locationFailure('示範模式未取得示範位置，請重試。');
      }
      return result;
    } on SafeWalkCancelledException {
      return _locationFailure('定位操作已取消。');
    } on TimeoutException {
      return sw.LocationFailure(
        status: sw.LocationFailureStatus.timeout,
        message: '定位逾時，請重試或說出附近地標。',
      );
    } catch (_) {
      return _locationFailure('暫時無法取得位置，請重試或說出附近地標。');
    }
  }

  sw.LocationFailure _locationFailure(String message) => sw.LocationFailure(
    status: sw.LocationFailureStatus.unavailable,
    message: message,
  );

  Future<sw.EmergencyActionResult> _emergency(
    sw.EmergencyChannel channel,
  ) async {
    _closeNavigation();
    // Issue the stop before platform work; a broken audio adapter cannot leave
    // the emergency page waiting indefinitely.
    try {
      await _speaker.stopForEmergency().timeout(const Duration(seconds: 1));
    } catch (_) {
      // The mock action remains available even if cleanup fails.
    }
    try {
      if (_lifetime.isCancelled) throw const SafeWalkCancelledException();
      return await _platform.requestEmergency(
        mode: sw.DataMode.mock,
        channel: channel,
        userInitiated: true,
        allowRealCalls: false,
      );
    } catch (_) {
      return sw.EmergencyActionResult.fromJson({
        'schemaVersion': '1.0.0',
        'channel': channel.wireValue,
        'action': 'failed',
        'officialReceipt': null,
        'message': '示範求助暫時無法完成；未撥號、未傳送，也未通知任何人。',
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _navigation,
    builder: (context, child) => SafeWalkNavigationScope(
      mode: _navigation.mode,
      liveNavigationAvailable: _navigation.liveNavigationAvailable,
      hasRoutingConsent: _navigation.hasRoutingConsent,
      routeResult: _navigation.routeResult,
      routeLoading: _navigation.routeLoading,
      routeError: _navigation.routeError,
      createRouteRequest: _createRouteRequest,
      onPlanRoute: _planRoute,
      onCancelRoute: _navigation.cancelRoute,
      onRoutingConsentChanged: _navigation.setRoutingConsent,
      onDestinationChanged: _navigation.cancelRoute,
      onNavigationOpened: _openNavigation,
      onNavigationClosed: _closeNavigation,
      onEmergencyOpened: _closeNavigation,
      // Built here so route results, loading and live position reach the map.
      child: SafeWalkFlow(
        mode: sw.DataMode.mock,
        allowRealCalls: false,
        // Live mode shows no demo help points; real nearby places come later.
        points: widget.liveRoutes ? const [] : _points,
        pointsLoading: !widget.liveRoutes && _pointsLoading,
        pointsError: widget.liveRoutes ? null : _pointsError,
        onRetryPoints: () => unawaited(_loadPoints()),
        route: widget.liveRoutes ? _navigation.routeResult : null,
        livePosition: _livePosition,
        onLeaveMap: _closeNavigation,
        onStartChanged: widget.liveRoutes
            ? (origin) {
                _manualOrigin = origin;
                if (origin != null) _stopFollowing();
              }
            : null,
        routeLoading: widget.liveRoutes && _navigation.routeLoading,
        onPlanRoute: widget.liveRoutes
            ? (destination) => unawaited(_planTo(destination))
            : null,
        onReportsChanged: (spots) => _areas = [
          for (final spot in spots)
            AvoidArea(
              id: spot.id,
              center: spot.center,
              radiusMeters: AvoidArea.reportRadiusMeters,
              source: 'report',
            ),
        ],
        speaker: _speaker,
        onLocate: _locate,
        onEmergency: _emergency,
        onExit: _exit,
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopFollowing();
    _navigation.removeListener(_syncFollowing);
    _lifetime.cancel();
    _pointsRequest?.cancel();
    _navigation.dispose();
    unawaited(_speaker.dispose());
    super.dispose();
  }
}

final class _RouteCancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
