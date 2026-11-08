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
    expectSync(mode, sw.DataMode.live);
    expectSync(userInitiated, isTrue);
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

class _AreasTransport extends _Transport implements NearbyHelperAreas {
  List<NearbyGuardArea> areas = [];
  final replaced = <List<NearbyGuardArea>>[];
  Object? fetchError;
  Object? replaceError;
  int fetchAreaCalls = 0;
  bool roundOnFetch = false;

  @override
  Future<List<NearbyGuardArea>> fetchGuardAreas() async {
    fetchAreaCalls++;
    if (fetchError != null) throw fetchError!;
    if (!roundOnFetch) return areas;
    return [
      for (final a in areas)
        NearbyGuardArea(
          center: sw.Coordinates(
            lat: (a.center.lat * 1000).round() / 1000,
            lng: (a.center.lng * 1000).round() / 1000,
          ),
          radiusMeters: a.radiusMeters,
        ),
    ];
  }

  @override
  Future<void> replaceGuardAreas(List<NearbyGuardArea> next) async {
    if (replaceError != null) throw replaceError!;
    replaced.add(next);
    areas = next;
  }
}

NearbyGuardArea _area(double lat, int radius) => NearbyGuardArea(
  center: sw.Coordinates(lat: lat, lng: 121.566),
  radiusMeters: radius,
);

class _ContactsTransport extends _Transport
    implements NearbyTrustedContacts, NearbyIdentityRestore {
  bool canRestore = true;
  int restores = 0;
  int listCalls = 0;
  List<NearbyContactLink> mine = [];
  List<NearbyFollowing> follows = [];
  NearbyInviteResult acceptResult = NearbyInviteResult.paired;

  /// Added to [follows] when an invite is accepted as paired.
  NearbyFollowing? followOnPair;
  Object? error;
  Completer<void>? gate;
  final created = <String>[];
  final accepted = <String>[];
  final removed = <String>[];
  final unfollowed = <String>[];
  NearbyContactInvite invite = NearbyContactInvite(
    code: 'ABCD2345',
    expiresAt: DateTime.utc(2026, 11, 9, 12),
  );

  Future<void> _wait() async {
    await gate?.future;
    if (error != null) throw error!;
  }

  @override
  Future<bool> restoreExistingIdentity() async {
    restores++;
    return canRestore;
  }

  @override
  Future<NearbyContactInvite> createContactInvite(String displayName) async {
    created.add(displayName);
    await _wait();
    return invite;
  }

  @override
  Future<NearbyInviteResult> acceptContactInvite(String code) async {
    accepted.add(code);
    await _wait();
    if (acceptResult == NearbyInviteResult.paired && followOnPair != null) {
      follows = [...follows, followOnPair!];
    }
    return acceptResult;
  }

  @override
  Future<List<NearbyContactLink>> listMyContacts() async {
    listCalls++;
    return List.of(mine);
  }

  @override
  Future<void> removeContact(String linkId) async {
    removed.add(linkId);
    await _wait();
    mine = [
      for (final c in mine)
        if (c.id != linkId) c,
    ];
  }

  @override
  Future<List<NearbyFollowing>> listFollowing() async => List.of(follows);

  @override
  Future<void> unfollow(String linkId) async {
    unfollowed.add(linkId);
    await _wait();
    follows = [
      for (final f in follows)
        if (f.id != linkId) f,
    ];
  }
}

NearbyContactLink _link(String id) =>
    NearbyContactLink(id: id, since: DateTime.utc(2026, 11, 8));

NearbyFollowing _following(String id, [String name = '小明']) =>
    NearbyFollowing(id: id, name: name, since: DateTime.utc(2026, 11, 8));

