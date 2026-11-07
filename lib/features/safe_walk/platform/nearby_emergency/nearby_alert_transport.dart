import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// An alert addressed to this helper. The sender's location is included only
/// because the sender explicitly pressed emergency.
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

  /// Returns how many opted-in helpers inside [radiusMeters] were alerted.
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  });

  /// Returns unseen alerts and marks them as seen.
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId);
}

/// Supabase (PostgREST RPC) implementation. Configure with
/// `--dart-define=SUPABASE_URL=...` and
/// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...` using [fromEnvironment].
/// Keys are never committed to the repository.
final class SupabaseNearbyAlertTransport implements NearbyAlertTransport {
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

  SupabaseNearbyAlertTransport.fromConfig(this._config, {HttpClient? client})
    : _client = client ?? HttpClient();

  factory SupabaseNearbyAlertTransport.fromEnvironment() =>
      SupabaseNearbyAlertTransport.fromConfig(
        SafeWalkSupabaseConfig.fromEnvironment(),
      );

  final SafeWalkSupabaseConfig _config;
  Uri get baseUrl => _config.url;
  String get anonKey => _config.apiKey;
  final HttpClient _client;
  bool _closed = false;

  static const _timeout = Duration(seconds: 10);

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    await _rpc('set_helper_opt_in', {
      'p_helper_id': helperId,
      'p_enabled': enabled,
      'p_lat': location?.lat,
      'p_lng': location?.lng,
    });
  }

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    final result = await _rpc('send_emergency_alert', {
      'p_sender_id': senderId,
      'p_lat': location.lat,
      'p_lng': location.lng,
      'p_radius_m': radiusMeters,
    });
    if (result is! int) {
      throw const NearbyAlertException('Unexpected alert response');
    }
    return result;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    final rows = await _rpc('fetch_pending_alerts', {'p_helper_id': helperId});
    if (rows is! List) {
      throw const NearbyAlertException('Unexpected alert list response');
    }
    return rows
        .map((row) {
          final map = row as Map<String, Object?>;
          return NearbyAlert(
            alertId: map['alert_id'] as String,
            senderId: map['sender_id'] as String,
            location: sw.Coordinates(
              lat: (map['lat'] as num).toDouble(),
              lng: (map['lng'] as num).toDouble(),
            ),
            radiusMeters: (map['radius_m'] as num).toInt(),
            createdAt: DateTime.parse(map['created_at'] as String),
          );
        })
        .toList(growable: false);
  }

  Future<Object?> _rpc(String name, Map<String, Object?> body) async {
    if (_closed) {
      throw const NearbyAlertException('Backend transport is closed');
    }
    try {
      final request = await _client
          .postUrl(baseUrl.resolve('/rest/v1/rpc/$name'))
          .timeout(_timeout);
      request.followRedirects = false;
      _config.requestHeaders.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(_timeout);
      final text = await utf8.decodeStream(response).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Status only: response bodies may echo request data.
        throw NearbyAlertException('Backend returned ${response.statusCode}');
      }
      return text.isEmpty ? null : jsonDecode(text);
    } on NearbyAlertException {
      rethrow;
    } on TimeoutException {
      throw const NearbyAlertException('Backend request timed out');
    } on Object {
      throw const NearbyAlertException('Backend request failed');
    }
  }

  /// The creator owns this transport and must close it after use.
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}
