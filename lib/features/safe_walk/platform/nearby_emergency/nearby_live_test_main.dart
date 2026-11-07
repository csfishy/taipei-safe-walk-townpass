// Live Safe Walk SOS entry. It does not touch the mock Safe Walk shell.
//
// Run on devices you control:
// flutter run -t lib/features/safe_walk/platform/nearby_emergency/nearby_live_test_main.dart \
//   --dart-define=NEARBY_LIVE_ENABLED=true \
//   --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
//   --dart-define=SUPABASE_ANON_KEY=<publishable-key>
//
// Leave NEARBY_LIVE_ENABLED unset in any shared build; every button then stays disabled.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/anonymous_helper_id.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';

const _liveEnabled = bool.fromEnvironment('NEARBY_LIVE_ENABLED');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() => runApp(const _LiveSosApp());

class _LiveSosApp extends StatelessWidget {
  const _LiveSosApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '安心行 SOS',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0E7C86), useMaterial3: true),
    home: const _Bootstrap(),
  );
}

typedef _Setup = ({
  NearbyEmergencyService? service,
  EmergencyDispatch? dispatch,
  EmergencyContactStore contacts,
  String helperId,
});

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<_Setup> _setup = _load();

  Future<_Setup> _load() async {
    final helperId = await loadOrCreateHelperId(SharedPreferencesHelperIdStore());
    final contacts = SharedPreferencesEmergencyContactStore();
    final configured =
        _liveEnabled && _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
    if (!configured) {
      return (service: null, dispatch: null, contacts: contacts, helperId: helperId);
    }
    final platform = TownPassPlatformAdapter(readPosition: _readGps);
    final transport = SupabaseNearbyAlertTransport(
      baseUrl: Uri.parse(_supabaseUrl),
      anonKey: _supabaseAnonKey,
    );
    final service = NearbyEmergencyService(platform: platform, transport: transport);
    final dispatch = EmergencyDispatch(
      platform: platform,
      transport: transport,
      sms: ChannelSmsSender(),
      contacts: contacts,
    );
    return (service: service, dispatch: dispatch, contacts: contacts, helperId: helperId);
  }

  // Reads GPS only after a user action. The adapter maps permission and accuracy errors.
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
  Widget build(BuildContext context) => FutureBuilder<_Setup>(
    future: _setup,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(body: Center(child: Text('無法初始化裝置設定。')));
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final data = snapshot.data!;
      return NearbyLiveTestPage(
        service: data.service,
        dispatch: data.dispatch,
        contacts: data.contacts,
        helperId: data.helperId,
      );
    },
  );
}
