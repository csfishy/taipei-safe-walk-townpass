import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Synthetic coordinates/contact only; none of these tests uses device or HTTP IO.
final _time = DateTime.utc(2026, 11, 7, 12, 30);

sw.LocationResult _fix({
  double lat = 25.03,
  double lng = 121.56,
  double? accuracy = 8,
  String? observedAt = '2026-11-07T12:30:00.000Z',
  sw.PositionSource source = sw.PositionSource.gps,
}) => sw.LocationSuccess(
  position: sw.Position(
    coordinates: sw.Coordinates(lat: lat, lng: lng),
    source: source,
    accuracyMeters: accuracy,
    observedAt: observedAt,
  ),
);

class _Token implements SafeWalkCancellation {
  final _done = Completer<void>();
  @override
  bool get isCancelled => _done.isCompleted;
  @override
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!isCancelled) _done.complete();
  }
}

class _Platform implements PlatformService {
  int calls = 0;
  Future<sw.LocationResult> Function()? handler;
  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    calls++;
    return handler?.call() ?? Future.value(_fix());
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
  int calls = 0;
  Future<int> Function()? handler;
  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) {
    calls++;
    return handler?.call() ?? Future.value(2);
  }

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) => throw UnimplementedError();
  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) =>
      throw UnimplementedError();
}

class _Unavailable extends _Transport implements UnavailableNearbyAlertBackend {
  @override
  String get unavailableReason => 'Unverified backend';
}

class _Sms implements SmsSender {
  int calls = 0;
  Future<bool> Function()? handler;
  @override
  Future<bool> send({required String number, required String body}) {
    calls++;
    return handler?.call() ?? Future.value(true);
  }
}

class _Contacts implements EmergencyContactStore {
  int calls = 0;
  Future<String?> Function()? handler;
  @override
  Future<String?> read() {
    calls++;
    return handler?.call() ?? Future.value('0912345678');
  }

  @override
  Future<void> write(String phone) => throw UnimplementedError();
}

class _Harness {
  _Harness({_Transport? transport}) : transport = transport ?? _Transport();
  final platform = _Platform();
  final _Transport transport;
  final sms = _Sms();
  final contacts = _Contacts();
  final token = _Token();
  var locationConsent = true;
  var nearbyConsent = true;
  var smsConsent = true;
  var now = _time;
  late final dispatch = EmergencyDispatch(
    platform: platform,
    transport: transport,
    sms: sms,
    contacts: contacts,
    clock: () => now,
  );

