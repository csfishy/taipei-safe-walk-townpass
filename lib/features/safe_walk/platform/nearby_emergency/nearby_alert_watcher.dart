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
  bool _polling = false;

  Stream<NearbyAlert> get alerts => _controller.stream;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(poll()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Fetches once. Network errors are ignored so polling keeps running.
  Future<void> poll() async {
    if (_polling || _controller.isClosed) return;
    _polling = true;
    try {
      final alerts = await _service.fetchPendingAlerts(helperId);
      for (final alert in alerts) {
        if (_seen.add(alert.alertId) && !_controller.isClosed) {
          _controller.add(alert);
        }
      }
    } catch (_) {
      // Retry on the next tick.
    } finally {
      _polling = false;
    }
  }

  void dispose() {
    stop();
    unawaited(_controller.close());
  }
}

/// Popup text for a nearby alert: exact coordinates and a Google Maps link.
String nearbyAlertPopupText(NearbyAlert alert) {
  final lat = alert.location.lat.toStringAsFixed(6);
  final lng = alert.location.lng.toStringAsFixed(6);
  return '求助位置：$lat, $lng\n'
      '範圍：${alert.radiusMeters} 公尺內\n'
      '地圖：https://maps.google.com/?q=$lat,$lng';
}

String nearbyAlertMapUrl(NearbyAlert alert) {
  final lat = alert.location.lat.toStringAsFixed(6);
  final lng = alert.location.lng.toStringAsFixed(6);
  return 'https://maps.google.com/?q=$lat,$lng';
}
