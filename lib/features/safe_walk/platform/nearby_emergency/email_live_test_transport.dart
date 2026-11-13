import 'dart:async';
import 'dart:convert';

import 'package:email_validator/email_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/anonymous_helper_id.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_build.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Live TEST identity, not Supabase Auth or proof of email ownership.
/// Only swtest_* RPCs are used. Never accesses production nearby_* data.
/// The unverified email label is saved locally; bearer tokens stay in memory.
final class EmailLiveTestTransport
    implements
        NearbyAlertTransport,
        NearbyAlertAvailability,
        NearbyAlertPreparation,
        NearbyIdentityRestore {
  EmailLiveTestTransport({required this.rpc, required this.prefs}) {
    if (kIsWeb || (!kDebugMode && !emailLiveTestBuild)) {
      throw StateError(
        'Email login requires an explicit native Live-test build',
      );
    }
  }

  static const emailKey = 'safe_walk.live_test.email.v1';
  static const seenKey = 'safe_walk.live_test.email_prompt_seen.v1';
  final SupabaseRpcClient rpc;
  final SharedPreferences prefs;
  String? _email;
  String? _token;
  DateTime? _expires;
  int _epoch = 0;
  Future<void>? _refresh;

  String? get email => _email;
  bool get hasSession => _token != null;
  bool get hasSeenPrompt => prefs.getBool(seenKey) ?? false;

  static String? normalizeEmail(String raw) {
    final value = raw.trim().toLowerCase();
    return value.length <= 254 && EmailValidator.validate(value) ? value : null;
  }

  @override
  String? get currentUnavailableReason =>
      hasSession ? null : '請先輸入信箱建立 Live 測試身分；信箱不經驗證。';

  Future<void> skip() async {
    if (!await prefs.setBool(seenKey, true)) {
      throw const NearbyAlertException('無法保存測試入口設定，請重試。');
    }
  }

  Future<Object?> _request(String name, Map<String, Object?> args) async {
    try {
      final result = await rpc.call('swtest_$name', args);
      if (result.statusCode < 200 || result.statusCode >= 300) {
        final Object? decoded = jsonDecode(result.body);
        final message = decoded is Map ? decoded['message'] : null;
        throw NearbyAlertException(switch (message) {
          'live_test_disabled' => 'Live 測試後端尚未啟用或測試時段已結束。',
          'rate_limited' => '測試操作過於頻繁，請稍後再試。',
          'invalid_test_session' => '測試身分已失效，請重新輸入信箱。',
          'not_a_helper' => '請先加入測試協助者。',
          'test_account_limit' => '測試帳號已達上限，請聯絡維護者。',
          _ => '測試後端拒絕操作，請確認部署及測試設定。',
        });
      }
      return result.body.isEmpty ? null : jsonDecode(result.body);
    } on NearbyAlertException {
      rethrow;
    } on Object {
      throw const NearbyAlertException('測試後端連線或回應異常，請重試。');
    }
  }

  Future<void> login(String raw) async {
    final normalized = normalizeEmail(raw);
    if (normalized == null) {
      throw const NearbyAlertException('請輸入有效的 e-mail。');
    }
    final epoch = ++_epoch;
    await _login(normalized, epoch);
  }

  Future<void> _login(String normalized, int epoch) async {
    final result = await _request('login', {'p_email': normalized});
    try {
      final row = (result as List).single as Map;
      final token = row['test_session'] as String;
      final expires = DateTime.parse(row['expires_at'] as String).toUtc();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
          !expires.isAfter(DateTime.now().toUtc())) {
        throw const FormatException();
      }
      if (epoch != _epoch) return;
      if (!await prefs.setString(emailKey, normalized)) {
        throw const NearbyAlertException('無法保存測試帳號，請重試。');
      }
      if (epoch != _epoch) {
        await prefs.remove(emailKey);
        return;
      }
      _email = normalized;
      _token = token;
      _expires = expires;
      // Prompt persistence is secondary to the already saved account label.
      await prefs.setBool(seenKey, true);
    } on NearbyAlertException {
      rethrow;
    } on Object {
      throw const NearbyAlertException('測試登入回應格式錯誤。');
    }
  }

  @override
  Future<bool> restoreExistingIdentity() async {
    if (hasSession) return true;
    final saved = prefs.getString(emailKey);
    if (saved == null) return false;
    await login(saved);
    return hasSession;
  }

  @override
  Future<String?> prepare() async {
    if (!hasSession) return currentUnavailableReason;
    if (_expires!.isBefore(
      DateTime.now().toUtc().add(const Duration(seconds: 30)),
    )) {
      final epoch = _epoch;
      await (_refresh ??= _login(
        _email!,
        epoch,
      ).whenComplete(() => _refresh = null));
    }
    return currentUnavailableReason;
  }

  Future<Object?> _call(String name, Map<String, Object?> args) async {
    final reason = await prepare();
    if (reason != null) throw NearbyAlertException(reason);
    final epoch = _epoch;
    final result = await _request(name, {'p_test_session': _token, ...args});
    if (epoch != _epoch) throw const NearbyAlertException('測試帳號已登出。');
    return result;
  }

  /// Clears this device even if the server is unavailable. Returns whether
  /// revocation was confirmed; other devices' sessions are not removed.
  Future<bool> logout() async {
    ++_epoch;
    final token = _token;
    _token = null;
    _email = null;
    _expires = null;
    if (!await prefs.remove(emailKey)) {
      throw const NearbyAlertException('無法清除本機測試帳號，請重試。');
    }
    await skip();
    if (token == null) return true;
    try {
      await _request('logout', {'p_test_session': token});
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    if (!enabled) {
      await _call('opt_out', {});
      return;
    }
    if (location == null) throw const NearbyAlertException('加入需要目前位置。');
    await _call('opt_in', {'p_consent_version': 'live-test-email-2026-11-13'});
    await _call('report_location', {
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
    if (radiusMeters != 500) throw const NearbyAlertException('測試範圍固定 500 公尺。');
    final result = await _call('send', {
      'p_lat': location.lat,
      'p_lng': location.lng,
      'p_request_id': generateAnonymousHelperId(),
    });
    if (result is! int || result < 0) {
      throw const NearbyAlertException('測試發送回應格式錯誤。');
    }
    return result;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    final result = await _call('fetch', {});
    try {
      return (result as List).map((item) {
        final row = item as Map;
        return NearbyAlert(
          alertId: row['alert_id'] as String,
          location: sw.Coordinates(
            lat: (row['lat'] as num).toDouble(),
            lng: (row['lng'] as num).toDouble(),
          ),
          radiusMeters: 500,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }).toList();
    } on Object {
      throw const NearbyAlertException('測試通知回應格式錯誤。');
    }
  }
}
