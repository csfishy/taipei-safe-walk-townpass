import 'dart:async';
import 'dart:convert';

import 'package:town_pass/features/safe_walk/platform/nearby_emergency/anonymous_helper_id.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Version of the consent text shown before someone becomes a helper. The
/// backend stores it next to the consent time.
const nearbyHelperConsentVersion = '2026-11-08.v1';

/// The verified sign-in of the person using the app. Where this comes from
/// (TownPass login or Supabase Auth) is decided outside this file; nothing here
/// creates accounts, stores credentials or accepts a caller-chosen identity.
abstract interface class NearbySession {
  /// True only while a verified session exists.
  bool get isSignedIn;

  /// A current access token (JWT) for that session, or null when signed out.
  /// Implementations refresh it as needed and must never log it.
  Future<String?> accessToken();
}

/// Talks to the `nearby_*` RPCs in `supabase/nearby_helper/001_nearby_helper.sql`.
///
/// Identity is the server-verified session: the backend uses `auth.uid()`, so
/// the `senderId`/`helperId` arguments required by [NearbyAlertTransport] are
/// deliberately ignored and never sent. The backend returns only a recipient
/// count after an SOS, and alerts for a helper never include the sender.
///
/// This transport is not wired into the app. It becomes usable only when a
/// composition explicitly supplies a [NearbySession], and the backend itself
/// is Level C: it needs the team lead's authorization before any deployment.
final class AuthenticatedNearbyAlertTransport
    implements NearbyAlertTransport, NearbyAlertAvailability {
  AuthenticatedNearbyAlertTransport({
    required this._rpc,
    required this._session,
    this.consentVersion = nearbyHelperConsentVersion,
    String Function()? newRequestId,
  }) : _newRequestId = newRequestId ?? generateAnonymousHelperId;

  final SupabaseRpcClient _rpc;
  final NearbySession _session;
  final String consentVersion;
  final String Function() _newRequestId;

  /// The backend fixes the alert radius at 500 m.
  static const radiusMeters = 500;

  static const signedOutReason = '附近通知需要先登入，目前無法使用；請使用電話或緊急聯絡人求助';

  static final _jwtShape = RegExp(
    r'^[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*$',
  );

  @override
  String? get currentUnavailableReason =>
      _session.isSignedIn ? null : signedOutReason;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    if (!enabled) {
      await _call('nearby_helper_opt_out', const {});
      return;
    }
    if (location == null) {
      throw const NearbyAlertException('成為協助者需要一次目前位置');
    }
    await _call('nearby_helper_opt_in', {'p_consent_version': consentVersion});
    await _call('nearby_helper_report_location', {
      'p_lat': location.lat,
      'p_lng': location.lng,
    });
  }

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    if (radiusMeters != AuthenticatedNearbyAlertTransport.radiusMeters) {
      throw const NearbyAlertException('附近通知的範圍固定為 500 公尺');
    }
    final body = await _call('nearby_sos_send', {
      'p_lat': location.lat,
      'p_lng': location.lng,
      'p_client_request_id': _newRequestId(),
    });
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
    if (decoded is! int || decoded < 0) {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
    return decoded;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    final body = await _call('nearby_helper_fetch_alerts', const {});
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
    if (decoded is! List) {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
    try {
      return [
        for (final row in decoded.cast<Map<String, dynamic>>())
          NearbyAlert(
            alertId: row['alert_id'] as String,
            location: sw.Coordinates(
              lat: (row['lat'] as num).toDouble(),
              lng: (row['lng'] as num).toDouble(),
            ),
            radiusMeters: row['radius_m'] as int,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
      ];
    } on Object {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  /// One RPC under the current session. Failure messages never contain the
  /// token, the response body or coordinates.
  Future<String> _call(String function, Map<String, Object?> arguments) async {
    final unavailable = currentUnavailableReason;
    if (unavailable != null) throw NearbyAlertException(unavailable);
    final token = await _session.accessToken();
    if (token == null || !_jwtShape.hasMatch(token.trim())) {
      throw const NearbyAlertException(signedOutReason);
    }
    final SupabaseRpcResponse response;
    try {
      response = await _rpc.call(
        function,
        arguments,
        headers: {'Authorization': 'Bearer ${token.trim()}'},
      );
    } on SafeWalkCancelledException {
      rethrow;
    } on TimeoutException {
      throw const NearbyAlertException('附近通知連線逾時');
    } on Object {
      throw const NearbyAlertException('附近通知連線失敗');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw NearbyAlertException(_messageFor(response.statusCode));
  }

  static String _messageFor(int status) => switch (status) {
    401 || 403 => '附近通知需要登入，或沒有使用權限',
    429 => '操作太頻繁，請稍後再試',
    400 || 422 => '附近通知要求無效',
    >= 500 => '附近通知服務暫時無法使用',
    _ => '附近通知失敗',
  };
}
