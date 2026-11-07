import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
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

  static const insideWarning = '你目前在回報範圍內';
  static const fallbackWarning = '暫時無法避讓回報點，這是一般步行路線';

  @override
  Future<sw.RouteResult> planRoute(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    if (request.mode != sw.DataMode.live) {
      return fallback.planRoute(request, cancellation: cancellation);
    }
    final AvoidRoutePlan plan;
    try {
      plan = await planner.plan(
        origin: request.origin.coordinates,
        destination: request.destination,
        areas: areas(),
        cancellation: cancellation,
      );
    } on WalkingRouteProviderUnavailable {
      final result = await fallback.planRoute(
        request,
        cancellation: cancellation,
      );
      return result is sw.RouteSuccess
          ? sw.RouteSuccess(
              requestId: result.requestId,
              mode: result.mode,
              generatedAt: result.generatedAt,
              routes: result.routes,
              warnings: [fallbackWarning, ...result.warnings],
            )
          : result;
    } on SafeWalkCancelledException {
      return _failure(request, sw.RouteFailureStatus.cancelled, '路線計算已取消');
    }
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
        '依 OpenStreetMap 步行路網計算，不保證沿途安全或目前可通行',
      ],
    );
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
