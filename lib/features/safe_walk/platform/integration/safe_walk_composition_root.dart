import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:town_pass/features/safe_walk/navigation/default_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_live_navigation_coordinator.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_transport.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// The native route opens the controlled Live walking-preview flow. No GPS or
/// route request starts on entry. Mock remains an explicit independent mode.
class SafeWalkCompositionRoot extends StatefulWidget {
  const SafeWalkCompositionRoot({
    super.key,
    this.platform,
    this.safetyData,
    this.speaker,
    this.routeService,
    this.routeTransport,
    this.onExit,
    this.mode = sw.DataMode.live,
  });

  /// Fixed for this route's lifetime. Use a new route/key to change modes.
  final sw.DataMode mode;

  final PlatformService? platform;
  final SafetyDataRepository? safetyData;

  /// Defaults to M2's existing service; never falls back from Live to Mock.
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
  SafeWalkLiveNavigationCoordinator? _liveNavigation;
  _RouteCancellation? _manualLocation;
  int _routeSequence = 0;
  bool _navigationActive = false;
  List<sw.AssistancePoint> _points = const [];
  bool _pointsLoading = true;
  String? _pointsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platform =
        widget.platform ??
        TownPassPlatformAdapter(
          mockPosition: widget.mode == sw.DataMode.mock
              ? sw.Position.fromJson({
                  'schemaVersion': '1.0.0',
                  'coordinates': {
                    'lat': DemoGeo.start.lat,
                    'lng': DemoGeo.start.lng,
                  },
                  'source': 'mock',
                  'accuracyMeters': null,
                  'observedAt': null,
                })
              : null,
        );
    _safetyData =
        widget.safetyData ??
        MockSafetyDataRepository(
          assistancePoints: widget.mode == sw.DataMode.mock
              ? demoAssistancePoints()
              : const [],
          areaStatistics: const [],
        );
    _speaker = widget.speaker ?? _deviceSpeaker();
    _navigation = SafeWalkNavigationController(
      routeService:
          widget.routeService ??
          DefaultRouteService(
            pointLookup: _lookupRoutePoints,
            liveProvider: OsrmWalkingRouteProvider(
              transport:
                  widget.routeTransport ??
                  RateLimitedRouteTransport(
                    inner: createDefaultJsonTransport(),
                    hasConsent: _routingAllowed,
                  ),
              hasConsent: _routingAllowed,
              pointLookup: _lookupRoutePoints,
            ),
          ),
      // These gates describe this PR's implemented preview seams, not physical
      // device verification. Readiness remains WIRED_NOT_VERIFIED.
      mode: widget.mode,
      livePresentationReady: widget.mode == sw.DataMode.live,
      liveProviderReady: widget.mode == sw.DataMode.live && !kIsWeb,
    );
    if (widget.mode == sw.DataMode.live) {
      _liveNavigation = SafeWalkLiveNavigationCoordinator(
        controller: _navigation,
        platform: _platform,
      );
      final state = WidgetsBinding.instance.lifecycleState;
      _liveNavigation!.setForeground(
        state == null || state == AppLifecycleState.resumed,
      );
    }
    unawaited(_loadPoints());
  }

  bool _routingAllowed() =>
      !_lifetime.isCancelled &&
      _navigation.liveNavigationAvailable &&
      _navigation.hasRoutingConsent &&
      (_liveNavigation?.hasLocationConsent ?? false) &&
      (_liveNavigation?.active ?? false) &&
      (_liveNavigation?.foreground ?? false);

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
    if (_navigation.mode == sw.DataMode.live) {
      throw StateError('Live planning must acquire its origin through M1.');
    }
    await _navigation.planRoute(request);
  }

  void _openNavigation() {
    if (_lifetime.isCancelled) return;
    _navigationActive = true;
    _liveNavigation?.openNavigation();
  }

  void _closeNavigation() {
    _navigationActive = false;
    _manualLocation?.cancel();
    if (_liveNavigation != null) {
      _liveNavigation!.closeNavigation();
    } else {
      _navigation.cancelRoute();
    }
  }

  void _cancelNavigation() {
    if (_liveNavigation != null) {
      _liveNavigation!.cancel();
    } else {
      _navigation.cancelRoute();
    }
  }

  void _destinationChanged() {
    if (_liveNavigation != null) {
      _liveNavigation!.destinationChanged();
    } else {
      _navigation.cancelRoute();
    }
  }

  void _setRoutingConsent(bool consent) {
    if (_liveNavigation != null) {
      _liveNavigation!.setRoutingConsent(consent);
    } else {
      _navigation.setRoutingConsent(consent);
    }
  }

  void _emergencyOpened() {
    _closeNavigation();
    unawaited(_stopForEmergency());
  }

  Future<void> _stopForEmergency() async {
    try {
      await _speaker.stopForEmergency().timeout(const Duration(seconds: 1));
    } catch (_) {
      // SOS UI never waits for broken audio cleanup.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _speaker.setLifecycleActive(active);
    _liveNavigation?.setForeground(active);
    if (!active) {
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
    if (_navigation.mode == sw.DataMode.live && widget.safetyData == null) {
      setState(() {
        _pointsLoading = false;
        _pointsError = '真實求助據點尚未配置；不顯示示範據點。';
      });
      return;
    }
    try {
      final points = await _safetyData.getAssistancePoints(
        mode: _navigation.mode,
        cancellation: request,
      );
      request.throwIfCancelled();
      const parser = ContractSafetyDataParser();
      final checked = points
          .map((point) {
            if (point.source.dataMode != _navigation.mode) {
              throw const FormatException(
                'Assistance point mode does not match the current session',
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
    _manualLocation?.cancel();
    final token = _manualLocation = _RouteCancellation();
    try {
      final result = await Future.any<sw.LocationResult>([
        Future.sync(
          () => _platform.getCurrentPosition(
            mode: _navigation.mode,
            userInitiated: true,
            cancellation: token,
          ),
        ),
        token.whenCancelled.then<sw.LocationResult>(
          (_) => throw const SafeWalkCancelledException(),
        ),
      ]);
      _lifetime.throwIfCancelled();
      token.throwIfCancelled();
      if (result is sw.LocationSuccess &&
          (_navigation.mode == sw.DataMode.mock
              ? result.position.source != sw.PositionSource.mock
              : result.position.source != sw.PositionSource.gps)) {
        return _locationFailure('定位來源與目前模式不符，請重試。');
      }
      if (result is sw.LocationSuccess &&
          _navigation.mode == sw.DataMode.live &&
          (positionProblems(result.position).isNotEmpty ||
              result.position.accuracyMeters == null ||
              result.position.accuracyMeters! > 100)) {
        return _locationFailure('定位資料無效或精度不足，請重新取得位置。');
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
    } finally {
      if (identical(_manualLocation, token)) _manualLocation = null;
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
    await _stopForEmergency();
    try {
      if (_lifetime.isCancelled) throw const SafeWalkCancelledException();
      return await _platform.requestEmergency(
        mode: _navigation.mode,
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
        'message': '求助管道尚未完成；未撥號、未傳送，也未通知任何人。',
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _liveNavigation ?? _navigation,
    builder: (context, child) => SafeWalkNavigationScope(
      mode: _navigation.mode,
      liveNavigationAvailable: _navigation.liveNavigationAvailable,
      hasRoutingConsent: _navigation.hasRoutingConsent,
      routeResult: _navigation.routeResult,
      routeLoading: _navigation.routeLoading,
      routeError: _navigation.routeError,
      createRouteRequest: _createRouteRequest,
      onPlanRoute: _planRoute,
      onCancelRoute: _cancelNavigation,
      onRoutingConsentChanged: _setRoutingConsent,
      onDestinationChanged: _destinationChanged,
      onNavigationOpened: _openNavigation,
      onNavigationClosed: _closeNavigation,
      onEmergencyOpened: _emergencyOpened,
      position: _liveNavigation?.position,
      locationLoading: _liveNavigation?.locationLoading ?? false,
      locationError: _liveNavigation?.locationError,
      hasLocationConsent: _liveNavigation?.hasLocationConsent ?? false,
      onLocationConsentChanged: _liveNavigation?.setLocationConsent,
      onPlanDestination: _liveNavigation?.planDestination,
      child: SafeWalkFlow(
        mode: _navigation.mode,
        allowRealCalls: false,
        points: _points,
        pointsLoading: _pointsLoading,
        pointsError: _pointsError,
        onRetryPoints: () => unawaited(_loadPoints()),
        route: _navigation.routeResult,
        routeLoading: _navigation.routeLoading,
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
    _lifetime.cancel();
    _manualLocation?.cancel();
    _pointsRequest?.cancel();
    _liveNavigation?.dispose();
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
