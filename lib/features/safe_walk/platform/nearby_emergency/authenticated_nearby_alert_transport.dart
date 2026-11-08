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

/// The verified identity of the person using the app. Where it comes from is
/// decided outside this file (`SupabaseAnonymousNearbySession` gives every phone a
/// server-issued anonymous one); nothing here creates accounts, stores
/// credentials or accepts a caller-chosen identity.
abstract interface class NearbyExistingIdentity {
  /// A token for an identity that already exists on this phone, or null. Never
  /// creates one.
  Future<String?> existingAccessToken();
}

abstract interface class NearbySession {
  /// True while the session can supply a token: a verified session exists, or
  /// one can be created on demand and the backend is not currently refusing.
  bool get isSignedIn;

  /// A current access token (JWT) for that session, or null when none can be
  /// had. Implementations create or refresh it as needed and must never log it.
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
    implements
        NearbyAlertTransport,
        NearbyAlertAvailability,
        NearbyAlertPreparation,
        NearbyHelperAreas,
        NearbyIdentityRestore,
        NearbyTrustedContacts {
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

  /// Shown when no identity can be had. There is no login in this app: the
  /// identity is made automatically, so this must never tell anyone to log in.
  static const identityUnavailableReason = '附近通知目前無法使用（服務尚未開啟，或暫時連不上）；請改用電話求助';

  static final _jwtShape = RegExp(
    r'^[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*$',
  );

  @override
  String? get currentUnavailableReason =>
      _session.isSignedIn ? null : identityUnavailableReason;

  @override
  Future<String?> prepare() async {
    final reason = currentUnavailableReason;
    if (reason != null) return reason;
    final token = await _session.accessToken();
    return token != null && _jwtShape.hasMatch(token.trim())
        ? null
        : identityUnavailableReason;
  }

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
            fromContact: row['from_contact'] == true,
            senderName: row['sender_name'] as String?,
          ),
      ];
    } on Object {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  @override
  Future<bool> restoreExistingIdentity() async {
    final session = _session;
    final token = session is NearbyExistingIdentity
        ? await (session as NearbyExistingIdentity).existingAccessToken()
        : await session.accessToken();
    return token != null && _jwtShape.hasMatch(token.trim());
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Object? _json(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  List<Map<String, dynamic>> _rows(String body) {
    final decoded = _json(body);
    if (decoded is! List) {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
    try {
      return decoded.cast<Map<String, dynamic>>();
    } on Object {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  @override
  Future<NearbyContactInvite> createContactInvite(String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty || name.runes.length > nearbyContactNameMax) {
      throw const NearbyAlertException('名字需要 1 到 20 個字');
    }
    final rows = _rows(
      await _call('nearby_contact_invite_create', {'p_display_name': name}),
    );
    try {
      final row = rows.single;
      return NearbyContactInvite(
        code: row['code'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } on Object {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  @override
  Future<NearbyInviteResult> acceptContactInvite(String code) async {
    final normalized = normalizeNearbyInviteCode(code);
    // A malformed code is never sent, so it does not use up an attempt.
    if (normalized == null) return NearbyInviteResult.invalid;
    final status = _json(
      await _call('nearby_contact_invite_accept', {'p_code': normalized}),
    );
    return switch (status) {
      'ok' => NearbyInviteResult.paired,
      'invalid' => NearbyInviteResult.invalid,
      'self' => NearbyInviteResult.self,
      'owner_full' => NearbyInviteResult.ownerFull,
      'following_full' => NearbyInviteResult.followingFull,
      _ => throw const NearbyAlertException('附近通知回應格式錯誤'),
    };
  }

  @override
  Future<List<NearbyContactLink>> listMyContacts() async {
    final rows = _rows(await _call('nearby_contact_list_mine', const {}));
    try {
      return [
        for (final row in rows)
          NearbyContactLink(
            id: row['link_id'] as String,
            since: DateTime.parse(row['since'] as String),
          ),
      ];
    } on Object {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  @override
  Future<void> removeContact(String linkId) async {
    if (!_uuid.hasMatch(linkId)) {
      throw const NearbyAlertException('找不到這位聯絡人');
    }
    await _call('nearby_contact_remove', {'p_link_id': linkId});
  }

  @override
  Future<List<NearbyFollowing>> listFollowing() async {
    final rows = _rows(await _call('nearby_contact_following', const {}));
    try {
      return [
        for (final row in rows)
          NearbyFollowing(
            id: row['link_id'] as String,
            name: row['display_name'] as String,
            since: DateTime.parse(row['since'] as String),
          ),
      ];
    } on Object {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  @override
  Future<void> unfollow(String linkId) async {
    if (!_uuid.hasMatch(linkId)) {
      throw const NearbyAlertException('找不到這位聯絡人');
    }
    await _call('nearby_contact_unfollow', {'p_link_id': linkId});
  }

  @override
  Future<List<NearbyGuardArea>> fetchGuardAreas() async {
    final body = await _call('nearby_helper_get_areas', const {});
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
          NearbyGuardArea(
            center: sw.Coordinates(
              lat: (row['lat'] as num).toDouble(),
              lng: (row['lng'] as num).toDouble(),
            ),
            radiusMeters: row['radius_m'] as int,
          ),
      ];
    } on Object {
      throw const NearbyAlertException('附近通知回應格式錯誤');
    }
  }

  @override
  Future<void> replaceGuardAreas(List<NearbyGuardArea> areas) async {
    if (areas.length > nearbyGuardAreaMax ||
        areas.any((a) => !nearbyGuardAreaRadii.contains(a.radiusMeters))) {
      throw const NearbyAlertException('守護區的數量或範圍不正確');
    }
    await _call('nearby_helper_set_areas', {
      'p_areas': [
        for (final area in areas)
          {
            'lat': area.center.lat,
            'lng': area.center.lng,
            'radius_m': area.radiusMeters,
          },
      ],
    });
  }

  /// One RPC under the current session. Failure messages never contain the
  /// token, the response body or coordinates.
  Future<String> _call(String function, Map<String, Object?> arguments) async {
    final unavailable = currentUnavailableReason;
    if (unavailable != null) throw NearbyAlertException(unavailable);
    final token = await _session.accessToken();
    if (token == null || !_jwtShape.hasMatch(token.trim())) {
      throw const NearbyAlertException(identityUnavailableReason);
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
    401 || 403 => '附近通知暫時無法驗證這支手機，請稍後再試',
    404 => '找不到，或已過期',
    409 => '已達上限',
    429 => '操作太頻繁，請稍後再試',
    400 || 422 => '附近通知要求無效',
    >= 500 => '附近通知服務暫時無法使用',
    _ => '附近通知失敗',
  };
}
