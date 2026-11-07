import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Live requests get up to three options from [planner], most-avoiding first
/// (never inside → not through centres → shortest). Mock requests, and live
/// requests while the planner is unreachable, go to [fallback] (OSRM).
final class AvoidingRouteService implements RouteService {
  AvoidingRouteService({
    required this.planner,
    required this.fallback,
    required this.areas,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AvoidingRoutePlanner planner;
  final RouteService fallback;
  final List<AvoidArea> Function() areas;
  final DateTime Function() _clock;
  int _latestCall = 0;

  static const insideWarning = '起點或目的地位於避讓緩衝區內，無法完整避開該區域';
  static const fallbackWarning = '暫時無法避讓緩衝區，這是一般步行路線';

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    final call = ++_latestCall;
    bool interrupted() =>
        (cancellation?.isCancelled ?? false) || call != _latestCall;
    sw.RouteFailure cancelled() =>
        _failure(request, sw.RouteFailureStatus.cancelled, '路線計算已取消');
    if (interrupted()) return cancelled();
    Future<sw.RouteResult> fallbackResult({required bool warning}) async {
      if (interrupted()) return cancelled();
      final result = await raceCancellation(
        fallback.planRoute(request, cancellation: cancellation),
        cancellation,
      );
      if (interrupted()) return cancelled();
      return warning && result is sw.RouteSuccess
          ? sw.RouteSuccess(
              requestId: result.requestId,
              mode: result.mode,
              generatedAt: result.generatedAt,
              routes: result.routes,
              warnings: [fallbackWarning, ...result.warnings],
            )
          : result;
    }

    try {
      if (request.mode != sw.DataMode.live) {
        return await fallbackResult(warning: false);
      }
      if (request.origin.source == sw.PositionSource.mock ||
          positionProblems(request.origin, now: _clock()).isNotEmpty ||
          distanceMeters(request.origin.coordinates, request.destination) < 1) {
        return _failure(
          request,
          sw.RouteFailureStatus.invalidInput,
          '起點位置無效，請重新取得位置並選擇不同的目的地',
        );
      }
      // The avoiding planner currently handles direct routes only. Preserve
      // existing via-point requests in the regular service instead of ignoring
      // the requested assistance points.
      if (request.preference == sw.RouteKind.viaAssistance ||
          request.assistancePointIds.isNotEmpty) {
        return await fallbackResult(warning: true);
      }
      final AvoidRoutePlan plan;
      try {
        plan = await raceCancellation(
          planner.plan(
            origin: request.origin.coordinates,
            destination: request.destination,
            areas: List.unmodifiable(areas()),
            cancellation: cancellation,
          ),
          cancellation,
        );
      } on WalkingRouteProviderUnavailable {
        if (interrupted()) return cancelled();
        return await fallbackResult(warning: true);
      }
      if (interrupted()) return cancelled();
      if (plan.options.isEmpty) {
        return _failure(request, sw.RouteFailureStatus.noRoute, '目前找不到可步行的路線。');
      }
      final inside =
          plan.originInsideAreaIds.isNotEmpty ||
          plan.destinationInsideAreaIds.isNotEmpty;
      return sw.RouteSuccess(
        requestId: request.requestId,
        mode: request.mode,
        generatedAt: _clock().toUtc().toIso8601String(),
        routes: [for (final o in plan.options.reversed) o.route],
        warnings: [
          if (inside) insideWarning,
          '50 公尺為產品設定的避讓緩衝，不代表官方犯罪範圍或定位精度',
          '依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行',
        ],
      );
    } on SafeWalkCancelledException {
      return cancelled();
    } catch (_) {
      if (interrupted()) return cancelled();
      return _failure(
        request,
        sw.RouteFailureStatus.providerUnavailable,
        '路線服務目前無法使用，請稍後重試',
      );
    }
  }

  sw.RouteFailure _failure(
    sw.RouteRequest request,
    sw.RouteFailureStatus status,
    String reason,
  ) => sw.RouteFailure(
    requestId: request.requestId,
    mode: request.mode,
    generatedAt: _clock().toUtc().toIso8601String(),
    status: status,
    reason: reason,
    warnings: const ['沒有產生路線'],
  );
}
