import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// All coordinates and identities in this file are artificial fixtures.
const _identity = '11111111-2222-4333-8444-555555555555';
final _location = sw.Coordinates(lat: 25.033, lng: 121.5654);
sw.LocationSuccess _position() => sw.LocationSuccess(
  position: sw.Position(
    coordinates: _location,
    source: sw.PositionSource.gps,
    accuracyMeters: 12,
    observedAt: '2026-11-08T00:00:00Z',
  ),
);

class _Cancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();
  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() => _cancelled.complete();
}

class _Platform implements PlatformService {
  int calls = 0;
  final called = Completer<void>();
  Completer<sw.LocationResult>? pending;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    calls++;
    if (!called.isCompleted) called.complete();
    return pending?.future ?? Future.value(_position());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements NearbyAlertTransport {
  int sends = 0;
  int optIns = 0;
  final sent = Completer<void>();
  final optedIn = Completer<void>();
  Completer<int>? pendingSend;
  Completer<void>? pendingOptIn;

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) {
    sends++;
    if (!sent.isCompleted) sent.complete();
    return pendingSend?.future ?? Future.value(1);
  }

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) {
    optIns++;
    if (!optedIn.isCompleted) optedIn.complete();
    return pendingOptIn?.future ?? Future.value();
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async => [];
}

class _NoNetworkClient implements HttpClient {
  int networkCalls = 0;
  int closes = 0;

  @override
  void close({bool force = false}) => closes++;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    networkCalls++;
    throw StateError('Unavailable nearby backend must not use HttpClient');
  }
}

