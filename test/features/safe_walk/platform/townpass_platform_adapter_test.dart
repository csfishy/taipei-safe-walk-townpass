import 'dart:async';

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
  double accuracy = 12,
  DateTime? timestamp,
}) => geo.Position(
  longitude: 121.5654,
  latitude: 25.0330,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  accuracy: accuracyKnown ? accuracy : 0,
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
  test(
    'coarse native GPS is unavailable rather than a walking origin',
    () async {
      final adapter = TownPassPlatformAdapter(
        readPosition: () async => _native(accuracy: 500),
      );
      final result = await adapter.getCurrentPosition(
        mode: sw.DataMode.live,
        userInitiated: true,
      );
      expect(result.toJson()['status'], 'unavailable');
      expect(result.toJson()['message'], contains('精度'));
    },
  );
  test(
    'official permission errors remain denied without raw native details',
    () async {
      for (final error in ['使用者未允許定位權限', '使用者未允許定位權限（永久），無法取得定位資訊']) {
        final adapter = TownPassPlatformAdapter(
          readPosition: () => Future<geo.Position>.error(error),
        );
        final result = await adapter.getCurrentPosition(
          mode: sw.DataMode.live,
          userInitiated: true,
        );
        expect(result.toJson()['status'], 'denied');
      }
    },
  );
  test('mock mode is unavailable and never reads GPS', () async {
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
    expect(result, isA<sw.LocationFailure>());
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
  group('emergency handoff (the phone dialer only)', () {
    // A fake launcher: nothing is ever dialled, sent or opened for real.
    late List<Uri> launched;
    late bool accepts;
    Object? launchError;

    TownPassPlatformAdapter adapter() => TownPassPlatformAdapter(
      launchUri: (uri) async {
        launched.add(uri);
        if (launchError != null) throw launchError!;
        return accepts;
      },
    );

    Future<sw.EmergencyActionResult> ask(
      TownPassPlatformAdapter a, {
      sw.DataMode mode = sw.DataMode.live,
      sw.EmergencyChannel channel = sw.EmergencyChannel.police,
      bool userInitiated = true,
      bool allowRealCalls = true,
    }) => a.requestEmergency(
      mode: mode,
      channel: channel,
      userInitiated: userInitiated,
      allowRealCalls: allowRealCalls,
    );

    setUp(() {
      launched = [];
      accepts = true;
      launchError = null;
    });

    test(
      'Live, user tap, dialer on: opens the dialer for 110 and 119',
      () async {
        final police = await ask(adapter());
        expect(launched.last.toString(), 'tel:110');
        expect(police.toJson()['action'], 'dial_link_activated');
        expect(police.toJson()['channel'], '110');
        expect(police.toJson()['officialReceipt'], isNull);

        final fire = await ask(adapter(), channel: sw.EmergencyChannel.fire);
        expect(launched.last.toString(), 'tel:119');
        expect(fire.toJson()['action'], 'dial_link_activated');
        expect(fire.toJson()['channel'], '119');
        expect(launched, hasLength(2));
      },
    );

    test('the message never claims a connected call or acceptance', () async {
      final result = await ask(adapter());
      final message = result.toJson()['message'] as String;
      expect(message, contains('撥號畫面'));
      expect(message, contains('不代表電話已接通或已受理'));
      for (final claim in ['已報警', '已通報', '已派遣', '警方已']) {
        expect(message, isNot(contains(claim)), reason: claim);
      }
    });

    test('nothing opens without the person: no tap means cancelled', () async {
      final result = await ask(adapter(), userInitiated: false);
      expect(result.toJson()['action'], 'cancelled');
      expect(launched, isEmpty);
    });

    test('demo mode never reaches the phone', () async {
      for (final channel in sw.EmergencyChannel.values) {
        final result = await ask(
          adapter(),
          mode: sw.DataMode.mock,
          channel: channel,
        );
        expect(result.toJson()['action'], 'not_configured');
        expect(result.toJson()['officialReceipt'], isNull);
      }
      expect(launched, isEmpty);
    });

    test('with the dialer switched off, Live still opens nothing', () async {
      final result = await ask(adapter(), allowRealCalls: false);
      expect(result.toJson()['action'], 'not_configured');
      expect(result.toJson()['message'], contains('真實撥號未啟用'));
      expect(launched, isEmpty);
    });

    test('a trusted contact has no number here, so nothing opens', () async {
      final result = await ask(
        adapter(),
        channel: sw.EmergencyChannel.trustedContact,
      );
      expect(result.toJson()['action'], 'not_configured');
      expect(result.toJson()['channel'], 'trusted_contact');
      expect(launched, isEmpty);
    });

    test(
      'a phone that cannot open a dialer reports failure honestly',
      () async {
        accepts = false;
        final result = await ask(adapter());
        expect(result.toJson()['action'], 'failed');
        final message = result.toJson()['message'] as String;
        expect(message, contains('沒有撥號、沒有通報'));
        expect(message, contains('110'));
        expect(result.toJson()['officialReceipt'], isNull);
      },
    );

    test(
      'a launcher error is contained and its details are not shown',
      () async {
        launchError = StateError('SECRET-DETAIL');
        final result = await ask(adapter(), channel: sw.EmergencyChannel.fire);
        expect(result.toJson()['action'], 'failed');
        final message = result.toJson()['message'] as String;
        expect(message, isNot(contains('SECRET-DETAIL')));
        expect(message, contains('119'));
      },
    );

    test('every result is a valid contract payload with no receipt', () async {
      for (final mode in sw.DataMode.values) {
        for (final channel in sw.EmergencyChannel.values) {
          for (final tap in [true, false]) {
            final result = await ask(
              adapter(),
              mode: mode,
              channel: channel,
              userInitiated: tap,
            );
            // fromJson validates against the shared schema; re-read it too.
            final again = sw.EmergencyActionResult.fromJson(result.toJson());
            expect(again.toJson()['officialReceipt'], isNull);
          }
        }
      }
    });
  });
}
