// Standalone entry for the read-only crime reference live check. It does not
// change the official TownPass shell or the mock Safe Walk flow.
//
// flutter run -t lib/features/safe_walk/platform/integration/crime_reference_live_check_main.dart \
//   --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
//   --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
// (or the legacy --dart-define=SUPABASE_ANON_KEY=<anon-jwt>). Never pass a
// service_role / secret key; the configuration rejects it.
import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_live_check_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';

void main() {
  final wiring = CrimeReferenceWiring.fromEnvironment();
  runApp(
    MaterialApp(
      title: 'Crime reference live check',
      home: CrimeReferenceLiveCheckPage(repository: wiring.repository),
    ),
  );
}
