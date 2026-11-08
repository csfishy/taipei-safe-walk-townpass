import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/authenticated_nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/supabase_anonymous_nearby_session.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_auth_client.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';

/// The nearby-notification backend for the official entry: the authenticated
/// transport with an anonymous per-phone identity, using the project this build
/// is already configured for.
///
/// Returns null (the feature then shows "unavailable") when this build has no
/// Supabase configuration, or on the web, where the native HTTP client does not
/// exist. Building this opens nothing and creates no account: an identity is
/// created only when the person first joins as a helper or sends an SOS.
///
/// Whether it actually works depends on the project: the SQL in
/// `supabase/nearby_helper/` must be applied and anonymous sign-ins enabled,
/// both manual Level C steps. Until then every action fails with "unavailable".
NearbyAlertTransport? createOfficialNearbyAlerts({
  Map<String, String>? environment,
  bool? isWeb,
  NearbySessionStore? store,
  HttpClient Function()? createHttpClient,
}) {
  if (isWeb ?? kIsWeb) return null;
  final SafeWalkSupabaseConfig config;
  try {
    config = SafeWalkSupabaseConfig.fromEnvironment(environment: environment);
  } on SupabaseConfigurationException {
    return null;
  }
  return AuthenticatedNearbyAlertTransport(
    rpc: SupabaseRpcClient(config: config, createHttpClient: createHttpClient),
    session: SupabaseAnonymousNearbySession(
      auth: SupabaseAuthClient(
        config: config,
        createHttpClient: createHttpClient,
      ),
      store: store ?? SharedPreferencesNearbySessionStore(),
    ),
  );
}
