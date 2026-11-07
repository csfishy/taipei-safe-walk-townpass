import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

class _Platform implements PlatformService {
  int locationCalls = 0;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    locationCalls++;
    return sw.LocationSuccess(
      position: sw.Position(
        coordinates: sw.Coordinates(lat: 25.033, lng: 121.5654),
        source: sw.PositionSource.gps,
        accuracyMeters: 10,
        observedAt: null,
      ),
    );
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) => throw UnimplementedError();
}

class _Transport implements NearbyAlertTransport {
  int sendCalls = 0;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {}

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    sendCalls++;
    return 3;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async => [];
}

const _helperId = '11111111-2222-4333-8444-555555555555';

Future<void> _pump(WidgetTester tester, NearbyEmergencyService? service) =>
    tester.pumpWidget(
      MaterialApp(
        home: NearbyLiveTestPage(service: service, helperId: _helperId),
      ),
    );

void main() {
  testWidgets('unconfigured page disables every action and sends nothing', (
    tester,
  ) async {
    await _pump(tester, null);

    expect(find.textContaining('所有按鈕已停用'), findsOneWidget);
    final sos = tester.widget<FilledButton>(
      find.ancestor(
        of: find.textContaining('SOS'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(sos.onPressed, isNull);
  });

  testWidgets('SOS sends the location once and shows the recipient count', (
    tester,
  ) async {
    final platform = _Platform();
    final transport = _Transport();
    await _pump(
      tester,
      NearbyEmergencyService(platform: platform, transport: transport),
    );

    await tester.tap(find.textContaining('SOS'));
    await tester.pumpAndSettle();

    expect(platform.locationCalls, 1);
    expect(transport.sendCalls, 1);
    expect(find.textContaining('已送出：3 位'), findsOneWidget);
  });
}
