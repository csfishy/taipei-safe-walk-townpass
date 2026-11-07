import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

sealed class NearbyEmergencyResult {
  const NearbyEmergencyResult();
}

final class NearbyEmergencySent extends NearbyEmergencyResult {
  const NearbyEmergencySent(this.recipientCount);
  final int recipientCount;
}

enum NearbyEmergencyBlock {
  mockMode,
  noUserAction,
  locationUnavailable,
  cancelled,
  transportFailed,
}

final class NearbyEmergencyNotSent extends NearbyEmergencyResult {
  const NearbyEmergencyNotSent(this.reason, this.message);
  final NearbyEmergencyBlock reason;
  final String message;
}

/// Coordinates the emergency tap: read location once, then alert opted-in
/// helpers inside [radiusMeters]. Nothing is sent without a user action, and
/// mock mode never reads device location or contacts the backend.
final class NearbyEmergencyService {
  NearbyEmergencyService({
    required this._platform,
    required this._transport,
    this.radiusMeters = 500,
  });

  final PlatformService _platform;
  final NearbyAlertTransport _transport;
  final int radiusMeters;

  Future<NearbyEmergencyResult> triggerEmergency({
    required sw.DataMode mode,
    required String senderId,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    if (mode == sw.DataMode.mock) {
      return const NearbyEmergencyNotSent(
        NearbyEmergencyBlock.mockMode,
        '示範模式不發送附近通知',
      );
    }
    if (!userInitiated) {
      return const NearbyEmergencyNotSent(
        NearbyEmergencyBlock.noUserAction,
        '需要使用者主動按下求助',
      );
    }

    final sw.Coordinates location;
    try {
      final result = await _platform.getCurrentPosition(
        mode: mode,
        userInitiated: true,
        cancellation: cancellation,
      );
      if (cancellation?.isCancelled ?? false) {
        return const NearbyEmergencyNotSent(
          NearbyEmergencyBlock.cancelled,
          '已取消',
        );
      }
      if (result is! sw.LocationSuccess) {
        final failure = result as sw.LocationFailure;
        return NearbyEmergencyNotSent(
          NearbyEmergencyBlock.locationUnavailable,
          failure.message,
        );
      }
      location = result.position.coordinates;
    } on SafeWalkCancelledException {
      return const NearbyEmergencyNotSent(NearbyEmergencyBlock.cancelled, '已取消');
    }

    try {
      final count = await _transport.sendEmergencyAlert(
        senderId: senderId,
        location: location,
        radiusMeters: radiusMeters,
      );
      return NearbyEmergencySent(count);
    } on Object {
      return const NearbyEmergencyNotSent(
        NearbyEmergencyBlock.transportFailed,
        '附近通知發送失敗，請改用電話求助',
      );
    }
  }

  /// Opting in shares the helper's current location once. It is not tracked.
  Future<void> setHelperOptIn({
    required sw.DataMode mode,
    required String helperId,
    required bool enabled,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    if (mode == sw.DataMode.mock) {
      throw const NearbyAlertException('Mock mode does not use the backend');
    }
    if (!userInitiated) {
      throw const NearbyAlertException('User action required');
    }
    sw.Coordinates? location;
    if (enabled) {
      final result = await _platform.getCurrentPosition(
        mode: mode,
        userInitiated: true,
        cancellation: cancellation,
      );
      if (result is! sw.LocationSuccess) {
        throw NearbyAlertException((result as sw.LocationFailure).message);
      }
      location = result.position.coordinates;
    }
    await _transport.setHelperOptIn(
      helperId: helperId,
      enabled: enabled,
      location: location,
    );
  }

  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) =>
      _transport.fetchPendingAlerts(helperId);
}
