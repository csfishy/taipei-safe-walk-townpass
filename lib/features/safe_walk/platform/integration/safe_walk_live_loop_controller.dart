import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Where the official live loop currently is.
enum LiveLoopStage {
  /// Nothing in flight; waiting for an explicit user action.
  idle,
  locating,
  routing,

  /// The real route is shown; the crime reference query is in flight.
  assessing,

  /// The real route (and the crime reference outcome) is shown.
  ready,
  failed,
}

/// Explicit failure states. None of them is ever replaced by demo data.
enum LiveLoopFailure {
  locationConsentMissing,
  locationDenied,
  locationTimeout,
  locationUnavailable,

  /// The position is not a fresh, accurate device GPS fix.
  locationNotLive,

  /// The origin aged out before the route request; locate again.
  staleOrigin,
  routingConsentMissing,
  destinationMissing,
  noRoute,
  routeUnavailable,
  routeTimeout,

  /// The provider answered with something that is not a live walking route.
  routeNotLive,
  invalidInput,
  cancelled,

  /// The app went to the background; all work and the position were dropped.
  backgrounded,
}

/// Outcome of the crime reference step for the shown route.
enum LiveLoopReferenceState {
  notRequested,
  notConsented,
  loading,

  /// See [SafeWalkLiveLoopController.alert] for answered / not configured /
  /// failed / too large.
  done,
  timeout,
  failed,
}

