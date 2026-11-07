// Helper side of "notify people nearby", delivered inside the app: joining,
// foreground polling and refreshing, de-duplicated alerts, pause in the
// background, leaving, and disposal. Fakes only: no network, no real location.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/integration/nearby_helper_controller.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final _here = sw.Coordinates(lat: 25.033, lng: 121.5654);
const _fast = Duration(milliseconds: 25);

class _Platform implements PlatformService {
  int calls = 0;
  Completer<sw.LocationResult>? pending;
  sw.LocationResult? result;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    expect(mode, sw.DataMode.live);
    expect(userInitiated, isTrue);
    calls++;
    if (pending != null) return pending!.future;
    return Future.value(
      result ??
          sw.LocationSuccess(
            position: sw.Position(
              coordinates: _here,
              source: sw.PositionSource.gps,
              accuracyMeters: 10,
              observedAt: '2026-11-08T00:00:00Z',
            ),
          ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements NearbyAlertTransport, NearbyAlertAvailability {
  String? reason;
  final optIns = <bool>[];
  int fetches = 0;
  List<NearbyAlert> alerts = [];
  Object? optInError;

  @override
  String? get currentUnavailableReason => reason;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    if (optInError != null) throw optInError!;
    optIns.add(enabled);
  }

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async => 0;

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    fetches++;
    return alerts;
  }
}

NearbyAlert _alert(String id) => NearbyAlert(
  alertId: id,
  location: sw.Coordinates(lat: 25.034, lng: 121.566),
  radiusMeters: 500,
  createdAt: DateTime.utc(2026, 11, 8, 1, 2, 3),
);

Future<void> _until(bool Function() ok, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!ok()) {
    if (DateTime.now().isAfter(deadline)) fail(reason ?? 'condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _quiet() => Future<void>.delayed(_fast * 6);

void main() {
  late _Platform platform;
  late _Transport transport;
  late NearbyHelperController helper;
  var arrivals = 0;

  setUp(() {
    platform = _Platform();
    transport = _Transport();
    arrivals = 0;
    helper = NearbyHelperController(
      service: NearbyEmergencyService(platform: platform, transport: transport),
      pollInterval: _fast,
      refreshInterval: const Duration(milliseconds: 80),
      onAlertArrived: () => arrivals++,
    );
  });
  tearDown(() => helper.dispose());

  test('unavailable backend: says why, reads no location, is not on', () async {
    transport.reason = '測試：尚未登入';
    expect(helper.unavailableReason, '測試：尚未登入');
    await helper.enable();
    expect(helper.isOn, isFalse);
    expect(helper.message, '測試：尚未登入');
    expect(helper.messageIsError, isTrue);
    expect(platform.calls, 0);
    expect(transport.optIns, isEmpty);
    await _quiet();
    expect(transport.fetches, 0);
  });

  test('joining reads the position once, opts in and starts polling', () async {
    await helper.enable();
    expect(helper.isOn, isTrue);
    expect(helper.isBusy, isFalse);
    expect(helper.messageIsError, isFalse);
    expect(platform.calls, 1);
    expect(transport.optIns, [true]);
    await _until(() => transport.fetches >= 2, reason: 'polling started');
  });

  test('a failed location read means not joined and nothing is sent', () async {
    platform.result = sw.LocationFailure(
      status: sw.LocationFailureStatus.denied,
      message: '測試：定位權限未允許',
    );
    await helper.enable();
    expect(helper.isOn, isFalse);
    expect(helper.message, contains('定位權限未允許'));
    expect(helper.messageIsError, isTrue);
    expect(transport.optIns, isEmpty);
    await _quiet();
    expect(transport.fetches, 0);
  });

  test('an alert is shown once even if the backend repeats it', () async {
    transport.alerts = [_alert('a1')];
    await helper.enable();
    await _until(() => helper.incoming.isNotEmpty);
    await _until(() => transport.fetches >= 4);
    expect(helper.incoming.map((a) => a.alertId), ['a1']);
    expect(helper.incoming.single.location.lat, 25.034);
    expect(arrivals, 1);
    helper.dismiss('a1');
    expect(helper.incoming, isEmpty);
    // The backend keeps returning it until it expires; it must not come back.
    await _quiet();
    expect(helper.incoming, isEmpty);
    expect(arrivals, 1);
    transport.alerts = [_alert('a1'), _alert('a2')];
    await _until(() => helper.incoming.length == 1);
    expect(helper.incoming.single.alertId, 'a2');
    expect(arrivals, 2);
  });

  test('stopping opts out, deletes the position and stops polling', () async {
    await helper.enable();
    await helper.disable();
    expect(helper.isOn, isFalse);
    expect(transport.optIns, [true, false]);
    expect(helper.message, contains('位置已刪除'));
    expect(helper.messageIsError, isFalse);
    final fetches = transport.fetches;
    await _quiet();
    expect(transport.fetches, fetches);
    expect(transport.optIns, [true, false]);
  });

  test('stopping when deletion cannot be confirmed says so honestly', () async {
    await helper.enable();
    transport.optInError = const NearbyAlertException('x');
    await helper.disable();
    expect(helper.isOn, isFalse);
    expect(helper.messageIsError, isTrue);
    expect(helper.message, contains('沒有確認伺服器已刪除'));
    expect(helper.message, contains('10 分鐘'));
  });

  test('the position is refreshed while joined', () async {
    await helper.enable();
    await _until(() => transport.optIns.length >= 3, reason: 'refreshes ran');
    expect(transport.optIns.every((e) => e), isTrue);
    expect(platform.calls, greaterThanOrEqualTo(3));
  });

  test('background pauses polling and refreshing; resume refreshes', () async {
    await helper.enable();
    await _until(() => transport.fetches >= 1);
    helper.setForeground(false);
    final fetches = transport.fetches;
    final shares = platform.calls;
    await _quiet();
    expect(transport.fetches, fetches);
    expect(platform.calls, shares);
    expect(helper.isOn, isTrue);

    helper.setForeground(true);
    await _until(() => platform.calls > shares, reason: 'refreshed on resume');
    await _until(() => transport.fetches > fetches, reason: 'polling resumed');
  });

  test('alerts that arrive while paused are not surfaced', () async {
    await helper.enable();
    helper.setForeground(false);
    transport.alerts = [_alert('late')];
    await _quiet();
    expect(helper.incoming, isEmpty);
    expect(arrivals, 0);
  });

  test(
    'a failed refresh keeps joined but warns that reach may be lost',
    () async {
      await helper.enable();
      transport.optInError = const NearbyAlertException('操作太頻繁');
      await _until(
        () => helper.messageIsError,
        reason: 'refresh failure shown',
      );
      expect(helper.isOn, isTrue);
      expect(helper.message, contains('位置更新失敗'));
      expect(helper.message, contains('操作太頻繁'));
      transport.optInError = null;
      await _until(() => !helper.messageIsError, reason: 'cleared on recovery');
    },
  );

  test('losing the session stops helping instead of half-working', () async {
    await helper.enable();
    transport.reason = '測試：已登出';
    await _until(() => !helper.isOn, reason: 'stopped after sign-out');
    expect(helper.message, contains('已登出'));
    expect(helper.messageIsError, isTrue);
    final fetches = transport.fetches;
    await _quiet();
    expect(transport.fetches, fetches);
  });

  test(
    'disposing mid-join cancels it: nothing is sent, nothing starts',
    () async {
      platform.pending = Completer<sw.LocationResult>();
      final joining = helper.enable();
      await _until(() => platform.calls == 1);
      expect(helper.isBusy, isTrue);
      helper.dispose();
      platform.pending!.complete(
        sw.LocationSuccess(
          position: sw.Position(
            coordinates: _here,
            source: sw.PositionSource.gps,
            accuracyMeters: 10,
            observedAt: '2026-11-08T00:00:00Z',
          ),
        ),
      );
      await joining;
      await _quiet();
      expect(transport.optIns, isEmpty);
      expect(transport.fetches, 0);
    },
  );

  test('disposing stops polling and refreshing', () async {
    await helper.enable();
    await _until(() => transport.fetches >= 1);
    helper.dispose();
    final fetches = transport.fetches;
    final shares = platform.calls;
    await _quiet();
    expect(transport.fetches, fetches);
    expect(platform.calls, shares);
  });

  test('a second join while joining or joined is ignored', () async {
    platform.pending = Completer<sw.LocationResult>();
    final first = helper.enable();
    await _until(() => platform.calls == 1);
    await helper.enable();
    expect(platform.calls, 1);
    platform.pending!.complete(
      sw.LocationSuccess(
        position: sw.Position(
          coordinates: _here,
          source: sw.PositionSource.gps,
          accuracyMeters: 10,
          observedAt: '2026-11-08T00:00:00Z',
        ),
      ),
    );
    await first;
    platform.pending = null;
    final shares = platform.calls;
    await helper.enable();
    expect(platform.calls, shares);
    expect(transport.optIns.where((e) => e).length, 1);
  });
}
