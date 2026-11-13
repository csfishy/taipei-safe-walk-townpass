// Explicit native debug entry. Never imported by lib/main.dart or official routes.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/main.dart' as townpass;
import 'package:town_pass/features/safe_walk/platform/integration/email_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/util/tp_colors.dart';

Future<void> main() async {
  if (!kDebugMode || kIsWeb) {
    throw UnsupportedError('Email Live test requires a native debug build');
  }
  WidgetsFlutterBinding.ensureInitialized();
  // Missing public configuration fails visibly; no fake or production fallback.
  final config = SafeWalkSupabaseConfig.fromEnvironment();
  final prefs = await SharedPreferences.getInstance();
  await townpass.initServices();
  final transport = EmailLiveTestTransport(
    rpc: SupabaseRpcClient(config: config),
    prefs: prefs,
  );
  runApp(
    GetMaterialApp(
      title: '臺北安心行 Live 測試',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: TPColors.primary500),
      ),
      home: EmailLiveTestPage(
        transport: transport,
        flowBuilder: (backend) =>
            SafeWalkCompositionRoot(liveRoutes: true, nearbyAlerts: backend),
      ),
    ),
  );
}
