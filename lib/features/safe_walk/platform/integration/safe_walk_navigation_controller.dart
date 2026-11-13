import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// M1 owns route work; M3 consumes these values and forwards user actions.
///
/// This controller consumes the existing position in [sw.RouteRequest]. It never
/// acquires GPS, stores coordinates, or substitutes mock data after a failure.
/// Its mode is fixed for its lifetime so a mode change requires a new session.
final class SafeWalkNavigationController extends ChangeNotifier {
  SafeWalkNavigationController({
    required this.routeService,
    this.mode = sw.DataMode.mock,
    this.livePresentationReady = false,
    this.liveProviderReady = false,
    this.allowOfflineRouting = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RouteService routeService;
  final DateTime Function() _clock;
  final sw.DataMode mode;

  /// Remains false until M3 can show real geometry, provenance and failures.
  final bool livePresentationReady;

  /// Remains false until the M2 consent/cancellation fixes are integrated and
  /// the live provider is approved for this composition.
  final bool liveProviderReady;

  /// Allows a local provider without granting permission to any transport.
  final bool allowOfflineRouting;

  bool get liveNavigationAvailable =>
      livePresentationReady && liveProviderReady;

  bool _hasRoutingConsent = false;
  bool get hasRoutingConsent => _hasRoutingConsent;

  sw.RouteResult? _routeResult;
  sw.RouteResult? get routeResult => _routeResult;
  bool _routeLoading = false;
  bool get routeLoading => _routeLoading;
  String? _routeError;
  String? get routeError => _routeError;

  _NavigationCancellation? _request;
  int _generation = 0;
  bool _disposed = false;

  /// Must follow an explicit third-party routing consent action. OS location
  /// permission alone is not consent to send coordinates to a routing service.
  void setRoutingConsent(bool consent) {
    if (_disposed || consent == _hasRoutingConsent) return;
    _hasRoutingConsent = consent;
    if (!consent) _clearRoute();
    notifyListeners();
  }

  /// Call for destination changes, explicit cancel, leaving navigation or SOS.
  /// Cancellation immediately clears the old route, including loading/errors;
  /// a provider that ignores the signal cannot restore it later.
  void cancelRoute() {
    if (_disposed) return;
    _clearRoute();
    notifyListeners();
  }

  void _clearRoute() {
    _generation++;
    _request?.cancel();
    _request = null;
    _routeResult = null;
    _routeLoading = false;
    _routeError = null;
  }

  /// Shows a route already planned through the same route analysis (one of
  /// the nearby stores compared beforehand) without asking the provider again.
  /// Following and re-planning then work on it like any planned route.
  void showRoute(sw.RouteResult result) {
    if (_disposed || result.mode != mode) return;
    if (mode == sw.DataMode.live &&
        (!liveNavigationAvailable ||
            (!hasRoutingConsent && !allowOfflineRouting))) {
      return;
    }
    _clearRoute();
    _routeResult = result;
    notifyListeners();
  }

  Future<void> planRoute(sw.RouteRequest request) async {
    if (_disposed) return;
    _clearRoute();
    final generation = _generation;

    final inputError = _inputError(request);
    if (inputError != null) {
      _routeResult = _failure(
        request,
        sw.RouteFailureStatus.invalidInput,
        inputError,
      );
      _routeError = inputError;
      notifyListeners();
      return;
    }
    if (mode == sw.DataMode.live &&
        (!liveNavigationAvailable ||
            (!hasRoutingConsent && !allowOfflineRouting))) {
      final reason = !liveNavigationAvailable
          ? '真實導航尚未開放；路線介面與供應商接線仍待完成。'
          : '請先同意將起訖座標傳送至第三方路線服務。';
      _routeResult = _failure(
        request,
        sw.RouteFailureStatus.providerUnavailable,
        reason,
      );
      _routeError = reason;
      notifyListeners();
      return;
    }

    final token = _request = _NavigationCancellation();
    _routeLoading = true;
    notifyListeners();
    if (!_isCurrent(generation, token)) return;

    // Register the cancellation race immediately. Both late success and late
    // errors are observed even when an injected service ignores cancellation.
    try {
      final result = await Future.any<sw.RouteResult>([
        Future.sync(() => routeService.planRoute(request, cancellation: token)),
        token.whenCancelled.then<sw.RouteResult>(
          (_) => throw const SafeWalkCancelledException(),
        ),
      ]);
      if (!_isCurrent(generation, token)) return;
      if (!_matches(request, result)) {
        _routeResult = _failure(
          request,
          sw.RouteFailureStatus.providerUnavailable,
          '路線結果與目前請求或資料模式不符，已拒絕。',
        );
      } else {
        _routeResult = result;
      }
      final current = _routeResult;
      _routeError =
          current is sw.RouteFailure &&
              current.status != sw.RouteFailureStatus.cancelled
          ? current.reason
          : null;
    } on SafeWalkCancelledException {
      if (!_isCurrent(generation, token)) return;
      _routeResult = _failure(
        request,
        sw.RouteFailureStatus.cancelled,
        '路線請求已取消。',
      );
    } catch (_) {
      if (!_isCurrent(generation, token)) return;
      _routeResult = _failure(
        request,
        sw.RouteFailureStatus.providerUnavailable,
        '路線服務暫時無法使用，請稍後重試。',
      );
      _routeError = (_routeResult as sw.RouteFailure).reason;
    } finally {
      if (_isCurrent(generation, token)) {
        _request = null;
        _routeLoading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int generation, _NavigationCancellation token) =>
      !_disposed &&
      generation == _generation &&
      identical(_request, token) &&
      !token.isCancelled;

  String? _inputError(sw.RouteRequest request) {
    if (request.mode != mode) return '路線請求與目前資料模式不符。';
    if (mode == sw.DataMode.mock &&
        request.origin.source != sw.PositionSource.mock) {
      return '示範模式只能使用示範位置。';
    }
    if (mode == sw.DataMode.live &&
        request.origin.source == sw.PositionSource.mock) {
      return '真實模式不能使用示範位置。';
    }
    if (positionProblems(request.origin, now: _clock()).isNotEmpty) {
      return '目前位置無效或已過期，請重新取得位置。';
    }
    return null;
  }

  bool _matches(sw.RouteRequest request, sw.RouteResult result) {
    if (result.requestId != request.requestId || result.mode != mode) {
      return false;
    }
    if (result is sw.RouteSuccess && mode == sw.DataMode.live) {
      return result.routes.every(
        (route) =>
            route.walkingNetworkVerified &&
            !route.provider.toLowerCase().contains('mock'),
      );
    }
    return true;
  }

  sw.RouteFailure _failure(
    sw.RouteRequest request,
    sw.RouteFailureStatus status,
    String reason,
  ) => sw.RouteFailure(
    requestId: request.requestId,
    mode: mode,
    generatedAt: _clock().toUtc().toIso8601String(),
    status: status,
    reason: reason,
    warnings: const ['未產生可使用的路線；不會改用示範路線。'],
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearRoute();
    super.dispose();
  }
}

final class _NavigationCancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