void main() {
  SupabaseNearbyAlertTransport unavailable({_NoNetworkClient? client}) =>
      SupabaseNearbyAlertTransport(
        baseUrl: Uri.parse('https://artificial-project.supabase.co'),
        anonKey: 'sb_publishable_artificial-security-test-key',
        client: client,
      );

  test(
    'unconfigured production transport rejects every nearby action',
    () async {
      const transport = UnavailableNearbyAlertTransport();
      expect(transport, isA<UnavailableNearbyAlertBackend>());
      final blocked = throwsA(isA<NearbyAlertException>());
      await expectLater(
        transport.setHelperOptIn(
          helperId: _identity,
          enabled: true,
          location: _location,
        ),
        blocked,
      );
      await expectLater(
        transport.sendEmergencyAlert(
          senderId: _identity,
          location: _location,
          radiusMeters: 500,
        ),
        blocked,
      );
      await expectLater(transport.fetchPendingAlerts(_identity), blocked);
    },
  );

  test(
    'configured keys and caller UUID cannot enable any legacy RPC',
    () async {
      final client = _NoNetworkClient();
      final transport = unavailable(client: client);
      addTearDown(transport.close);
      expect(transport, isA<UnavailableNearbyAlertBackend>());
      expect(transport.unavailableReason, isNotEmpty);
      final blocked = throwsA(isA<NearbyAlertException>());

      await expectLater(
        transport.setHelperOptIn(
          helperId: _identity,
          enabled: true,
          location: _location,
        ),
        blocked,
      );
      await expectLater(
        transport.setHelperOptIn(helperId: _identity, enabled: false),
        blocked,
      );
      await expectLater(
        transport.sendEmergencyAlert(
          senderId: _identity,
          location: _location,
          radiusMeters: 500,
        ),
        blocked,
      );
      await expectLater(transport.fetchPendingAlerts(_identity), blocked);
      expect(client.networkCalls, 0);
      transport.close();
      transport.close();
      expect(client.closes, 1);
    },
  );

  test(
    'unavailable nearby action rejects before collecting location',
    () async {
      final platform = _Platform();
      final transport = unavailable();
      addTearDown(transport.close);
      final service = NearbyEmergencyService(
        platform: platform,
        transport: transport,
      );
      final result = await service.triggerEmergency(
        mode: sw.DataMode.live,
        senderId: _identity,
        userInitiated: true,
      );
      expect(
        (result as NearbyEmergencyNotSent).reason,
        NearbyEmergencyBlock.backendUnavailable,
      );
      await expectLater(
        service.setHelperOptIn(
          mode: sw.DataMode.live,
          helperId: _identity,
          enabled: true,
          userInitiated: true,
        ),
        throwsA(isA<NearbyAlertException>()),
      );
      expect(platform.calls, 0);
    },
  );

  test('pre-cancelled actions never collect or publish location', () async {
    final platform = _Platform();
    final transport = _Transport();
    final cancellation = _Cancellation()..cancel();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
    );
    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: _identity,
      userInitiated: true,
      cancellation: cancellation,
    );
    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.cancelled,
    );
    for (final enabled in [true, false]) {
      await expectLater(
        service.setHelperOptIn(
          mode: sw.DataMode.live,
          helperId: _identity,
          enabled: enabled,
          userInitiated: true,
          cancellation: cancellation,
        ),
        throwsA(isA<SafeWalkCancelledException>()),
      );
    }
    expect(platform.calls, 0);
    expect(transport.sends, 0);
    expect(transport.optIns, 0);
  });

  for (final optIn in [false, true]) {
    test('cancel during GPS prevents ${optIn ? 'opt-in' : 'send'}', () async {
      final gps = Completer<sw.LocationResult>();
      final platform = _Platform()..pending = gps;
      final transport = _Transport();
      final cancellation = _Cancellation();
      final service = NearbyEmergencyService(
        platform: platform,
        transport: transport,
      );
      final Future<Object?> pending;
      if (optIn) {
        pending = service.setHelperOptIn(
          mode: sw.DataMode.live,
          helperId: _identity,
          enabled: true,
          userInitiated: true,
          cancellation: cancellation,
        );
      } else {
        pending = service.triggerEmergency(
          mode: sw.DataMode.live,
          senderId: _identity,
          userInitiated: true,
          cancellation: cancellation,
        );
      }
      await platform.called.future;
      final expectation = optIn
          ? expectLater(pending, throwsA(isA<SafeWalkCancelledException>()))
          : expectLater(
              pending,
              completion(
                isA<NearbyEmergencyNotSent>().having(
                  (result) => result.reason,
                  'reason',
                  NearbyEmergencyBlock.cancelled,
                ),
              ),
            );
      cancellation.cancel();
      await expectation;
      gps.complete(_position());
      await Future<void>.delayed(Duration.zero);
      expect(transport.sends, 0);
      expect(transport.optIns, 0);
    });
  }

  test('cancel after RPC submission suppresses a late success', () async {
    final rpc = Completer<int>();
    final transport = _Transport()..pendingSend = rpc;
    final cancellation = _Cancellation();
    final service = NearbyEmergencyService(
      platform: _Platform(),
      transport: transport,
    );
    final pending = service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: _identity,
      userInitiated: true,
      cancellation: cancellation,
    );
    await transport.sent.future;
    cancellation.cancel();
    final result = await pending;
    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.cancelled,
    );
    rpc.complete(10);
    await Future<void>.delayed(Duration.zero);
    expect(transport.sends, 1);
  });

  test('cancel after opt-in submission cannot report success', () async {
    final rpc = Completer<void>();
    final transport = _Transport()..pendingOptIn = rpc;
    final cancellation = _Cancellation();
    final service = NearbyEmergencyService(
      platform: _Platform(),
      transport: transport,
    );
    final pending = service.setHelperOptIn(
      mode: sw.DataMode.live,
      helperId: _identity,
      enabled: true,
      userInitiated: true,
      cancellation: cancellation,
    );
    final expectation = expectLater(
      pending,
      throwsA(isA<SafeWalkCancelledException>()),
    );
    await transport.optedIn.future;
    cancellation.cancel();
    await expectation;
    rpc.complete();
    await Future<void>.delayed(Duration.zero);
    expect(transport.optIns, 1);
  });
}
