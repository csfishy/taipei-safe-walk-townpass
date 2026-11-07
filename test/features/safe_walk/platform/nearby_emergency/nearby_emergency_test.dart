import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/anonymous_helper_id.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

class _Cancellation implements SafeWalkCancellation {
  final _done = Completer<void>();
  @override
  bool get isCancelled => _done.isCompleted;
  @override
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!isCancelled) _done.complete();
  }
}

class _FakePlatform implements PlatformService {
  _FakePlatform({this.result});

  sw.LocationResult? result;
  int locationCalls = 0;
  bool? lastUserInitiated;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    locationCalls++;
    lastUserInitiated = userInitiated;
    return result ??
        sw.LocationSuccess(
          position: sw.Position(
            coordinates: sw.Coordinates(lat: 25.033, lng: 121.5654),
            source: sw.PositionSource.gps,
            accuracyMeters: 12,
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

class _FakeTransport implements NearbyAlertTransport {
  int sendCalls = 0;
  int? nextCount = 2;
  bool fail = false;
  sw.Coordinates? sentLocation;
  int? sentRadius;
  String? sentSender;
  final optIns = <({String helperId, bool enabled, sw.Coordinates? location})>[];

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    optIns.add((helperId: helperId, enabled: enabled, location: location));
  }

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    sendCalls++;
    sentSender = senderId;
    sentLocation = location;
    sentRadius = radiusMeters;
    if (fail) throw const NearbyAlertException('Backend request failed');
    return nextCount!;
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async => [];
}

void main() {
  const senderId = '11111111-2222-4333-8444-555555555555';

  test('anonymous helper IDs are UUID v4 and persisted once created', () async {
    final id = generateAnonymousHelperId();
    expect(isValidAnonymousHelperId(id), isTrue);
    expect(isValidAnonymousHelperId('not-an-id'), isFalse);

    final store = _MemoryStore();
    final first = await loadOrCreateHelperId(store);
    final second = await loadOrCreateHelperId(store);
    expect(first, second);
    expect(isValidAnonymousHelperId(first), isTrue);
  });

  test('mock mode never reads location or contacts the backend', () async {
    final platform = _FakePlatform();
    final transport = _FakeTransport();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
    );

    final result = await service.triggerEmergency(
      mode: sw.DataMode.mock,
      senderId: senderId,
      userInitiated: true,
    );

    expect(result, isA<NearbyEmergencyNotSent>());
    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.mockMode,
    );
    expect(platform.locationCalls, 0);
    expect(transport.sendCalls, 0);
  });

  test('without a user action nothing is read or sent', () async {
    final platform = _FakePlatform();
    final transport = _FakeTransport();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
    );

    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: senderId,
      userInitiated: false,
    );

    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.noUserAction,
    );
    expect(platform.locationCalls, 0);
    expect(transport.sendCalls, 0);
  });

  test('a successful tap sends the sender location and radius once', () async {
    final platform = _FakePlatform();
    final transport = _FakeTransport();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
      radiusMeters: 300,
    );

    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: senderId,
      userInitiated: true,
    );

    expect(result, isA<NearbyEmergencySent>());
    expect((result as NearbyEmergencySent).recipientCount, 2);
    expect(platform.lastUserInitiated, isTrue);
    expect(transport.sendCalls, 1);
    expect(transport.sentSender, senderId);
    expect(transport.sentRadius, 300);
    expect(transport.sentLocation!.lat, 25.033);
    expect(transport.sentLocation!.lng, 121.5654);
  });

  test('location failure blocks sending and reports the reason', () async {
    final platform = _FakePlatform(
      result: sw.LocationFailure(
        status: sw.LocationFailureStatus.denied,
        message: '定位權限未開啟',
      ),
    );
    final transport = _FakeTransport();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
    );

    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: senderId,
      userInitiated: true,
    );

    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.locationUnavailable,
    );
    expect(result.message, '定位權限未開啟');
    expect(transport.sendCalls, 0);
  });

  test('cancellation before the send prevents the alert', () async {
    final cancellation = _Cancellation()..cancel();
    final platform = _FakePlatform();
    final transport = _FakeTransport();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
    );

    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: senderId,
      userInitiated: true,
      cancellation: cancellation,
    );

    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.cancelled,
    );
    expect(transport.sendCalls, 0);
  });

  test('transport failure is reported without throwing', () async {
    final transport = _FakeTransport()..fail = true;
    final service = NearbyEmergencyService(
      platform: _FakePlatform(),
      transport: transport,
    );

    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: senderId,
      userInitiated: true,
    );

    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.transportFailed,
    );
  });

  test('opting in shares one location; opting out sends none', () async {
    final transport = _FakeTransport();
    final service = NearbyEmergencyService(
      platform: _FakePlatform(),
      transport: transport,
    );
    const helper = '66666666-7777-4888-8999-aaaaaaaaaaaa';

    await service.setHelperOptIn(
      mode: sw.DataMode.live,
      helperId: helper,
      enabled: true,
      userInitiated: true,
    );
    await service.setHelperOptIn(
      mode: sw.DataMode.live,
      helperId: helper,
      enabled: false,
      userInitiated: true,
    );

    expect(transport.optIns[0].enabled, isTrue);
    expect(transport.optIns[0].location, isNotNull);
    expect(transport.optIns[1].enabled, isFalse);
    expect(transport.optIns[1].location, isNull);
  });

  test('opt-in throws when the user did not act', () async {
    final service = NearbyEmergencyService(
      platform: _FakePlatform(),
      transport: _FakeTransport(),
    );
    expect(
      () => service.setHelperOptIn(
        mode: sw.DataMode.live,
        helperId: senderId,
        enabled: true,
        userInitiated: false,
      ),
      throwsA(isA<NearbyAlertException>()),
    );
  });
}

class _MemoryStore implements HelperIdStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String id) async => value = id;
}
