import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_watcher.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_helper.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// The helper side of "notify people nearby", delivered inside the app.
///
/// While a person has joined and the app is in the foreground, it
///  * refreshes their single stored position every [refreshInterval], and
///  * polls for alerts addressed to them every [pollInterval] and surfaces each
///    one once through [incoming].
///
/// There is no push channel: when the app is backgrounded or closed nothing is
/// polled or refreshed, the stored position expires on the server (10 minutes),
/// and no alert is received. Joining is the explicit, revocable consent for this
/// foreground sharing; nothing runs before the person confirmed it, and nothing
/// runs at all unless the injected backend is usable (a verified session).
final class NearbyHelperController extends ChangeNotifier
    implements SafeWalkNearbyHelper {
  NearbyHelperController({
    required this._service,
    this.pollInterval = const Duration(seconds: 10),
    this.refreshInterval = const Duration(minutes: 4),
    this.onAlertArrived,
  });

  final NearbyEmergencyService _service;
  final Duration pollInterval;
  final Duration refreshInterval;

  /// Called once per new alert, for example to vibrate.
  final void Function()? onAlertArrived;

  bool _on = false;
  bool _busy = false;
  bool _paused = false;
  bool _disposed = false;
  String? _message;
  bool _messageIsError = false;
  final _incoming = <SafeWalkNearbyAlert>[];
  final _areas = <SafeWalkGuardArea>[];
  final _known = <String>{};
  _Operation? _operation;
  NearbyAlertWatcher? _watcher;
  StreamSubscription<NearbyAlert>? _subscription;
  Timer? _refreshTimer;

  @override
  String? get unavailableReason => _service.unavailableReason;
  @override
  bool get isOn => _on;
  @override
  bool get isBusy => _busy;
  @override
  String? get message => _message;
  @override
  bool get messageIsError => _messageIsError;
  @override
  List<SafeWalkNearbyAlert> get incoming => List.unmodifiable(_incoming);
  @override
  bool get guardAreasSupported => _service.supportsGuardAreas;
  @override
  List<SafeWalkGuardArea> get guardAreas => List.unmodifiable(_areas);

  @override
  Future<void> enable() async {
    if (_disposed || _busy || _on) return;
    final reason = _service.unavailableReason;
    if (reason != null) {
      _say(reason, error: true);
      return;
    }
    _busy = true;
    _message = null;
    notifyListeners();
    final operation = _operation = _Operation();
    try {
      await _share(operation);
      if (_disposed || operation.isCancelled) return;
      _on = true;
      _paused = false;
      _say('已加入。App 開啟期間，附近有人求助時會通知你。', error: false, notify: false);
      _start();
      if (_service.supportsGuardAreas) unawaited(_loadAreas());
    } on SafeWalkCancelledException {
      // Left the page or stopped before it finished; nothing to report.
    } on Object catch (error) {
      if (_disposed) return;
      _say(_describe(error), error: true, notify: false);
    } finally {
      if (identical(_operation, operation)) _operation = null;
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  Future<void> disable() async {
    if (_disposed || _busy || !_on) return;
    _busy = true;
    _message = null;
    _stop();
    _operation?.cancel();
    notifyListeners();
    final operation = _operation = _Operation();
    var deleted = true;
    try {
      await _service.setHelperOptIn(
        mode: sw.DataMode.live,
        helperId: '',
        enabled: false,
        userInitiated: true,
        cancellation: operation,
      );
    } on Object {
      deleted = false;
    }
    if (_disposed) return;
    final hadAreas = _areas.isNotEmpty;
    _on = false;
    _paused = false;
    _busy = false;
    _operation = null;
    _areas.clear();
    _say(
      deleted
          ? '已停止協助，你的位置已刪除。${hadAreas ? '守護區也已刪除。' : ''}'
          : '已在這支手機停止協助，但沒有確認伺服器已刪除位置；位置最多 10 分鐘後會自動刪除，'
                '守護區則要再次停止協助成功後才會刪除。',
      error: !deleted,
    );
  }

  @override
  void dismiss(String alertId) {
    final before = _incoming.length;
    _incoming.removeWhere((a) => a.alertId == alertId);
    if (_incoming.length != before && !_disposed) notifyListeners();
  }

  @override
  Future<void> addGuardAreaHere(int radiusMeters) async {
    if (_disposed || _busy || !_on || !_service.supportsGuardAreas) return;
    if (!nearbyGuardAreaRadii.contains(radiusMeters) ||
        _areas.length >= nearbyGuardAreaMax) {
      return;
    }
    await _changeAreas('無法設定守護區，請稍後再試', '已新增守護區。', (operation) async {
      final here = await _service.readCurrentPosition(
        mode: sw.DataMode.live,
        cancellation: operation,
      );
      return [
        ..._current(),
        NearbyGuardArea(center: here, radiusMeters: radiusMeters),
      ];
    });
  }

  @override
  Future<void> removeGuardArea(int index) async {
    if (_disposed || _busy || !_on || !_service.supportsGuardAreas) return;
    if (index < 0 || index >= _areas.length) return;
    await _changeAreas('無法移除守護區，請稍後再試', '已移除守護區。', (_) async {
      final next = _current();
      next.removeAt(index);
      return next;
    });
  }

  List<NearbyGuardArea> _current() => [
    for (final a in _areas)
      NearbyGuardArea(center: a.center, radiusMeters: a.radiusMeters),
  ];

  /// Computes the new list, stores it, then shows what the server kept (it
  /// rounds the centres). Only one change runs at a time.
  Future<void> _changeAreas(
    String failure,
    String success,
    Future<List<NearbyGuardArea>> Function(SafeWalkCancellation) compute,
  ) async {
    _busy = true;
    _message = null;
    notifyListeners();
    final operation = _operation = _Operation();
    try {
      final next = await compute(operation);
      if (_disposed || operation.isCancelled) return;
      await _service.replaceGuardAreas(next);
      if (_disposed || operation.isCancelled) return;
      List<NearbyGuardArea> stored;
      try {
        stored = await _service.fetchGuardAreas();
      } on Object {
        stored = [
          for (final a in next)
            NearbyGuardArea(
              center: sw.Coordinates(
                lat: _round3(a.center.lat),
                lng: _round3(a.center.lng),
              ),
              radiusMeters: a.radiusMeters,
            ),
        ];
      }
      if (_disposed || operation.isCancelled) return;
      _setAreas(stored);
      _say(success, error: false, notify: false);
    } on SafeWalkCancelledException {
      // Left the page or stopped; nothing to report.
    } on Object catch (error) {
      if (_disposed) return;
      _say(_describe(error, failure), error: true, notify: false);
    } finally {
      if (identical(_operation, operation)) _operation = null;
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _loadAreas() async {
    try {
      final areas = await _service.fetchGuardAreas();
      if (_disposed || !_on) return;
      _setAreas(areas);
      notifyListeners();
    } on Object catch (error) {
      if (_disposed || !_on) return;
      _say(_describe(error, '無法讀取守護區'), error: true);
    }
  }

  void _setAreas(List<NearbyGuardArea> areas) {
    _areas
      ..clear()
      ..addAll([
        for (final a in areas)
          SafeWalkGuardArea(center: a.center, radiusMeters: a.radiusMeters),
      ]);
  }

  static double _round3(double v) => (v * 1000).round() / 1000;

  /// Foreground only. Going to the background stops polling and refreshing;
  /// coming back refreshes the position and resumes, because the person already
  /// consented to foreground sharing when joining.
  void setForeground(bool foreground) {
    if (_disposed || !_on) return;
    if (!foreground) {
      _paused = true;
      _stop();
      return;
    }
    if (_paused) {
      _paused = false;
      _start();
      unawaited(_refresh());
    }
  }

  Future<void> _share(_Operation operation) => _service.setHelperOptIn(
    mode: sw.DataMode.live,
    helperId: '',
    enabled: true,
    userInitiated: true,
    cancellation: operation,
  );

  Future<void> _refresh() async {
    if (_disposed || !_on || _paused || _busy) return;
    if (_service.unavailableReason != null) {
      // The session ended: stop locally rather than keep a half-working state.
      _on = false;
      _stop();
      _say('已登出，附近協助已停止。', error: true);
      return;
    }
    final operation = _operation = _Operation();
    try {
      await _share(operation);
      if (_disposed || operation.isCancelled) return;
      if (_messageIsError) _say(null, error: false);
    } on SafeWalkCancelledException {
      // Superseded by leaving or stopping.
    } on Object catch (error) {
      if (_disposed || operation.isCancelled) return;
      _say('位置更新失敗，附近的人可能暫時無法通知到你：${_describe(error)}', error: true);
    } finally {
      if (identical(_operation, operation)) _operation = null;
    }
  }

  void _start() {
    _stop();
    final watcher = _watcher = NearbyAlertWatcher(
      service: _service,
      helperId: '',
      interval: pollInterval,
    );
    _subscription = watcher.alerts.listen(_onAlert);
    watcher.start();
    unawaited(watcher.poll());
    _refreshTimer = Timer.periodic(
      refreshInterval,
      (_) => unawaited(_refresh()),
    );
  }

  void _stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _watcher?.dispose();
    _watcher = null;
  }

  void _onAlert(NearbyAlert alert) {
    if (_disposed || !_on || _paused || !_known.add(alert.alertId)) return;
    _incoming.insert(
      0,
      SafeWalkNearbyAlert(
        alertId: alert.alertId,
        location: alert.location,
        createdAt: alert.createdAt,
      ),
    );
    notifyListeners();
    onAlertArrived?.call();
  }

  void _say(String? text, {required bool error, bool notify = true}) {
    _message = text;
    _messageIsError = text != null && error;
    if (notify && !_disposed) notifyListeners();
  }

  String _describe(Object error, [String fallback = '無法加入附近協助，請稍後再試']) =>
      error is NearbyAlertException ? error.message : fallback;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stop();
    _operation?.cancel();
    super.dispose();
  }
}

final class _Operation implements SafeWalkCancellation {
  final _done = Completer<void>();
  @override
  bool get isCancelled => _done.isCompleted;
  @override
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}
