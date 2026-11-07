import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';
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

geo.Position _native({
  bool accuracyKnown = true,
  bool mocked = false,
  DateTime? timestamp,
}) => geo.Position(
  longitude: 121.5654,
  latitude: 25.0330,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  accuracy: accuracyKnown ? 12 : 0,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  hasAccuracy: accuracyKnown,
  isMocked: mocked,
);

void main() {
  sw.Position mockPosition() => sw.Position.fromJson(
    jsonDecode(
      File('test/fixtures/safe_walk/valid/01-Position.json').readAsStringSync(),
    ),
  );
  test('no user action means no native location call in either mode', () async {
    var nativeCalls = 0;
    final adapter = TownPassPlatformAdapter(
      readPosition: () async {
        nativeCalls++;
        return _native();
      },
    );
    for (final mode in sw.DataMode.values) {
      final result = await adapter.getCurrentPosition(
        mode: mode,
        userInitiated: false,
      );
      expect(result.toJson()['status'], 'denied');
    }
    expect(nativeCalls, 0);
  });
  test('mock mode only uses injected mock data and never reads GPS', () async {
    var nativeCalls = 0;
    final adapter = TownPassPlatformAdapter(
      mockPosition: mockPosition(),
      readPosition: () async {
        nativeCalls++;
        return _native();
      },
    );
    final result = await adapter.getCurrentPosition(
      mode: sw.DataMode.mock,
      userInitiated: true,
    );
    expect(result, isA<sw.LocationSuccess>());
    expect((result.toJson()['position'] as Map)['source'], 'mock');
    expect(nativeCalls, 0);
  });
  test('missing mock position never falls back to GPS', () async {
    var nativeCalls = 0;
    final adapter = TownPassPlatformAdapter(
      readPosition: () async {
        nativeCalls++;
        return _native();
      },
    );
    final result = await adapter.getCurrentPosition(
      mode: sw.DataMode.mock,
      userInitiated: true,
    );
    expect(result.toJson()['status'], 'unavailable');
    expect(nativeCalls, 0);
  });
  test(
    'live host data is converted to the shared schema with measured accuracy',
    () async {
      final adapter = TownPassPlatformAdapter(
        readPosition: () async => _native(),
      );
      final result = await adapter.getCurrentPosition(
        mode: sw.DataMode.live,
        userInitiated: true,
      );
      final payload = result.toJson()['position'] as Map;
      expect(payload['source'], 'gps');
      expect(payload['accuracyMeters'], 12);
      expect(payload['observedAt'], endsWith('Z'));
    },
  );
  test('unmeasured zero accuracy is not treated as precise GPS', () async {
    final adapter = TownPassPlatformAdapter(
      readPosition: () async => _native(accuracyKnown: false),
    );
    final result = await adapter.getCurrentPosition(
      mode: sw.DataMode.live,
      userInitiated: true,
    );
    expect(result.toJson()['status'], 'unavailable');
  });
  test(
    'stale native GPS is unavailable rather than a successful origin',
    () async {
      final adapter = TownPassPlatformAdapter(
        readPosition: () async => _native(
          timestamp: DateTime.now().toUtc().subtract(
            const Duration(minutes: 10),
          ),
        ),
      );
      final result = await adapter.getCurrentPosition(
        mode: sw.DataMode.live,
        userInitiated: true,
      );
      expect(result, isA<sw.LocationFailure>());
      expect(
        (result as sw.LocationFailure).status,
        sw.LocationFailureStatus.unavailable,
      );
      expect(result.message, contains('定位時間'));
    },
  );
  test(
    'future native GPS is unavailable rather than a successful origin',
    () async {
      final adapter = TownPassPlatformAdapter(
        readPosition: () async => _native(
          timestamp: DateTime.now().toUtc().add(const Duration(minutes: 10)),
        ),
      );
      final result = await adapter.getCurrentPosition(
        mode: sw.DataMode.live,
        userInitiated: true,
      );
      expect(result, isA<sw.LocationFailure>());
      expect(
        (result as sw.LocationFailure).status,
        sw.LocationFailureStatus.unavailable,
      );
      expect(result.message, contains('定位時間'));
    },
  );
  test('host-simulated position is not relabelled as live GPS', () async {
    final adapter = TownPassPlatformAdapter(
      readPosition: () async => _native(mocked: true),
    );
    final result = await adapter.getCurrentPosition(
      mode: sw.DataMode.live,
      userInitiated: true,
    );
    expect(result.toJson()['status'], 'unavailable');
  });
  test('unstructured upstream errors become explicit unavailability', () async {
    final adapter = TownPassPlatformAdapter(
      readPosition: () async => throw StateError('host details'),
    );
    final result = await adapter.getCurrentPosition(
      mode: sw.DataMode.live,
      userInitiated: true,
    );
    expect(result.toJson()['status'], 'unavailable');
    expect(result.toJson()['message'], isNot(contains('host details')));
  });
  test('a stalled native future has a bounded caller timeout', () async {
    final native = Completer<geo.Position>();
    final adapter = TownPassPlatformAdapter(
      readPosition: () => native.future,
      locationTimeout: const Duration(milliseconds: 1),
    );
    final result = await adapter.getCurrentPosition(
      mode: sw.DataMode.live,
      userInitiated: true,
    );
    expect(result.toJson()['status'], 'timeout');
    native.complete(_native());
  });
  test('pre-cancelled work never reaches the native reader', () async {
    var nativeCalls = 0;
    final cancel = _Cancellation()..cancel();
    final adapter = TownPassPlatformAdapter(
      readPosition: () async {
        nativeCalls++;
        return _native();
      },
    );
    await expectLater(
      adapter.getCurrentPosition(
        mode: sw.DataMode.live,
        userInitiated: true,
        cancellation: cancel,
      ),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    expect(nativeCalls, 0);
  });
  test('cancellation wins over a late native location response', () async {
    final native = Completer<geo.Position>();
    final cancel = _Cancellation();
    final adapter = TownPassPlatformAdapter(readPosition: () => native.future);
    final result = adapter.getCurrentPosition(
      mode: sw.DataMode.live,
      userInitiated: true,
      cancellation: cancel,
    );
    final assertion = expectLater(
      result,
      throwsA(isA<SafeWalkCancelledException>()),
    );
    cancel.cancel();
    await assertion;
    native.complete(_native());
    await Future<void>.delayed(Duration.zero);
  });
  test(
    'all emergency channels remain local and have no official receipt',
    () async {
      final adapter = TownPassPlatformAdapter();
      for (final mode in sw.DataMode.values) {
        for (final channel in sw.EmergencyChannel.values) {
          final result = await adapter.requestEmergency(
            mode: mode,
            channel: channel,
            userInitiated: true,
            allowRealCalls: true,
          );
          expect(result.toJson()['action'], 'not_configured');
          expect(result.toJson()['officialReceipt'], isNull);
        }
      }
      final cancelled = await adapter.requestEmergency(
        mode: sw.DataMode.live,
        channel: sw.EmergencyChannel.police,
        userInitiated: false,
        allowRealCalls: true,
      );
      expect(cancelled.toJson()['action'], 'cancelled');
    },
  );
}
