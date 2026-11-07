import 'dart:async';

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/navigation/default_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/companion_speaker_adapter.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
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
  });

  final PlatformService? platform;
  final SafetyDataRepository? safetyData;

  /// Defaults to M2's service. Injection never changes the route's Mock mode.
  final RouteService? routeService;

  /// Optional transport for provider verification without public requests.
  final JsonTransport? routeTransport;

  /// Ownership transfers to this route, which disposes the adapter once.
  final CompanionSpeakerAdapter? speaker;
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
  late final CompanionSpeakerAdapter _speaker;
  late final SafeWalkNavigationController _navigation;
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
    _speaker = widget.speaker ?? CompanionSpeakerAdapter.unavailable();
    _navigation = SafeWalkNavigationController(
      routeService:
          widget.routeService ??
          DefaultRouteService(
            pointLookup: _lookupRoutePoints,
            liveProvider: OsrmWalkingRouteProvider(
              transport: widget.routeTransport ?? createDefaultJsonTransport(),
              hasConsent: () =>
                  _navigation.hasRoutingConsent &&
                  _navigation.liveNavigationAvailable &&
                  !_lifetime.isCancelled,
              pointLookup: _lookupRoutePoints,
            ),
          ),
      // M3 still draws demo geometry/ETA/PiP. PR #15's M2 lifecycle fixes
      // also require separate review. Neither gate can be enabled by this UI.
      mode: sw.DataMode.mock,
      livePresentationReady: false,
      liveProviderReady: false,
    );
    unawaited(_loadPoints());
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

  void _openNavigation() {
    if (!_lifetime.isCancelled) _navigationActive = true;
  }

  void _closeNavigation() {
    _navigationActive = false;
    _navigation.cancelRoute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _closeNavigation();
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
    // the emergency page waiting indefinitely. No real audio is configured.
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
      child: child!,
    ),
    child: SafeWalkFlow(
      mode: sw.DataMode.mock,
      allowRealCalls: false,
      points: _points,
      pointsLoading: _pointsLoading,
      pointsError: _pointsError,
      onRetryPoints: () => unawaited(_loadPoints()),
      speaker: _speaker,
      onLocate: _locate,
      onEmergency: _emergency,
      onExit: _exit,
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
