// Standalone entry for the live nearby-alert test. It does not touch the
// official TownPass app or the mock Safe Walk shell.
//
// Run on two devices you control:
// flutter run -t lib/features/safe_walk/platform/nearby_emergency/nearby_live_test_main.dart \
//   --dart-define=NEARBY_LIVE_ENABLED=true \
//   --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
//   --dart-define=SUPABASE_ANON_KEY=<publishable-key>
//
// Leave NEARBY_LIVE_ENABLED unset in any shared build; every button then stays disabled.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/anonymous_helper_id.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';

const _liveEnabled = bool.fromEnvironment('NEARBY_LIVE_ENABLED');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() => runApp(const _NearbyLiveTestApp());

class _NearbyLiveTestApp extends StatelessWidget {
  const _NearbyLiveTestApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nearby live test',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0E7C86), useMaterial3: true),
    home: const _Bootstrap(),
  );
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<({NearbyEmergencyService? service, String helperId})> _setup =
      _load();

  Future<({NearbyEmergencyService? service, String helperId})> _load() async {
    final helperId = await loadOrCreateHelperId(SharedPreferencesHelperIdStore());
    final configured =
        _liveEnabled && _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
    if (!configured) return (service: null, helperId: helperId);
    final service = NearbyEmergencyService(
      platform: TownPassPlatformAdapter(readPosition: _readGps),
      transport: SupabaseNearbyAlertTransport(
        baseUrl: Uri.parse(_supabaseUrl),
        anonKey: _supabaseAnonKey,
      ),
    );
    return (service: service, helperId: helperId);
  }

  // Reads GPS only after a user action. Adapter maps permission and accuracy errors.
  Future<geo.Position> _readGps() async {
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      throw const geo.PermissionDeniedException('location permission denied');
    }
    return geo.Geolocator.getCurrentPosition(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({NearbyEmergencyService? service, String helperId})>(
        future: _setup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Scaffold(body: Center(child: Text('無法初始化測試裝置識別碼。')));
          }
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final data = snapshot.data!;
          return NearbyLiveTestPage(service: data.service, helperId: data.helperId);
        },
      );
}
