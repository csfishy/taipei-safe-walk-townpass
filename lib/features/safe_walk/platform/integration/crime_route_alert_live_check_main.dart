// Standalone entry for the P0-2 route / crime reference check (issue #48). It
// does not change the official TownPass shell or the mock Safe Walk flow.
//
// flutter run -t lib/features/safe_walk/platform/integration/crime_route_alert_live_check_main.dart \
//   --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
//   --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
// Never pass a service_role / secret key; the configuration rejects it.
// Location comes from the existing TownPass GeoLocatorService after a tap;
// routes come from the public OSRM foot server only after explicit consent.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/features/safe_walk/navigation/default_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_live_check_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_service.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';
import 'package:town_pass/service/geo_locator_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Get.put(GeoLocatorService());
  final wiring = CrimeReferenceWiring.fromEnvironment();
  final transport = createDefaultJsonTransport();
  runApp(
    MaterialApp(
      title: 'Crime route alert live check',
      home: CrimeRouteAlertLiveCheckPage(
        platform: TownPassPlatformAdapter(),
        createRouteService: (hasConsent) => DefaultRouteService(
          liveProvider: OsrmWalkingRouteProvider(
            transport: transport,
            hasConsent: hasConsent,
            requestAlternatives: true,
          ),
        ),
        // No reviewed-boundary source is on main (PR #39's polygon is not), so
        // the page shows the explicit "no reliable area" state.
        alertService: CrimeRouteAlertService(repository: wiring.repository),
      ),
    ),
  );
}
