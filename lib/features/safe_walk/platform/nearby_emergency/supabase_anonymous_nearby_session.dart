import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/authenticated_nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_auth_client.dart';

/// Where the refresh token of this phone's anonymous identity is kept between
/// launches. It is a credential: losing it means a new identity (the old
/// helper profile and guard areas can no longer be reached), leaking it lets
/// someone act as this phone's identity.
abstract interface class NearbySessionStore {
  Future<String?> read();
  Future<void> write(String refreshToken);
  Future<void> clear();
}

/// App preferences. Not secure storage (`flutter_secure_storage` is not a
/// dependency), so OS backup and rooted-device access still apply; moving this to
/// secure storage is a recorded follow-up.
final class SharedPreferencesNearbySessionStore implements NearbySessionStore {
  static const _key = 'safe_walk.nearby_refresh_token';

  @override
  Future<String?> read() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, refreshToken)) {
      throw StateError('Could not save the nearby session');
    }
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

/// Gives every phone a server-issued anonymous identity for the nearby feature.
///
/// Nothing happens at construction or app start. The identity is created the
/// first time a feature action (joining as a helper, sending an SOS) asks for a
/// token, so a person who never uses the feature never gets one. The refresh
/// token is kept in a [NearbySessionStore] so the identity survives restarts.
///
/// What this is: a stable, server-verified owner for the person's helper profile,
/// positions and guard areas, so the backend's `auth.uid()` rules work.
/// What this is not: proof of who someone is, or of eligibility to receive
/// SOS locations. Anyone can obtain one, and reinstalling gives a new one.
///
/// [isSignedIn] means "can supply a token": the project is reachable and was
/// not recently refusing. After a refusal it reports false for [blockFor] so the
/// UI shows "unavailable" instead of retrying on every tap.
final class SupabaseAnonymousNearbySession implements NearbySession {
  SupabaseAnonymousNearbySession({
    required this._auth,
    required this._store,
    DateTime Function()? clock,
    this.refreshMargin = const Duration(seconds: 60),
    this.blockFor = const Duration(minutes: 5),
    this.retryAfterFailure = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  final SupabaseAuthClient _auth;
  final NearbySessionStore _store;
  final DateTime Function() _clock;
  final Duration refreshMargin;
  final Duration blockFor;
  final Duration retryAfterFailure;

  SupabaseAuthSession? _session;
  DateTime? _blockedUntil;
  Future<String?>? _inFlight;

  @override
  bool get isSignedIn {
    final until = _blockedUntil;
    return until == null || !_clock().isBefore(until);
  }

  @override
  Future<String?> accessToken() {
    final session = _session;
    if (session != null &&
        session.expiresAt.isAfter(_clock().toUtc().add(refreshMargin))) {
      return Future.value(session.accessToken);
    }
    if (!isSignedIn) return Future.value(null);
    // One request at a time; concurrent callers share its result.
    return _inFlight ??= _obtain().whenComplete(() => _inFlight = null);
  }

  Future<String?> _obtain() async {
    try {
      final refreshToken = _session?.refreshToken ?? await _store.read();
      if (refreshToken != null) {
        try {
          return await _adopt(await _auth.refresh(refreshToken));
        } on SupabaseAuthRejected {
          // The server no longer honours it: that identity is gone. Start a new
          // one below. (A transient failure is not caught here, so a flaky
          // network never throws away a good identity.)
          _session = null;
          await _store.clear();
        }
      }
      return await _adopt(await _auth.signUpAnonymously());
    } on SupabaseAuthRejected {
      _blockedUntil = _clock().add(blockFor);
      return null;
    } on Object {
      _blockedUntil = _clock().add(retryAfterFailure);
      return null;
    }
  }

  Future<String> _adopt(SupabaseAuthSession session) async {
    _session = session;
    _blockedUntil = null;
    try {
      // The refresh token rotates, so it is written every time it changes.
      await _store.write(session.refreshToken);
    } on Object {
      // The identity still works for this run; it just cannot be found again
      // after a restart (a new one is made then).
    }
    return session.accessToken;
  }
}
