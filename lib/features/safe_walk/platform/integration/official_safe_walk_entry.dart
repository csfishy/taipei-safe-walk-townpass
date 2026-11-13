import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/features/safe_walk/platform/integration/email_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/official_nearby_alerts.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_build.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';

/// Keeps the official route's navigation, consent and emergency callbacks while
/// selecting the separate email-test backend only in explicit preview builds.
class OfficialSafeWalkEntry extends StatefulWidget {
  const OfficialSafeWalkEntry({
    super.key,
    required this.flowBuilder,
    this.emailTest = emailLiveTestBuild,
    this.loadEmailTransport,
  });

  final Widget Function(NearbyAlertTransport?) flowBuilder;
  final bool emailTest;
  final Future<EmailLiveTestTransport> Function()? loadEmailTransport;

  @override
  State<OfficialSafeWalkEntry> createState() => _OfficialSafeWalkEntryState();
}

class _OfficialSafeWalkEntryState extends State<OfficialSafeWalkEntry> {
  Future<EmailLiveTestTransport>? _loading;
  NearbyAlertTransport? _normal;

  @override
  void initState() {
    super.initState();
    if (widget.emailTest) {
      _loading = _load();
    } else {
      _normal = createOfficialNearbyAlerts();
    }
  }

  Future<EmailLiveTestTransport> _load() async {
    if (widget.loadEmailTransport case final loader?) return loader();
    final config = SafeWalkSupabaseConfig.fromEnvironment();
    return EmailLiveTestTransport(
      rpc: SupabaseRpcClient(config: config),
      prefs: await SharedPreferences.getInstance(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.emailTest) return widget.flowBuilder(_normal);
    return FutureBuilder<EmailLiveTestTransport>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Live 測試設定無法載入，請確認安裝的是最新測試版本。'),
                    TextButton(
                      onPressed: () {
                        final retry = _load();
                        setState(() {
                          _loading = retry;
                        });
                      },
                      child: const Text('重新載入'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final transport = snapshot.data;
        if (transport == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return EmailLiveTestPage(
          transport: transport,
          flowBuilder: widget.flowBuilder,
        );
      },
    );
  }
}
