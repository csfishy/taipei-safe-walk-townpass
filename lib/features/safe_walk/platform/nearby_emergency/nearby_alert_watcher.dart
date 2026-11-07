import 'dart:async';

import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';

/// Polls for alerts addressed to this helper while the app is open and emits
/// each alert once. Background delivery needs push notifications (not built).
final class NearbyAlertWatcher {
  NearbyAlertWatcher({
    required this._service,
    required this.helperId,
    this.interval = const Duration(seconds: 10),
  });

  final NearbyEmergencyService _service;
  final String helperId;
  final Duration interval;

  final _controller = StreamController<NearbyAlert>.broadcast();
  final _seen = <String>{};
  Timer? _timer;
  bool _stopped = false;
  bool _disposed = false;
  int _generation = 0;
  int? _pollingGeneration;

  Stream<NearbyAlert> get alerts => _controller.stream;

  void start() {
    if (_disposed || _timer != null) return;
    _stopped = false;
    _timer ??= Timer.periodic(interval, (_) => unawaited(poll()));
  }

  void stop() {
    _stopped = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  /// Fetches once. The caller must already have helper consent.
  /// A newly created watcher permits an explicit poll without starting a timer;
  /// after stop(), start() is required before any further poll can run.
  /// Network errors are ignored so polling keeps running.
  Future<void> poll() async {
    final generation = _generation;
    if (_stopped || _disposed || _pollingGeneration == generation) return;
    _pollingGeneration = generation;
    try {
      final alerts = await _service.fetchPendingAlerts(helperId);
      for (final alert in alerts) {
        if (_stopped || _disposed || generation != _generation) return;
        if (_seen.add(alert.alertId)) {
          _controller.add(alert);
        }
      }
    } catch (_) {
      // Retry on the next tick.
    } finally {
      // A restarted watcher may already have a newer request in flight.
      if (_pollingGeneration == generation) _pollingGeneration = null;
    }
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    unawaited(_controller.close());
  }
}

/// Coordinates and the alert creation time; no external location link.
String nearbyAlertPopupText(NearbyAlert alert) {
  final lat = alert.location.lat.toStringAsFixed(6);
  final lng = alert.location.lng.toStringAsFixed(6);
  final createdAt = alert.createdAt.toUtc().toIso8601String();
  return '求助位置：$lat, $lng\n'
      '建立時間：$createdAt（UTC）';
}
