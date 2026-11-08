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
  backendUnavailable,
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

  String? get unavailableReason => nearbyBackendUnavailableReason(_transport);

  /// Null when the backend can be used now. Waits for any identity the
  /// transport has to set up first (see [NearbyAlertPreparation]).
  Future<String?> _prepare() async {
    final reason = unavailableReason;
    if (reason != null) return reason;
    final transport = _transport;
    if (transport is NearbyAlertPreparation) {
      return (transport as NearbyAlertPreparation).prepare();
    }
    return null;
  }

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
    if (cancellation?.isCancelled ?? false) {
      return const NearbyEmergencyNotSent(
        NearbyEmergencyBlock.cancelled,
        '已取消',
      );
    }
    final String? backendFailure;
    try {
      backendFailure = await _whileActive(_prepare(), cancellation);
    } on SafeWalkCancelledException {
      return const NearbyEmergencyNotSent(
        NearbyEmergencyBlock.cancelled,
        '已取消',
      );
    }
    if (backendFailure != null) {
      return NearbyEmergencyNotSent(
        NearbyEmergencyBlock.backendUnavailable,
        backendFailure,
      );
    }

    final sw.Coordinates location;
    try {
      cancellation?.throwIfCancelled();
      final result = await _whileActive(
        _platform.getCurrentPosition(
          mode: mode,
          userInitiated: true,
          cancellation: cancellation,
        ),
        cancellation,
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
      return const NearbyEmergencyNotSent(
        NearbyEmergencyBlock.cancelled,
        '已取消',
      );
    }

    try {
      cancellation?.throwIfCancelled();
      final count = await _whileActive(
        _transport.sendEmergencyAlert(
          senderId: senderId,
          location: location,
          radiusMeters: radiusMeters,
        ),
        cancellation,
      );
      cancellation?.throwIfCancelled();
      return NearbyEmergencySent(count);
    } on SafeWalkCancelledException {
      // An already submitted request cannot be recalled; do not present its
      // late response as a new successful action after cancellation.
      return const NearbyEmergencyNotSent(
        NearbyEmergencyBlock.cancelled,
        '已取消',
      );
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
    cancellation?.throwIfCancelled();
    final backendFailure = await _whileActive(_prepare(), cancellation);
    if (backendFailure != null) throw NearbyAlertException(backendFailure);
    sw.Coordinates? location;
    if (enabled) {
      final result = await _whileActive(
        _platform.getCurrentPosition(
          mode: mode,
          userInitiated: true,
          cancellation: cancellation,
        ),
        cancellation,
      );
      cancellation?.throwIfCancelled();
      if (result is! sw.LocationSuccess) {
        throw NearbyAlertException((result as sw.LocationFailure).message);
      }
      location = result.position.coordinates;
    }
    cancellation?.throwIfCancelled();
    await _whileActive(
      _transport.setHelperOptIn(
        helperId: helperId,
        enabled: enabled,
        location: location,
      ),
      cancellation,
    );
    cancellation?.throwIfCancelled();
  }

  /// Whether the backend stores guard areas.
  bool get supportsGuardAreas => _transport is NearbyHelperAreas;

  NearbyHelperAreas get _areas {
    final transport = _transport;
    if (transport is! NearbyHelperAreas) {
      throw const NearbyAlertException('目前的後端不支援守護區');
    }
    return transport as NearbyHelperAreas;
  }

  Future<List<NearbyGuardArea>> fetchGuardAreas() => _areas.fetchGuardAreas();

  Future<void> replaceGuardAreas(List<NearbyGuardArea> areas) =>
      _areas.replaceGuardAreas(areas);

  /// One fresh position, read because the person asked for it (for example to
  /// set a guard area here). Throws [NearbyAlertException] with the reason when
  /// no position can be read.
  Future<sw.Coordinates> readCurrentPosition({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final result = await _whileActive(
      _platform.getCurrentPosition(
        mode: mode,
        userInitiated: true,
        cancellation: cancellation,
      ),
      cancellation,
    );
    cancellation?.throwIfCancelled();
    if (result is! sw.LocationSuccess) {
      throw NearbyAlertException((result as sw.LocationFailure).message);
    }
    return result.position.coordinates;
  }

  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) =>
      _transport.fetchPendingAlerts(helperId);
}

Future<T> _whileActive<T>(
  Future<T> operation,
  SafeWalkCancellation? cancellation,
) => cancellation == null
    ? operation
    : Future.any<T>([
        operation,
        cancellation.whenCancelled.then<T>(
          (_) => throw const SafeWalkCancelledException(),
        ),
      ]);
