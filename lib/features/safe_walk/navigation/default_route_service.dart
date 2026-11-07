import 'dart:async';

import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/mock_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// A provider may snap the ends of a route to the nearest walkable node, but
/// a route that starts or ends farther away than this is rejected.
const double maxEndpointSnapMeters = 500;

/// Builds [sw.RouteResult]s from an injected provider.
///
/// * `mock` requests use [mockProvider] (a labelled demo polyline).
/// * `live` requests use [liveProvider]; without one the result is
///   `provider_unavailable`, never a mock or straight-line route.
/// * Only the newest `planRoute` call may produce a route; an older call that
///   finishes later returns `cancelled`.
///
/// It only consumes the position inside the request and starts no GPS
/// listener. Errors from providers are reported with a fixed reason; their
/// messages (which may contain coordinates) are never copied into results.
final class DefaultRouteService implements RouteService {
  DefaultRouteService({
    this.mockProvider = const MockWalkingRouteProvider(),
    this.liveProvider,
    this.pointLookup,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WalkingRouteProvider mockProvider;
  final WalkingRouteProvider? liveProvider;
  final AssistancePointLookup? pointLookup;
  final DateTime Function() _clock;
  int _latestCall = 0;

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    final call = ++_latestCall;
    final base = (
      requestId: request.requestId,
      mode: request.mode,
      generatedAt: _clock().toUtc().toIso8601String(),
    );
    sw.RouteFailure fail(
      sw.RouteFailureStatus status,
      String reason, [
      List<String> warnings = const ['沒有產生路線'],
    ]) => sw.RouteFailure(
      requestId: base.requestId,
      mode: base.mode,
      generatedAt: base.generatedAt,
      status: status,
      reason: reason,
      warnings: warnings,
    );
    sw.RouteFailure cancelled(String reason) =>
        fail(sw.RouteFailureStatus.cancelled, reason, const ['沒有產生路線']);
    sw.RouteFailure? interruption() {
      if (cancellation?.isCancelled ?? false) return cancelled('使用者已取消');
      if (call != _latestCall) return cancelled('已被較新的路線請求取代');
      return null;
    }

    if (cancellation?.isCancelled ?? false) return cancelled('使用者已取消');

    final inputProblem = _inputProblem(request);
    if (inputProblem != null) {
      return fail(sw.RouteFailureStatus.invalidInput, inputProblem);
    }

    final provider = request.mode == sw.DataMode.live
        ? liveProvider
        : mockProvider;
    if (provider == null) {
      return fail(
        sw.RouteFailureStatus.providerUnavailable,
        '尚未設定真實步行路線供應商',
        const ['不以直線或示範資料冒充真實導航'],
      );
    }

    final List<sw.AssistancePoint> points;
    final List<sw.RouteCandidate> candidates;
    try {
      points = await _lookupPoints(request, cancellation);
      final interrupted = interruption();
      if (interrupted != null) return interrupted;
      final missing = request.assistancePointIds.where(
        (id) => !points.any((point) => point.id == id),
      );
      if (missing.isNotEmpty) {
        return fail(
          sw.RouteFailureStatus.invalidInput,
          '找不到途經據點：${missing.join('、')}',
        );
      }
      candidates = await _raceCancellation(
        provider.findRoutes(request, cancellation: cancellation),
        cancellation,
      );
    } on SafeWalkCancelledException {
      return cancelled('使用者已取消');
    } on WalkingRouteNotFound {
      final interrupted = interruption();
      if (interrupted != null) return interrupted;
      return fail(sw.RouteFailureStatus.noRoute, '找不到可步行的路線');
    } catch (_) {
      final interrupted = interruption();
      if (interrupted != null) return interrupted;
      return fail(sw.RouteFailureStatus.providerUnavailable, '路線供應商目前無法使用');
    }

    final interrupted = interruption();
    if (interrupted != null) return interrupted;
    if (candidates.isEmpty) {
      return fail(sw.RouteFailureStatus.noRoute, '找不到可步行的路線');
    }

    final endpointProblem = _endpointProblem(request, candidates);
    if (endpointProblem != null) {
      return fail(sw.RouteFailureStatus.providerUnavailable, endpointProblem);
    }

    final sw.RouteSuccess result;
    try {
      result = sw.RouteSuccess(
        requestId: base.requestId,
        mode: base.mode,
        generatedAt: base.generatedAt,
        routes: candidates,
        warnings: [
          if (request.mode == sw.DataMode.mock) '目前為示範模式，不提供安全保證',
          '路線僅反映所用路網，不保證路段安全、無障礙或實際可通行',
        ],
      );
    } on FormatException {
      return fail(
        sw.RouteFailureStatus.providerUnavailable,
        '路線供應商的結果未通過共用契約檢查',
      );
    }
    final problems = routeProblems(result, points: points);
    if (problems.isNotEmpty) {
      return fail(
        sw.RouteFailureStatus.providerUnavailable,
        '路線供應商的結果未通過檢查：${problems.join('；')}',
      );
    }
    return result;
  }

  String? _inputProblem(sw.RouteRequest request) {
    final origin = request.origin;
    final problems = positionProblems(origin, now: _clock());
    if (problems.isNotEmpty) return '起點位置無效：${problems.join('；')}';
    if (request.mode == sw.DataMode.live &&
        origin.source == sw.PositionSource.mock) {
      return '真實模式不能使用示範位置作為起點';
    }
    final from = origin.coordinates;
    final to = request.destination;
    if (!isValidLatLng(from.lat, from.lng) || !isValidLatLng(to.lat, to.lng)) {
      return '座標超出有效範圍';
    }
    if (distanceMeters(from, to) < 1) return '起點與終點相同';
    return null;
  }

  Future<List<sw.AssistancePoint>> _lookupPoints(
    sw.RouteRequest request,
    SafeWalkCancellation? cancellation,
  ) async {
    final ids = request.assistancePointIds;
    if (ids.isEmpty) return const [];
    final lookup = pointLookup;
    if (lookup == null) return const [];
    return _raceCancellation(
      lookup(ids, cancellation: cancellation),
      cancellation,
    );
  }

  String? _endpointProblem(
    sw.RouteRequest request,
    List<sw.RouteCandidate> candidates,
  ) {
    for (final candidate in candidates) {
      final line = candidate.geometry.coordinates;
      if (line.length < 2) return '路線供應商回傳的路線少於兩個座標';
      final startGap = distanceMeters(
        request.origin.coordinates,
        fromGeoJson(line.first),
      );
      final endGap = distanceMeters(
        request.destination,
        fromGeoJson(line.last),
      );
      if (startGap > maxEndpointSnapMeters || endGap > maxEndpointSnapMeters) {
        return '路線的起訖點與請求相差過遠，已拒絕';
      }
    }
    return null;
  }
}

/// Completes with [future], or throws [SafeWalkCancelledException] as soon as
/// [cancellation] fires. A result that arrives later is ignored.
Future<T> _raceCancellation<T>(
  Future<T> future,
  SafeWalkCancellation? cancellation,
) {
  if (cancellation == null) return future;
  final completer = Completer<T>();
  future.then(
    (value) {
      if (!completer.isCompleted) completer.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  cancellation.whenCancelled.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(const SafeWalkCancelledException());
    }
  });
  return completer.future;
}