  Future<EmergencyDispatchResult> run() => dispatch.sos(
    mode: sw.DataMode.live,
    senderId: 'synthetic-sender',
    cancellation: token,
    hasLocationConsent: () => locationConsent,
    hasNearbyConsent: () => nearbyConsent,
    hasSmsConsent: () => smsConsent,
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('missing consent fails closed before GPS or contact access', () async {
    final h = _Harness();
    final result = await h.dispatch.sos(
      mode: sw.DataMode.live,
      senderId: 'synthetic-sender',
    );
    expect(h.platform.calls, 0);
    expect(h.contacts.calls, 0);
    expect(h.transport.calls, 0);
    expect(h.sms.calls, 0);
    expect(result.located, isFalse);
  });

  test('location permission alone does not authorize sharing', () async {
    final h = _Harness()
      ..nearbyConsent = false
      ..smsConsent = false;
    await h.run();
    expect(h.platform.calls, 0);
    expect(h.transport.calls, 0);
    expect(h.sms.calls, 0);
  });

  test(
    'blocked nearby backend avoids GPS and cannot block consented SMS',
    () async {
      final h = _Harness(transport: _Unavailable())..smsConsent = false;
      final blocked = await h.run();
      expect(h.platform.calls, 0);
      expect(blocked.nearbyRequested, isFalse);
      h.smsConsent = true;
      final result = await h.run();
      expect(h.platform.calls, 1);
      expect(h.transport.calls, 0);
      expect(h.sms.calls, 1);
      expect(result.smsSubmitted, isTrue);
      expect(result.message, contains('安全後端尚未完成驗證'));
      expect(result.message, contains('尚未確認發送或送達'));
    },
  );

  test('already cancelled operation never reads GPS', () async {
    final h = _Harness()..token.cancel();
    final result = await h.run();
    expect(h.platform.calls, 0);
    expect(result.cancelled, isTrue);
  });

  for (final lateError in [false, true]) {
    test(
      'cancels pending GPS and ignores late ${lateError ? 'error' : 'fix'}',
      () async {
        final h = _Harness();
        final pending = Completer<sw.LocationResult>();
        h.platform.handler = () => pending.future;
        final operation = h.run();
        h.token.cancel();
        final result = await operation;
        expect(result.cancelled, isTrue);
        if (lateError) {
          pending.completeError(StateError('private GPS 25.03,121.56'));
        } else {
          pending.complete(_fix());
        }
        await _settle();
        expect(h.transport.calls, 0);
        expect(h.contacts.calls, 0);
        expect(h.sms.calls, 0);
      },
    );
  }

  test('GPS completion rechecks location and destination consents', () async {
    for (final revokeLocation in [true, false]) {
      final h = _Harness();
      final pending = Completer<sw.LocationResult>();
      h.platform.handler = () => pending.future;
      final operation = h.run();
      if (revokeLocation) {
        h.locationConsent = false;
      } else {
        h.nearbyConsent = false;
        h.smsConsent = false;
      }
      pending.complete(_fix());
      await operation;
      expect(h.transport.calls, 0);
      expect(h.sms.calls, 0);
    }
  });

  test(
    'new consent during an operation does not add a new destination',
    () async {
      final h = _Harness()..smsConsent = false;
      final pending = Completer<sw.LocationResult>();
      h.platform.handler = () => pending.future;
      final operation = h.run();
      h.smsConsent = true;
      pending.complete(_fix());
      await operation;
      expect(h.transport.calls, 1);
      expect(h.sms.calls, 0);
    },
  );

  test(
    'cancelled pending nearby request reports uncertainty and never sends SMS',
    () async {
      final h = _Harness();
      final pending = Completer<int>();
      h.transport.handler = () => pending.future;
      final operation = h.run();
      await _settle();
      expect(h.transport.calls, 1);
      h.token.cancel();
      final result = await operation;
      expect(result.cancelled, isTrue);
      expect(result.nearbyRequested, isTrue);
      expect(result.nearbyRecipients, isNull);
      expect(result.message, contains('已提出的請求無法撤回'));
      expect(result.message, isNot(contains('未傳送任何訊息')));
      pending.completeError(StateError('private RPC 25.03,121.56'));
      await _settle();
      expect(h.contacts.calls, 0);
      expect(h.sms.calls, 0);
    },
  );

  test(
    'location revocation after nearby completes prevents contact and SMS',
    () async {
      final h = _Harness();
      final pending = Completer<int>();
      h.transport.handler = () => pending.future;
      final operation = h.run();
      await _settle();
      h.locationConsent = false;
      pending.complete(2);
      final result = await operation;
      expect(result.nearbyRecipients, 2);
      expect(h.contacts.calls, 0);
      expect(h.sms.calls, 0);
    },
  );

  test('contact cancellation preserves completed nearby result and ignores late contact', () async {
    final h = _Harness();
    final pending = Completer<String?>();
    h.contacts.handler = () => pending.future;
    final operation = h.run();
    await _settle();
    expect(h.contacts.calls, 1);
    h.token.cancel();
    final result = await operation;
    expect(result.nearbyRecipients, 2);
    expect(result.cancelled, isTrue);
    expect(result.smsRequested, isFalse);
    expect(result.message, contains('後端回報 2 位接收者'));
    pending.complete('0912345678');
    await _settle();
    expect(h.sms.calls, 0);
  });

  test('contact completion rechecks SMS consent', () async {
    final h = _Harness();
    final pending = Completer<String?>();
    h.contacts.handler = () => pending.future;
    final operation = h.run();
    await _settle();
    h.smsConsent = false;
    pending.complete('0912345678');
    final result = await operation;
    expect(result.nearbyRecipients, 2);
    expect(h.sms.calls, 0);
  });

  test(
    'stale fix after a delayed nearby request cannot be shared via SMS',
    () async {
      final h = _Harness();
      final pending = Completer<int>();
      h.transport.handler = () => pending.future;
      final operation = h.run();
      await _settle();
      h.now = _time.add(const Duration(seconds: 61));
      pending.complete(2);
      final result = await operation;
      expect(result.nearbyRecipients, 2);
      expect(h.sms.calls, 0);
      expect(result.message, contains('位置已過期'));
    },
  );

  test('cancellation during SMS preserves attempted status without claiming delivery', () async {
    final h = _Harness();
    final pending = Completer<bool>();
    h.sms.handler = () => pending.future;
    final operation = h.run();
    await _settle();
    expect(h.sms.calls, 1);
    h.token.cancel();
    final result = await operation;
    expect(result.smsRequested, isTrue);
    expect(result.smsSubmitted, isFalse);
    expect(result.nearbyRecipients, 2);
    expect(result.message, contains('尚未確認發送或送達'));
    pending.complete(true);
    await _settle();
    expect(h.sms.calls, 1);
  });

  test(
    'unknown failures are redacted and independent destinations still work',
    () async {
      const privateError =
          'private location 25.03,121.56 and contact 0912345678';
      final h = _Harness();
      h.transport.handler = () => Future.error(StateError(privateError));
      final result = await h.run();
      expect(result.nearbyRequested, isTrue);
      expect(result.smsSubmitted, isTrue);
      expect(result.message, isNot(contains(privateError)));
      h.contacts.handler = () => Future.error(StateError(privateError));
      final contactFailure = await h.run();
      expect(contactFailure.message, isNot(contains(privateError)));
      expect(contactFailure.message, contains('無法讀取緊急聯絡人'));
      expect(h.sms.calls, 1);
    },
  );

  test('raw location provider errors never reach the screen', () async {
    final h = _Harness();
    h.platform.handler = () async => sw.LocationFailure(
      status: sw.LocationFailureStatus.unavailable,
      message: 'secret URL with lat=25.03 and lng=121.56',
    );
    final result = await h.run();
    expect(result.message, isNot(contains('25.03')));
    expect(h.transport.calls, 0);
    expect(h.sms.calls, 0);
  });

  test('a rejected or failed SMS request never claims it was sent', () async {
    for (final throws in [false, true]) {
      final h = _Harness();
      h.sms.handler = () => throws
          ? Future.error(StateError('private body 25.03,121.56'))
          : Future.value(false);
      final result = await h.run();
      expect(result.nearbyRecipients, 2);
      expect(result.smsRequested, isTrue);
      expect(result.smsSubmitted, isFalse);
      expect(result.message, isNot(contains('25.03')));
      expect(result.message, isNot(contains('已送簡訊')));
      expect(result.message, contains(throws ? '結果未確認' : '系統未接受'));
    }
  });

  testWidgets(
    'pending nearby timeout preserves uncertainty and allows consented SMS',
    (tester) async {
      final h = _Harness();
      final pending = Completer<int>();
      h.transport.handler = () => pending.future;
      final operation = h.run();
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      final result = await operation;
      expect(result.nearbyRequested, isTrue);
      expect(result.nearbyRecipients, isNull);
      expect(result.smsSubmitted, isTrue);
      expect(result.message, contains('附近通知請求結果未確認'));
      pending.completeError(StateError('late private RPC response'));
      await tester.pump();
    },
  );

  // Malformed values can be rejected by model validation while the provider is
  // constructing its result; dispatch must also contain that error safely.
  final invalidFixes = <String, sw.LocationResult Function()>{
    'missing accuracy': () => _fix(accuracy: null),
    'negative accuracy': () => _fix(accuracy: -1),
    'poor accuracy': () => _fix(accuracy: 101),
    'infinite accuracy': () => _fix(accuracy: double.infinity),
    'NaN accuracy': () => _fix(accuracy: double.nan),
    'NaN coordinate': () => _fix(lat: double.nan),
    'infinite coordinate': () => _fix(lng: double.infinity),
    'latitude out of range': () => _fix(lat: 91),
    'longitude out of range': () => _fix(lng: -181),
    'missing observation time': () => _fix(observedAt: null),
    'invalid observation time': () => _fix(observedAt: 'not-a-time'),
    'stale fix': () => _fix(observedAt: '2026-11-07T12:28:59Z'),
    'future fix': () => _fix(observedAt: '2026-11-07T12:30:31Z'),
    'manual location': () => _fix(source: sw.PositionSource.manual),
    'mock location': () => _fix(source: sw.PositionSource.mock),
  };
  for (final entry in invalidFixes.entries) {
    test('rejects ${entry.key} before sharing', () async {
      final h = _Harness();
      h.platform.handler = () async => entry.value();
      final result = await h.run();
      expect(result.located, isFalse);
      expect(h.transport.calls, 0);
      expect(h.sms.calls, 0);
    });
  }
}
