import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_watcher.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

class _NoLocationPlatform extends Fake implements PlatformService {}

class _Transport implements NearbyAlertTransport {
  _Transport(this.fetch);
  final Future<List<NearbyAlert>> Function() fetch;
  int fetchCalls = 0;

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) {
    fetchCalls++;
    return fetch();
  }

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) => throw UnimplementedError();

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) => throw UnimplementedError();
}

NearbyAlert _alert(String id) => NearbyAlert(
  alertId: id,
  senderId: 'synthetic-sender',
  location: sw.Coordinates(lat: 0.123456, lng: -0.654321),
  radiusMeters: 500,
  createdAt: DateTime.utc(2026, 11, 7),
);

NearbyAlertWatcher _watcher(
  _Transport transport, {
  Duration interval = const Duration(hours: 1),
}) => NearbyAlertWatcher(
  service: NearbyEmergencyService(
    platform: _NoLocationPlatform(),
    transport: transport,
  ),
  helperId: 'synthetic-helper',
  interval: interval,
);

void main() {
  test('stop suppresses a pending result and further manual polling', () async {
    final pending = Completer<List<NearbyAlert>>();
    final transport = _Transport(() => pending.future);
    final watcher = _watcher(transport);
    final received = <NearbyAlert>[];
    final subscription = watcher.alerts.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      watcher.dispose();
    });

    final poll = watcher.poll();
    watcher.stop();
    pending.complete([_alert('late')]);
    await poll;
    await Future<void>.delayed(Duration.zero);
    await watcher.poll();

    expect(received, isEmpty);
    expect(transport.fetchCalls, 1);
  });

  test('dispose suppresses a pending result and cannot be restarted', () async {
    final pending = Completer<List<NearbyAlert>>();
    final transport = _Transport(() => pending.future);
    final watcher = _watcher(transport);
    final received = <NearbyAlert>[];
    final subscription = watcher.alerts.listen(received.add);
    addTearDown(subscription.cancel);

    final poll = watcher.poll();
    watcher.dispose();
    watcher.start();
    pending.complete([_alert('late')]);
    await poll;
    await Future<void>.delayed(Duration.zero);
    await watcher.poll();

    expect(received, isEmpty);
    expect(transport.fetchCalls, 1);
  });

  test('restart ignores the old poll without blocking the new one', () async {
    final oldPending = Completer<List<NearbyAlert>>();
    final newPending = Completer<List<NearbyAlert>>();
    var calls = 0;
    final transport = _Transport(
      () => calls++ == 0 ? oldPending.future : newPending.future,
    );
    final watcher = _watcher(transport);
    final received = <NearbyAlert>[];
    final subscription = watcher.alerts.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      watcher.dispose();
    });

    final oldPoll = watcher.poll();
    watcher.stop();
    watcher.start();
    final newPoll = watcher.poll();
    newPending.complete([_alert('new')]);
    await newPoll;
    oldPending.complete([_alert('old')]);
    await oldPoll;
    await Future<void>.delayed(Duration.zero);

    expect(received.map((alert) => alert.alertId), ['new']);
    expect(transport.fetchCalls, 2);
  });

  test(
    'errors do not stop a later manual poll and duplicate alerts emit once',
    () async {
      var calls = 0;
      final transport = _Transport(() async {
        if (calls++ == 0) throw const NearbyAlertException('synthetic failure');
        return [_alert('same')];
      });
      final watcher = _watcher(transport);
      final received = <NearbyAlert>[];
      final subscription = watcher.alerts.listen(received.add);
      addTearDown(() async {
        await subscription.cancel();
        watcher.dispose();
      });

      await watcher.poll();
      await watcher.poll();
      await watcher.poll();
      await Future<void>.delayed(Duration.zero);

      expect(received.map((alert) => alert.alertId), ['same']);
      expect(transport.fetchCalls, 3);
    },
  );

  testWidgets('automatic polling only runs between start and stop', (
    tester,
  ) async {
    final transport = _Transport(() async => []);
    final watcher = _watcher(
      transport,
      interval: const Duration(milliseconds: 10),
    );
    addTearDown(watcher.dispose);

    await tester.pump(const Duration(milliseconds: 30));
    expect(transport.fetchCalls, 0);
    watcher.start();
    watcher.start();
    await tester.pump(const Duration(milliseconds: 10));
    expect(transport.fetchCalls, 1);
    watcher.stop();
    await tester.pump(const Duration(milliseconds: 30));
    expect(transport.fetchCalls, 1);
  });

  test(
    'popup uses coordinate text and an explicit UTC timestamp without a URL',
    () {
      final text = nearbyAlertPopupText(_alert('format'));
      expect(text, contains('0.123456, -0.654321'));
      expect(text, contains('2026-11-07T00:00:00.000Z（UTC）'));
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('已通知')));
    },
  );
}
