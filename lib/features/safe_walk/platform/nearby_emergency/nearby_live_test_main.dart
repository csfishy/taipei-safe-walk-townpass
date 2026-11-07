// Isolated contact-SMS device test entry. Nearby notifications stay unavailable.
//
// Run on devices you control:
// flutter run -t lib/features/safe_walk/platform/nearby_emergency/nearby_live_test_main.dart \
//   --dart-define=SMS_LIVE_TEST_ENABLED=true
//
// This flag does not enable a nearby backend. Runtime consent is also required.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const _smsTestEnabled = bool.fromEnvironment('SMS_LIVE_TEST_ENABLED');

void main() => runApp(const _LiveSosApp());

class _LiveSosApp extends StatelessWidget {
  const _LiveSosApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '安心行 SOS',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF0E7C86),
      useMaterial3: true,
    ),
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
    final contacts = SharedPreferencesEmergencyContactStore();
    if (!_smsTestEnabled) {
      return (service: null, dispatch: null, contacts: contacts, helperId: '');
    }
    final platform = _SmsTestPlatform();
    const transport = UnavailableNearbyAlertTransport();
    final dispatch = EmergencyDispatch(
      platform: platform,
      transport: transport,
      sms: ChannelSmsSender(),
      contacts: contacts,
    );
    return (
      service: null,
      dispatch: dispatch,
      contacts: contacts,
      helperId: '',
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

/// Checks the operation again after a system permission dialog, so returning
/// from the dialog cannot start a new GPS read after cancellation/backgrounding.
class _SmsTestPlatform extends TownPassPlatformAdapter {
  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) =>
      TownPassPlatformAdapter(
        readPosition: () async {
          cancellation?.throwIfCancelled();
          var permission = await geo.Geolocator.checkPermission();
          cancellation?.throwIfCancelled();
          if (permission == geo.LocationPermission.denied) {
            permission = await geo.Geolocator.requestPermission();
            cancellation?.throwIfCancelled();
          }
          if (permission == geo.LocationPermission.denied ||
              permission == geo.LocationPermission.deniedForever) {
            throw const geo.PermissionDeniedException(
              'location permission denied',
            );
          }
          return geo.Geolocator.getCurrentPosition(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              timeLimit: Duration(seconds: 8),
            ),
          );
        },
      ).getCurrentPosition(
        mode: mode,
        userInitiated: userInitiated,
        cancellation: cancellation,
      );
}