NearbyAlert _contactAlert(String id) => NearbyAlert(
  alertId: id,
  location: sw.Coordinates(lat: 25.034, lng: 121.566),
  radiusMeters: 500,
  createdAt: DateTime.utc(2026, 11, 8, 1, 2, 3),
  fromContact: true,
  senderName: '小明',
);

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
    expect(helper.message, contains('連線已中斷'));
    expect(helper.message, isNot(contains('登入')));
    expect(helper.message, isNot(contains('登出')));
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

  group('guard areas', () {
    late _AreasTransport areasTransport;
    late NearbyHelperController areasHelper;

    setUp(() {
      areasTransport = _AreasTransport();
      areasHelper = NearbyHelperController(
        service: NearbyEmergencyService(
          platform: platform,
          transport: areasTransport,
        ),
        pollInterval: _fast,
        refreshInterval: const Duration(minutes: 30),
      );
    });
    tearDown(() => areasHelper.dispose());

    test(
      'unsupported backend: no section, nothing is read or stored',
      () async {
        expect(helper.guardAreasSupported, isFalse);
        await helper.enable();
        final shares = platform.calls;
        await helper.addGuardAreaHere(500);
        expect(platform.calls, shares);
        expect(helper.guardAreas, isEmpty);
      },
    );

    test('joining loads the areas already stored', () async {
      areasTransport.areas = [_area(25.03, 1000)];
      expect(areasHelper.guardAreasSupported, isTrue);
      await areasHelper.enable();
      await _until(() => areasHelper.guardAreas.isNotEmpty);
      expect(areasHelper.guardAreas.single.radiusMeters, 1000);
      expect(areasHelper.guardAreas.single.center.lat, 25.03);
    });

    test(
      'adding reads the position once and stores previous plus new',
      () async {
        areasTransport.areas = [_area(25.03, 500)];
        await areasHelper.enable();
        await _until(() => areasHelper.guardAreas.length == 1);
        final reads = platform.calls;
        await areasHelper.addGuardAreaHere(1000);
        expect(platform.calls, reads + 1);
        final saved = areasTransport.replaced.single;
        expect(saved.map((a) => a.radiusMeters), [500, 1000]);
        expect(saved.last.center.lat, _here.lat);
        expect(areasHelper.guardAreas.map((a) => a.radiusMeters), [500, 1000]);
        expect(areasHelper.message, '已新增守護區。');
        expect(areasHelper.messageIsError, isFalse);
        expect(areasHelper.isBusy, isFalse);
      },
    );

    test(
      'what the server kept is what is shown (it rounds the centre)',
      () async {
        areasTransport.roundOnFetch = true;
        await areasHelper.enable();
        await areasHelper.addGuardAreaHere(500);
        expect(areasHelper.guardAreas.single.center.lat, 25.033);
        expect(areasHelper.guardAreas.single.center.lng, 121.565);
      },
    );

    test('if the follow-up read fails, it shows the rounded values', () async {
      await areasHelper.enable();
      areasTransport.fetchError = const NearbyAlertException('x');
      await areasHelper.addGuardAreaHere(500);
      expect(areasHelper.guardAreas.single.center.lng, 121.565);
      expect(areasHelper.messageIsError, isFalse);
    });

    test('an unsupported radius is ignored and nothing is read', () async {
      await areasHelper.enable();
      final reads = platform.calls;
      await areasHelper.addGuardAreaHere(700);
      expect(platform.calls, reads);
      expect(areasTransport.replaced, isEmpty);
    });

    test('at three areas, adding is ignored', () async {
      areasTransport.areas = [
        _area(25.01, 500),
        _area(25.02, 500),
        _area(25.03, 500),
      ];
      await areasHelper.enable();
      await _until(() => areasHelper.guardAreas.length == 3);
      final reads = platform.calls;
      await areasHelper.addGuardAreaHere(500);
      expect(platform.calls, reads);
      expect(areasTransport.replaced, isEmpty);
    });

    test('a failed location read changes nothing and says why', () async {
      await areasHelper.enable();
      platform.result = sw.LocationFailure(
        status: sw.LocationFailureStatus.denied,
        message: '測試：定位權限未允許',
      );
      await areasHelper.addGuardAreaHere(500);
      expect(areasTransport.replaced, isEmpty);
      expect(areasHelper.guardAreas, isEmpty);
      expect(areasHelper.message, contains('定位權限未允許'));
      expect(areasHelper.messageIsError, isTrue);
    });

    test('a failed save keeps the list and reports the reason', () async {
      areasTransport.areas = [_area(25.03, 500)];
      await areasHelper.enable();
      await _until(() => areasHelper.guardAreas.length == 1);
      areasTransport.replaceError = const NearbyAlertException('操作太頻繁');
      await areasHelper.addGuardAreaHere(500);
      expect(areasHelper.guardAreas.length, 1);
      expect(areasHelper.message, '操作太頻繁');
      expect(areasHelper.messageIsError, isTrue);
    });

    test(
      'removing stores the remaining areas; a bad index is ignored',
      () async {
        areasTransport.areas = [_area(25.01, 500), _area(25.02, 1000)];
        await areasHelper.enable();
        await _until(() => areasHelper.guardAreas.length == 2);
        await areasHelper.removeGuardArea(5);
        expect(areasTransport.replaced, isEmpty);
        await areasHelper.removeGuardArea(0);
        expect(areasTransport.replaced.single.single.radiusMeters, 1000);
        expect(areasHelper.guardAreas.single.radiusMeters, 1000);
        expect(areasHelper.message, '已移除守護區。');
      },
    );

    test('before joining, area changes are ignored', () async {
      await areasHelper.addGuardAreaHere(500);
      await areasHelper.removeGuardArea(0);
      expect(platform.calls, 0);
      expect(areasTransport.replaced, isEmpty);
    });

    test('stopping clears the list and says the areas were deleted', () async {
      areasTransport.areas = [_area(25.03, 500)];
      await areasHelper.enable();
      await _until(() => areasHelper.guardAreas.length == 1);
      await areasHelper.disable();
      expect(areasHelper.guardAreas, isEmpty);
      expect(areasHelper.message, contains('守護區也已刪除'));
    });

    test('stopping when deletion is unconfirmed does not claim it', () async {
      areasTransport.areas = [_area(25.03, 500)];
      await areasHelper.enable();
      await _until(() => areasHelper.guardAreas.length == 1);
      areasTransport.optInError = const NearbyAlertException('x');
      await areasHelper.disable();
      expect(areasHelper.messageIsError, isTrue);
      expect(areasHelper.message, contains('沒有確認伺服器已刪除'));
      expect(areasHelper.message, contains('守護區則要再次停止協助成功後才會刪除'));
      expect(areasHelper.message, isNot(contains('守護區也已刪除')));
    });

    test('disposing mid-add stores nothing', () async {
      await areasHelper.enable();
      platform.pending = Completer<sw.LocationResult>();
      final adding = areasHelper.addGuardAreaHere(500);
      await _until(() => platform.calls >= 2);
      areasHelper.dispose();
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
      await adding;
      expect(areasTransport.replaced, isEmpty);
    });
  });

  group('trusted contacts', () {
    late _ContactsTransport ct;
    late NearbyHelperController h;
    var arrived = 0;

    setUp(() {
      ct = _ContactsTransport();
      arrived = 0;
      h = NearbyHelperController(
        service: NearbyEmergencyService(platform: platform, transport: ct),
        pollInterval: _fast,
        refreshInterval: const Duration(minutes: 30),
        onAlertArrived: () => arrived++,
      );
    });
    tearDown(() => h.dispose());

    test(
      'a backend without contacts: not supported, restore does nothing',
      () async {
        expect(helper.contactsSupported, isFalse);
        await helper.restore();
        await _quiet();
        expect(transport.fetches, 0);
        expect(platform.calls, 0);
        expect(helper.myContacts, isEmpty);
        expect(helper.following, isEmpty);
      },
    );

    test('an unavailable backend: no restore is even attempted', () async {
      ct.reason = '測試：尚未登入';
      expect(h.contactsSupported, isTrue);
      await h.restore();
      expect(ct.restores, 0);
      expect(ct.listCalls, 0);
    });

    test('nothing to restore: no list calls and no polling', () async {
      ct.canRestore = false;
      await h.restore();
      await _quiet();
      expect(ct.restores, 1);
      expect(ct.listCalls, 0);
      expect(ct.fetches, 0);
      expect(h.following, isEmpty);
    });

    test(
      'an existing identity: contacts load, and a contact alert shows once',
      () async {
        ct.mine = [_link('l1'), _link('l2')];
        ct.follows = [_following('f1')];
        ct.alerts = [_contactAlert('c1')];
        await h.restore();
        expect(h.myContacts.map((c) => c.id), ['l1', 'l2']);
        expect(h.following.single.name, '小明');
        await _until(() => h.incoming.isNotEmpty);
        await _until(() => ct.fetches >= 4, reason: 'kept polling');
        expect(h.incoming, hasLength(1));
        expect(h.incoming.single.alertId, 'c1');
        expect(h.incoming.single.fromContact, isTrue);
        expect(h.incoming.single.senderName, '小明');
        expect(arrived, 1);
        // Being a contact reads no position and joins nothing.
        expect(platform.calls, 0);
        expect(ct.optIns, isEmpty);
        expect(h.isOn, isFalse);
      },
    );

    test(
      'contacts of my own but following nobody: loaded, no polling',
      () async {
        ct.mine = [_link('l1')];
        await h.restore();
        await _quiet();
        expect(h.myContacts, hasLength(1));
        expect(ct.fetches, 0);
      },
    );

    test('restore runs once', () async {
      ct.follows = [_following('f1')];
      await h.restore();
      await h.restore();
      expect(ct.restores, 1);
      expect(ct.listCalls, 1);
    });

    test('a contact-only listener pauses in the background and resumes without a position', () async {
      ct.follows = [_following('f1')];
      await h.restore();
      await _until(() => ct.fetches >= 1);

      h.setForeground(false);
      final fetches = ct.fetches;
      await _quiet();
      expect(ct.fetches, fetches);

      h.setForeground(true);
      await _until(() => ct.fetches > fetches, reason: 'polling resumed');
      expect(
        platform.calls,
        0,
        reason: 'nothing to refresh: no position shared',
      );
      expect(ct.optIns, isEmpty);
    });

    test('alerts that arrive while paused are not shown', () async {
      ct.follows = [_following('f1')];
      await h.restore();
      h.setForeground(false);
      ct.alerts = [_contactAlert('late')];
      await _quiet();
      expect(h.incoming, isEmpty);
      expect(arrived, 0);
    });

    test(
      'a helper who is also a contact keeps listening after stopping',
      () async {
        ct.follows = [_following('f1')];
        await h.restore();
        await h.enable();
        expect(h.isOn, isTrue);
        expect(platform.calls, 1);

        await h.disable();
        expect(h.isOn, isFalse);
        expect(ct.optIns, [true, false]);
        final fetches = ct.fetches;
        await _until(() => ct.fetches > fetches, reason: 'still a contact');

        // Leaving the last contact (helper already off) stops listening.
        await h.unfollow('f1');
        await _quiet();
        final after = ct.fetches;
        await _quiet();
        expect(ct.fetches, after);
        expect(h.following, isEmpty);
      },
    );

    test(
      'createInvite stores the name, shows the code and reloads the lists',
      () async {
        await h.createInvite('小明');
        expect(ct.created, ['小明']);
        expect(h.invite!.code, 'ABCD2345');
        expect(h.invite!.expiresAt, DateTime.utc(2026, 11, 9, 12));
        expect(ct.listCalls, greaterThanOrEqualTo(1));
        expect(h.contactsMessage, contains('邀請碼'));
        expect(h.contactsMessageIsError, isFalse);
        expect(h.contactsBusy, isFalse);
        h.clearInvite();
        expect(h.invite, isNull);
      },
    );

    test('createInvite is ignored at five contacts', () async {
      ct.mine = [for (var i = 0; i < 5; i++) _link('l$i')];
      await h.restore();
      await h.createInvite('小明');
      expect(ct.created, isEmpty);
      expect(h.invite, isNull);
    });

    test('a createInvite failure shows its reason and no code', () async {
      ct.error = const NearbyAlertException('操作太頻繁');
      await h.createInvite('小明');
      expect(h.invite, isNull);
      expect(h.contactsMessage, '操作太頻繁');
      expect(h.contactsMessageIsError, isTrue);
      expect(h.contactsBusy, isFalse);
    });

    test(
      'contact work has its own busy flag, separate from the helper card',
      () async {
        ct.gate = Completer<void>();
        final first = h.createInvite('小明');
        await _until(() => h.contactsBusy);
        expect(h.isBusy, isFalse);
        // A second call while busy is ignored.
        await h.createInvite('另一個');
        expect(ct.created, ['小明']);
        ct.gate!.complete();
        await first;
        expect(h.contactsBusy, isFalse);
        expect(h.isBusy, isFalse);
        expect(ct.created, ['小明']);
      },
    );

    test('accepting a code: now a contact, and listening starts', () async {
      ct.followOnPair = _following('f1');
      await h.acceptInvite('abcd 2345');
      expect(ct.accepted, ['abcd 2345']);
      expect(h.following.single.name, '小明');
      expect(h.contactsMessage, contains('已加入'));
      expect(h.contactsMessageIsError, isFalse);
      await _until(() => ct.fetches >= 2, reason: 'polling started');
      expect(platform.calls, 0);
    });

    test('every refusal has its own message and changes nothing', () async {
      final cases = {
        NearbyInviteResult.invalid: '邀請碼不正確',
        NearbyInviteResult.self: '自己的邀請碼',
        NearbyInviteResult.ownerFull: '對方的緊急聯絡人已滿',
        NearbyInviteResult.followingFull: '太多人',
      };
      for (final entry in cases.entries) {
        ct.acceptResult = entry.key;
        await h.acceptInvite('ABCD2345');
        expect(
          h.contactsMessage,
          contains(entry.value),
          reason: '${entry.key}',
        );
        expect(h.contactsMessageIsError, isTrue, reason: '${entry.key}');
        expect(h.following, isEmpty);
        expect(h.contactsBusy, isFalse);
      }
      expect(ct.accepted, hasLength(cases.length));
      await _quiet();
      expect(ct.fetches, 0, reason: 'a refused code never starts listening');
    });

    test('a failure using a code shows the reason, or a generic one', () async {
      ct.error = const NearbyAlertException('操作太頻繁');
      await h.acceptInvite('ABCD2345');
      expect(h.contactsMessage, '操作太頻繁');
      expect(h.contactsMessageIsError, isTrue);

      ct.error = StateError('SECRET');
      await h.acceptInvite('ABCD2345');
      expect(h.contactsMessage, '無法使用邀請碼，請稍後再試');
      expect(h.contactsMessage, isNot(contains('SECRET')));
      expect(h.contactsMessageIsError, isTrue);
    });

    test('removing a contact stores it, reloads and says so', () async {
      ct.mine = [_link('l1'), _link('l2')];
      await h.restore();
      ct.follows = [_following('f1')];
      await h.removeContact('l1');
      expect(ct.removed, ['l1']);
      expect(h.myContacts.map((c) => c.id), ['l2']);
      expect(h.contactsMessage, contains('已移除'));
      expect(h.contactsMessageIsError, isFalse);
    });

    test('leaving as someone\'s contact reloads and says so', () async {
      ct.follows = [_following('f1')];
      await h.restore();
      await h.unfollow('f1');
      expect(ct.unfollowed, ['f1']);
      expect(h.following, isEmpty);
      expect(h.contactsMessage, contains('已停止接收'));
      expect(h.contactsMessageIsError, isFalse);
    });

    test('a second remove or leave while one is running is ignored', () async {
      ct.mine = [_link('l1'), _link('l2')];
      ct.follows = [_following('f1'), _following('f2')];
      await h.restore();
      ct.gate = Completer<void>();
      final removing = h.removeContact('l1');
      await _until(() => h.contactsBusy);
      await h.removeContact('l2');
      await h.unfollow('f1');
      expect(ct.removed, ['l1']);
      expect(ct.unfollowed, isEmpty);
      ct.gate!.complete();
      await removing;
      expect(ct.removed, ['l1']);
    });

    test(
      'disposing mid-operation: no exception, no further requests',
      () async {
        ct.gate = Completer<void>();
        final creating = h.createInvite('小明');
        await _until(() => h.contactsBusy);
        h.dispose();
        final lists = ct.listCalls;
        ct.gate!.complete();
        await creating;
        await _quiet();
        // Nothing more is requested once the controller is gone.
        expect(ct.listCalls, lists);
        expect(ct.fetches, 0);
        expect(ct.optIns, isEmpty);
      },
    );
  });
}
