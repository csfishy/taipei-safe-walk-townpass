import 'dart:io';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// An alert that a trusted backend has authorized this recipient to read.
/// Sender consent alone does not establish recipient eligibility or ownership.
final class NearbyAlert {
  const NearbyAlert({
    required this.alertId,
    required this.senderId,
    required this.location,
    required this.radiusMeters,
    required this.createdAt,
  });

  final String alertId;
  final String senderId;
  final sw.Coordinates location;
  final int radiusMeters;
  final DateTime createdAt;
}

final class NearbyAlertException implements Exception {
  const NearbyAlertException(this.message);
  final String message;
  @override
  String toString() => 'NearbyAlertException: $message';
}

/// Backend seam for nearby helper alerts. Implementations must never log or
/// put coordinates in a URL.
abstract interface class NearbyAlertTransport {
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  });

  /// Returns the backend's accepted recipient count, not proof of delivery.
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  });

  /// Returns unseen alerts and marks them as seen.
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId);
}

/// Marks a backend that must be rejected before collecting location.
/// This exposes a failure reason, never a client-controlled authorization flag.
abstract interface class UnavailableNearbyAlertBackend {
  String get unavailableReason;
}

/// Production placeholder with no credentials, identity, or network client.
final class UnavailableNearbyAlertTransport
    implements NearbyAlertTransport, UnavailableNearbyAlertBackend {
  const UnavailableNearbyAlertTransport();

  @override
  String get unavailableReason =>
      SupabaseNearbyAlertTransport.backendUnavailableReason;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async => throw NearbyAlertException(unavailableReason);

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async => throw NearbyAlertException(unavailableReason);

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async =>
      throw NearbyAlertException(unavailableReason);
}

/// Retired anonymous RPC transport, retained for configuration compatibility.
///
/// A publishable/anonymous key and a caller-supplied UUID do not authenticate a
/// person or establish recipient eligibility. All operations fail closed until
/// a separately reviewed authenticated backend replaces this implementation.
/// No environment flag, API key, or consent boolean enables network requests.
final class SupabaseNearbyAlertTransport
    implements NearbyAlertTransport, UnavailableNearbyAlertBackend {
  SupabaseNearbyAlertTransport({
    required Uri baseUrl,
    required String anonKey,
    HttpClient? client,
    bool allowInsecureLocalhost = false,
  }) : this.fromConfig(
         SafeWalkSupabaseConfig(
           url: baseUrl,
           apiKey: anonKey,
           allowInsecureLocalhost: allowInsecureLocalhost,
         ),
         client: client,
       );

  SupabaseNearbyAlertTransport.fromConfig(this._config, {this._client});

  factory SupabaseNearbyAlertTransport.fromEnvironment() =>
      SupabaseNearbyAlertTransport.fromConfig(
        SafeWalkSupabaseConfig.fromEnvironment(),
      );

  final SafeWalkSupabaseConfig _config;
  Uri get baseUrl => _config.url;
  String get anonKey => _config.apiKey;
  final HttpClient? _client;
  bool _closed = false;

  static const backendUnavailableReason =
      '附近通知尚未具備可信身分與接收資格驗證，目前無法使用；請使用電話或緊急聯絡人求助';

  @override
  String get unavailableReason => backendUnavailableReason;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    _rejectUnavailable();
  }

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    _rejectUnavailable();
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    _rejectUnavailable();
  }

  Never _rejectUnavailable() {
    if (_closed) {
      throw const NearbyAlertException('Backend transport is closed');
    }
    throw const NearbyAlertException(backendUnavailableReason);
  }

  /// The creator owns this transport and must close it after use.
  void close() {
    if (_closed) return;
    _closed = true;
    _client?.close(force: true);
  }
}