/// M1 composition of the official live Safe Walk loop:
/// explicit location consent + explicit third-party routing consent ->
/// destination -> real OSRM walking route (M2) -> crime reference
/// information (M4 via [CrimeRouteAlertService]) -> map.
///
/// * GPS is read only from [locate], which only an explicit tap may call.
///   There is no watcher, no resume-triggered read and no stored position.
/// * Every step is guarded by a generation counter: a cancelled, superseded
///   or backgrounded request can never overwrite newer state.
/// * Any failure is an explicit [LiveLoopFailure]; nothing falls back to the
///   demo route, demo position or demo data.
/// * Route geometry is kept exactly as the provider returned it.
final class SafeWalkLiveLoopController extends ChangeNotifier {
  SafeWalkLiveLoopController({
    required this.platform,
    required this.routeService,
    required this.alertService,
    this.locationTimeout = const Duration(seconds: 15),
    this.routeTimeout = const Duration(seconds: 20),
    this.referenceTimeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PlatformService platform;
  final RouteService routeService;
  final CrimeRouteAlertService alertService;
  final Duration locationTimeout;
  final Duration routeTimeout;
  final Duration referenceTimeout;
  final DateTime Function() _clock;

  bool _locationConsent = false;
  bool get locationConsent => _locationConsent;
  bool _routingConsent = false;
  bool get routingConsent => _routingConsent;
  bool _referenceConsent = false;
  bool get referenceConsent => _referenceConsent;
  bool _foreground = true;
  bool get foreground => _foreground;

  LiveLoopStage _stage = LiveLoopStage.idle;
  LiveLoopStage get stage => _stage;
  LiveLoopFailure? _failure;
  LiveLoopFailure? get failure => _failure;
  String? _message;

  /// User-facing text for [failure] (or a neutral notice); never a coordinate.
  String? get message => _message;

  sw.Position? _origin;
  sw.Position? get origin => _origin;
  sw.Coordinates? _destination;
  sw.Coordinates? get destination => _destination;
  sw.RouteSuccess? _route;

  /// The unchanged provider result; null unless it is a live walking route.
  sw.RouteSuccess? get route => _route;
  LiveLoopReferenceState _referenceState = LiveLoopReferenceState.notRequested;
  LiveLoopReferenceState get referenceState => _referenceState;
  CrimeRouteAlert? _alert;
  CrimeRouteAlert? get alert => _alert;

  /// Reviewed areas with documented evidence; the only areas ever drawn.
  List<RouteReferenceArea> get reviewedAreas => alertService.reviewedAreas;

  bool get busy =>
      _stage == LiveLoopStage.locating || _stage == LiveLoopStage.routing;
  bool get canLocate => _foreground && _locationConsent && !busy;
  bool get canPlan =>
      _foreground &&
      _routingConsent &&
      _origin != null &&
      _destination != null &&
      !busy;

  int _generation = 0;
  int _sequence = 0;
  _Token? _token;
  bool _disposed = false;

  void setLocationConsent(bool value) {
    if (_disposed || value == _locationConsent) return;
    _locationConsent = value;
    if (!value) {
      _invalidate();
      _origin = null;
      _clearRoute();
      _setIdle();
    }
    _notify();
  }

  void setRoutingConsent(bool value) {
    if (_disposed || value == _routingConsent) return;
    _routingConsent = value;
    if (!value) {
      _invalidate();
      _clearRoute();
      _setIdle();
    }
    _notify();
  }

  void setReferenceConsent(bool value) {
    if (_disposed || value == _referenceConsent) return;
    _referenceConsent = value;
    // The shown route stays, but its reference outcome no longer matches the
    // consent; drop it rather than show a stale comparison.
    if (_stage == LiveLoopStage.assessing || _stage == LiveLoopStage.ready) {
      _invalidate();
      _alert = null;
      _referenceState = LiveLoopReferenceState.notRequested;
      if (_route != null) _stage = LiveLoopStage.ready;
    }
    _notify();
  }

  /// A new destination invalidates any in-flight route and the old result.
  void setDestination(sw.Coordinates? destination) {
    if (_disposed) return;
    if (destination != null &&
        !isValidLatLng(destination.lat, destination.lng)) {
      return;
    }
    _invalidate();
    _destination = destination;
    _clearRoute();
    _setIdle();
    _notify();
  }

  /// Explicit user tap only. Reads the device position once.
  Future<void> locate() async {
    if (_disposed) return;
    if (!_foreground) return;
    if (!_locationConsent) {
      _fail(LiveLoopFailure.locationConsentMissing);
      return;
    }
    final token = _begin(LiveLoopStage.locating);
    final generation = _generation;
    _origin = null;
    _clearRoute();
    _notify();
    sw.LocationResult result;
    try {
      result = await _guard(
        () => platform.getCurrentPosition(
          mode: sw.DataMode.live,
          userInitiated: true,
          cancellation: token,
        ),
        token,
        locationTimeout,
      );
    } on SafeWalkCancelledException {
      return;
    } on TimeoutException {
      if (!_current(generation)) return;
      token.cancel();
      _fail(LiveLoopFailure.locationTimeout);
      return;
    } catch (_) {
      if (!_current(generation)) return;
      _fail(LiveLoopFailure.locationUnavailable);
      return;
    }
    if (!_current(generation)) return;
    switch (result) {
      case sw.LocationFailure(:final status, :final message):
        _fail(switch (status) {
          sw.LocationFailureStatus.denied => LiveLoopFailure.locationDenied,
          sw.LocationFailureStatus.timeout => LiveLoopFailure.locationTimeout,
          _ => LiveLoopFailure.locationUnavailable,
        }, detail: message);
      case sw.LocationSuccess(:final position):
        if (!_isLiveFix(position)) {
          _fail(LiveLoopFailure.locationNotLive);
          return;
        }
        _origin = position;
        _token = null;
        _setIdle();
        _notify();
    }
  }

  /// Explicit user tap only: real OSRM walking route, then the crime
  /// reference information for that unchanged route.
  Future<void> planRoute() async {
    if (_disposed || !_foreground) return;
    if (!_routingConsent) {
      _fail(LiveLoopFailure.routingConsentMissing);
      return;
    }
    final origin = _origin;
    final destination = _destination;
    if (destination == null) {
      _fail(LiveLoopFailure.destinationMissing);
      return;
    }
    if (origin == null) {
      _fail(LiveLoopFailure.staleOrigin);
      return;
    }
    if (!_isLiveFix(origin)) {
      // Never silently re-read GPS; the user locates again.
      _origin = null;
      _fail(LiveLoopFailure.staleOrigin);
      return;
    }
    final token = _begin(LiveLoopStage.routing);
    final generation = _generation;
    _clearRoute();
    _notify();
    final now = _clock().toUtc();
    final request = sw.RouteRequest(
      requestId: 'live-loop-${++_sequence}-${now.microsecondsSinceEpoch}',
      mode: sw.DataMode.live,
      origin: origin,
      destination: destination,
      departAt: now.toIso8601String(),
      preference: sw.RouteKind.direct,
      maxExtraDistanceMeters: 500,
      assistancePointIds: const [],
    );
    sw.RouteResult result;
    try {
      result = await _guard(
        () => routeService.planRoute(request, cancellation: token),
        token,
        routeTimeout,
      );
    } on SafeWalkCancelledException {
      return;
    } on TimeoutException {
      if (!_current(generation)) return;
      token.cancel();
      _fail(LiveLoopFailure.routeTimeout);
      return;
    } catch (_) {
      if (!_current(generation)) return;
      _fail(LiveLoopFailure.routeUnavailable);
      return;
    }
    if (!_current(generation)) return;
    if (result.requestId != request.requestId) {
      _fail(LiveLoopFailure.routeNotLive);
      return;
    }
    switch (result) {
      case sw.RouteFailure(:final status, :final reason):
        _fail(switch (status) {
          sw.RouteFailureStatus.noRoute => LiveLoopFailure.noRoute,
          sw.RouteFailureStatus.invalidInput => LiveLoopFailure.invalidInput,
          sw.RouteFailureStatus.cancelled => LiveLoopFailure.cancelled,
          sw.RouteFailureStatus.providerUnavailable =>
            LiveLoopFailure.routeUnavailable,
        }, detail: reason);
        return;
      case sw.RouteSuccess():
        if (!_isLiveRoute(result)) {
          _fail(LiveLoopFailure.routeNotLive);
          return;
        }
        _route = result;
    }

    if (!_referenceConsent) {
      _referenceState = LiveLoopReferenceState.notConsented;
      _stage = LiveLoopStage.ready;
      _token = null;
      _notify();
      return;
    }
    final shown = _route!;
    _referenceState = LiveLoopReferenceState.loading;
    _stage = LiveLoopStage.assessing;
    _notify();
    try {
      final alert = await _guard(
        () => alertService.assess(shown, cancellation: token),
        token,
        referenceTimeout,
      );
      if (!_current(generation)) return;
      _alert = alert;
      _referenceState = LiveLoopReferenceState.done;
    } on SafeWalkCancelledException {
      return;
    } on TimeoutException {
      if (!_current(generation)) return;
      token.cancel();
      _referenceState = LiveLoopReferenceState.timeout;
    } catch (_) {
      if (!_current(generation)) return;
      _referenceState = LiveLoopReferenceState.failed;
    }
    _stage = LiveLoopStage.ready;
    _token = null;
    _notify();
  }

  /// Explicit cancel: drops in-flight work. The shown origin is kept.
  void cancel() {
    if (_disposed) return;
    final wasBusy =
        _stage != LiveLoopStage.idle &&
        _stage != LiveLoopStage.ready &&
        _stage != LiveLoopStage.failed;
    _invalidate();
    if (wasBusy) {
      _clearRoute();
      _fail(LiveLoopFailure.cancelled);
    } else {
      _notify();
    }
  }

  /// Background: cancel everything and drop the position; resuming never
  /// restarts work or reads GPS again on its own.
  void setForeground(bool foreground) {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) {
      final hadWork = _stage != LiveLoopStage.idle || _origin != null;
      _invalidate();
      _origin = null;
      _clearRoute();
      if (hadWork) {
        _fail(LiveLoopFailure.backgrounded);
        return;
      }
    }
    _notify();
  }

  /// Leaving the screen, SOS or exit: drop all work, the position, the
  /// destination and every consent. A new visit starts from nothing.
  void close() {
    if (_disposed) return;
    _invalidate();
    _locationConsent = false;
    _routingConsent = false;
    _referenceConsent = false;
    _origin = null;
    _destination = null;
    _clearRoute();
    _setIdle();
    _notify();
  }

  bool _isLiveFix(sw.Position position) =>
      position.source == sw.PositionSource.gps &&
      position.accuracyMeters != null &&
      position.accuracyMeters! <= 100 &&
      positionProblems(position, now: _clock()).isEmpty;

  static bool _isLiveRoute(sw.RouteSuccess route) =>
      route.mode == sw.DataMode.live &&
      route.routes.isNotEmpty &&
      route.routes.every(
        (c) =>
            c.walkingNetworkVerified &&
            !c.provider.toLowerCase().contains('mock'),
      );

  _Token _begin(LiveLoopStage stage) {
    _invalidate();
    final token = _token = _Token();
    _stage = stage;
    _failure = null;
    _message = null;
    return token;
  }

  void _invalidate() {
    _generation++;
    _token?.cancel();
    _token = null;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void _clearRoute() {
    _route = null;
    _alert = null;
    _referenceState = LiveLoopReferenceState.notRequested;
  }

  void _setIdle() {
    _stage = LiveLoopStage.idle;
    _failure = null;
    _message = null;
  }

  void _fail(LiveLoopFailure failure, {String? detail}) {
    _token = null;
    _stage = LiveLoopStage.failed;
    _failure = failure;
    _message = liveLoopFailureText(failure, detail: detail);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _invalidate();
    _disposed = true;
    super.dispose();
  }
}

String liveLoopFailureText(LiveLoopFailure failure, {String? detail}) {
  final text = switch (failure) {
    LiveLoopFailure.locationConsentMissing => '請先同意使用 TownPass 取得目前位置。',
    LiveLoopFailure.locationDenied => '定位權限未允許；可在系統設定調整後再按「取得目前位置」。',
    LiveLoopFailure.locationTimeout => '定位逾時，未取得起點；請再按一次「取得目前位置」。',
    LiveLoopFailure.locationUnavailable => '目前無法取得位置；請確認定位服務後重試。',
    LiveLoopFailure.locationNotLive => '取得的不是即時、精度足夠的裝置定位，未作為起點；不會改用示範位置。',
    LiveLoopFailure.staleOrigin => '起點位置已過期，請重新按「取得目前位置」；不會自動重新定位。',
    LiveLoopFailure.routingConsentMissing => '請先同意將起訖座標傳送至第三方 OSRM 步行路線服務。',
    LiveLoopFailure.destinationMissing => '請先在地圖上點選或輸入目的地。',
    LiveLoopFailure.noRoute => '找不到可步行的路線；不會改用示範路線或直線。',
    LiveLoopFailure.routeUnavailable => '步行路線服務目前無法使用（可能離線或服務中斷）；不會改用示範路線。',
    LiveLoopFailure.routeTimeout => '步行路線查詢逾時；不會改用示範路線，請稍後重試。',
    LiveLoopFailure.routeNotLive => '路線結果不是本次請求的真實步行路網結果，已拒絕顯示。',
    LiveLoopFailure.invalidInput => '起點或目的地無效，請重新選擇。',
    LiveLoopFailure.cancelled => '已取消；沒有顯示任何舊結果。',
    LiveLoopFailure.backgrounded => 'App 曾移至背景，已停止查詢並清除本次位置與路線；回到前景後請重新取得位置。',
  };
  // The provider reason is fixed text from M2 (never coordinates); the
  // platform message is fixed text from the adapter.
  return detail == null || detail.isEmpty ? text : '$text（$detail）';
}

/// Report-status screen: on every entry, query the reviewed crime reference
/// database for its current snapshot, and show only reviewed areas that carry
/// documented geographic evidence. Reference records are points, never areas,
/// so they are counted but never drawn as warning areas.
enum ReportStatusStage {
  idle,
  loading,

  /// The database answered; see [SafeWalkReportStatusController.result].
  answered,

  /// SUPABASE_URL / public key not configured; nothing was queried.
  notConfigured,
  failed,
  timeout,
  cancelled,
}

final class SafeWalkReportStatusController extends ChangeNotifier {
  SafeWalkReportStatusController({
    required this.repository,
    List<RouteReferenceArea> reviewedAreas = const [],
    this.timeout = const Duration(seconds: 15),
  }) : reviewedAreas = List.unmodifiable(reviewedAreas);

  final CrimeReferenceRepository repository;

  /// Only these (each with non-empty evidence) are shown as warning areas.
  final List<RouteReferenceArea> reviewedAreas;
  final Duration timeout;

  ReportStatusStage _stage = ReportStatusStage.idle;
  ReportStatusStage get stage => _stage;
  CrimeReferenceResult? _result;
  CrimeReferenceResult? get result => _result;
  CrimeReferenceFailure? _failure;
  CrimeReferenceFailure? get failure => _failure;

  /// Areas are only shown once the database answered for this visit.
  List<RouteReferenceArea> get evidencedAreas =>
      _stage == ReportStatusStage.answered
      ? reviewedAreas.where((a) => a.evidence.trim().isNotEmpty).toList()
      : const [];

  int _generation = 0;
  _Token? _token;
  bool _disposed = false;

  /// Called on every entry to the screen; a newer call supersedes older ones.
  Future<void> load() async {
    if (_disposed) return;
    _generation++;
    _token?.cancel();
    final generation = _generation;
    final token = _token = _Token();
    _stage = ReportStatusStage.loading;
    _result = null;
    _failure = null;
    _notify();
    try {
      final result = await _guard(
        () => repository.query(
          mode: sw.DataMode.live,
          // No location filter: the status query sends no position at all.
          query: const CrimeReferenceQuery(limit: 1),
          cancellation: token,
        ),
        token,
        timeout,
      );
      if (!_isCurrent(generation)) return;
      _result = result;
      _stage = ReportStatusStage.answered;
    } on SafeWalkCancelledException {
      return;
    } on TimeoutException {
      if (!_isCurrent(generation)) return;
      token.cancel();
      _stage = ReportStatusStage.timeout;
    } on SafeWalkDataUnavailable {
      if (!_isCurrent(generation)) return;
      _stage = ReportStatusStage.notConfigured;
    } on CrimeReferenceQueryException catch (error) {
      if (!_isCurrent(generation)) return;
      _failure = error.failure;
      _stage = error.failure == CrimeReferenceFailure.timeout
          ? ReportStatusStage.timeout
          : ReportStatusStage.failed;
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _stage = ReportStatusStage.failed;
    }
    _token = null;
    _notify();
  }

  /// Leaving the screen, background or exit.
  void cancel() {
    if (_disposed) return;
    final wasLoading = _stage == ReportStatusStage.loading;
    _generation++;
    _token?.cancel();
    _token = null;
    if (wasLoading) {
      _stage = ReportStatusStage.cancelled;
      _notify();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _generation++;
    _token?.cancel();
    _disposed = true;
    super.dispose();
  }
}

/// Races [work] against cancellation and a deadline; the timer is always
/// released so no work outlives the screen.
Future<T> _guard<T>(Future<T> Function() work, _Token token, Duration timeout) {
  final completer = Completer<T>();
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException(null, timeout));
    }
  });
  unawaited(
    token.whenCancelled.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(const SafeWalkCancelledException());
      }
    }),
  );
  Future.sync(work).then(
    (value) {
      if (!completer.isCompleted) completer.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future.whenComplete(timer.cancel);
}

final class _Token implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
