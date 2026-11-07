import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Coordinates an explicitly opened, consented Live walking-preview intent.
///
/// Construction, granting consent and returning to the foreground never obtain
/// a position. Only [planDestination] after [openNavigation] may do so. There is
/// no GPS watcher, stored location, demo fallback or external-app handoff here.
/// The injected [controller] remains owned and disposed by the composition root.
final class SafeWalkLiveNavigationCoordinator extends ChangeNotifier {
  SafeWalkLiveNavigationCoordinator({
    required this.controller,
    required this.platform,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _sessionId = _nextSessionId++ {
    controller.setRoutingConsent(false);
    controller.cancelRoute();
    controller.addListener(_forwardRouteState);
  }

  final SafeWalkNavigationController controller;
  final PlatformService platform;
  final DateTime Function() _clock;
  static int _nextSessionId = 0;
  final int _sessionId;
  int _requestSequence = 0;

  bool _hasLocationConsent = false;
  bool get hasLocationConsent => _hasLocationConsent;
  bool _hasRoutingConsent = false;
  bool get hasRoutingConsent => _hasRoutingConsent;
  bool _active = false;
  bool get active => _active;
  bool _foreground = true;
  bool get foreground => _foreground;
  sw.Position? _position;
  sw.Position? get position => _position;
  bool _locationLoading = false;
  bool get locationLoading => _locationLoading;
  String? _locationError;
  String? get locationError => _locationError;

  bool get liveNavigationAvailable =>
      controller.mode == sw.DataMode.live && controller.liveNavigationAvailable;
  sw.RouteResult? get routeResult => controller.routeResult;
  bool get routeLoading => controller.routeLoading;
  String? get routeError => controller.routeError;

  _LocationIntentCancellation? _intent;
  int _generation = 0;
  bool _disposed = false;
  bool _clearing = false;

  void setLocationConsent(bool consent) {
    if (_disposed || consent == _hasLocationConsent) return;
    _hasLocationConsent = consent;
    if (!consent) _clearIntent(deactivate: true);
    _notify();
  }

  void setRoutingConsent(bool consent) {
    if (_disposed || consent == _hasRoutingConsent) return;
    _hasRoutingConsent = consent;
    if (!consent) _clearIntent(deactivate: true);
    controller.setRoutingConsent(consent);
    _notify();
  }

  /// Call only for an explicit start/retry action, never from build or resume.
  /// Opening alone does not obtain GPS or send coordinates to a provider.
  void openNavigation() {
    if (_disposed || !_foreground || _active) return;
    _active = true;
    _locationError = null;
    _notify();
  }

  void closeNavigation() => cancel();

  /// Includes opening SOS: synchronously invalidate work before any handoff.
  /// A later attempt needs another explicit [openNavigation].
  void cancel() {
    if (_disposed) return;
    _clearIntent(deactivate: true);
    _notify();
  }

  /// Invalidate the old selection before requesting a newly chosen destination.
  /// This does not itself obtain GPS or plan another route.
  void destinationChanged() {
    if (_disposed) return;
    _clearIntent(deactivate: false);
    _notify();
  }

  void setForeground(bool foreground) {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) _clearIntent(deactivate: true);
    // Resuming never rearms navigation or retries pending location work.
    _notify();
  }

  Future<void> planDestination(sw.Coordinates destination) async {
    if (_disposed) return;
    _clearIntent(deactivate: false);
    final blocked = _blockedReason;
    if (blocked != null) {
      _locationError = blocked;
      _notify();
      return;
    }

    final generation = _generation;
    final token = _intent = _LocationIntentCancellation();
    _locationLoading = true;
    _notify();
    if (!_isCurrent(generation, token)) return;

    try {
      // Observe both late successes and errors, even if a platform ignores the
      // cooperative token. Cancellation releases the waiting UI immediately.
      final result = await Future.any<sw.LocationResult>([
        Future.sync(
          () => platform.getCurrentPosition(
            mode: sw.DataMode.live,
            userInitiated: true,
            cancellation: token,
          ),
        ),
        token.whenCancelled.then<sw.LocationResult>(
          (_) => throw const SafeWalkCancelledException(),
        ),
      ]);
      if (!_isCurrent(generation, token)) return;
      if (result is sw.LocationFailure) {
        _locationError = result.message;
        return;
      }

      final position = (result as sw.LocationSuccess).position;
      if (!_validPosition(position)) {
        _locationError = '未取得有效且即時的 GPS 起點；請重新定位，不會改用示範位置。';
        return;
      }
      _position = position;
      _locationLoading = false;
      _notify();
      // A listener can revoke consent, close the screen, or change destination
      // while consuming the location snapshot. Recheck before any route call.
      if (!_isCurrent(generation, token)) return;
      if (!_validPosition(position)) {
        _position = null;
        _locationError = '目前位置已過期，請重新取得起點。';
        return;
      }

      final now = _clock().toUtc();
      final request = sw.RouteRequest(
        requestId:
            'live-$_sessionId-${++_requestSequence}-${now.microsecondsSinceEpoch}',
        mode: sw.DataMode.live,
        origin: position,
        destination: destination,
        departAt: now.toIso8601String(),
        preference: sw.RouteKind.direct,
        maxExtraDistanceMeters: 500,
        assistancePointIds: const [],
      );
      await controller.planRoute(request);
    } on SafeWalkCancelledException {
      // Cancellation is an invalidated intent, not a recoverable location error.
    } catch (_) {
      if (_isCurrent(generation, token)) {
        _position = null;
        _locationError = '定位服務暫時無法使用，請確認權限後重新開始導航。';
      }
    } finally {
      if (_isCurrent(generation, token)) {
        _intent = null;
        _locationLoading = false;
        _notify();
      }
    }
  }

  String? get _blockedReason {
    if (!_foreground || !_active) return '請在前景明確開始導航後再查詢。';
    if (!_hasLocationConsent) return '請先同意使用 TownPass 取得目前位置。';
    if (!_hasRoutingConsent) return '請先同意將起訖座標傳送至第三方步行路線服務。';
    if (!liveNavigationAvailable) return '真實步行預覽尚未配置；不會取得位置或改用示範路線。';
    return null;
  }

  bool _validPosition(sw.Position position) =>
      position.source == sw.PositionSource.gps &&
      position.accuracyMeters != null &&
      position.accuracyMeters! <= 100 &&
      positionProblems(position, now: _clock()).isEmpty;

  bool _isCurrent(int generation, _LocationIntentCancellation token) =>
      !_disposed &&
      _generation == generation &&
      identical(_intent, token) &&
      !token.isCancelled &&
      _blockedReason == null;

  void _clearIntent({required bool deactivate}) {
    _generation++;
    _intent?.cancel();
    _intent = null;
    if (deactivate) _active = false;
    _position = null;
    _locationLoading = false;
    _locationError = null;
    _clearing = true;
    try {
      controller.cancelRoute();
    } finally {
      _clearing = false;
    }
  }

  void _forwardRouteState() {
    if (!_clearing) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.removeListener(_forwardRouteState);
    _clearIntent(deactivate: true);
    super.dispose();
  }
}

final class _LocationIntentCancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
