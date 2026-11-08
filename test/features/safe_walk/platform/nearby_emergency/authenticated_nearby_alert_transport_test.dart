import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/authenticated_nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial fixtures only: no real key, token, identity or location.
const _token = 'aaaa.bbbb.cccc';
const _requestId = '30000000-0000-4000-8000-000000000001';
const _callerIdentity = 'CALLER-CHOSEN-IDENTITY-MUST-NOT-BE-SENT';
final _here = sw.Coordinates(lat: 25.033, lng: 121.5654);

final _config = SafeWalkSupabaseConfig(
  url: Uri.parse('https://artificial.example'),
  apiKey: 'sb_publishable_artificial-local-test-key',
);

class _Session implements NearbySession {
  bool signedIn = true;
  String? token = _token;
  int tokenReads = 0;
  @override
  bool get isSignedIn => signedIn;
  @override
  Future<String?> accessToken() async {
    tokenReads++;
    return token;
  }
}

class _ExistingSession implements NearbySession, NearbyExistingIdentity {
  String? existing = _token;
  int existingReads = 0;
  int tokenReads = 0;
  @override
  bool get isSignedIn => true;
  @override
  Future<String?> existingAccessToken() async {
    existingReads++;
    return existing;
  }

  @override
  Future<String?> accessToken() async {
    tokenReads++;
    return 'must.not.be.used';
  }
}

class _SlowSession implements NearbySession {
  final completer = Completer<String?>();
  @override
  bool get isSignedIn => true;
  @override
  Future<String?> accessToken() => completer.future;
}

class _Cancel implements SafeWalkCancellation {
  final _done = Completer<void>();
  @override
  bool get isCancelled => _done.isCompleted;
  @override
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

class _Sent {
  _Sent(this.url);
  final Uri url;
  final headers = <String, String>{};
  final body = <int>[];
  Map<String, dynamic> get json =>
      jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
}

class _Network {
  final sent = <_Sent>[];
  int status = 200;
  String body = 'null';

  SupabaseRpcClient client() =>
      SupabaseRpcClient(config: _config, createHttpClient: _http);

  HttpClient _http() => _Http(this);
}

class _Http implements HttpClient {
  _Http(this._net);
  final _Network _net;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    final sent = _Sent(url);
    _net.sent.add(sent);
    return _Request(sent, _net);
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this._sent, this._net) : headers = _Headers(_sent);
  final _Sent _sent;
  final _Network _net;
  @override
  bool followRedirects = true;
  @override
  final HttpHeaders headers;
  @override
  void add(List<int> data) => _sent.body.addAll(data);
  @override
  Future<HttpClientResponse> close() async => _Response(_net.status, _net.body);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers(this._sent);
  final _Sent _sent;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _sent.headers[name.toLowerCase()] = value.toString();
  @override
  set contentType(ContentType? type) =>
      _sent.headers['content-type'] = type.toString();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, String body) : _body = utf8.encode(body);
  final List<int> _body;
  @override
  final int statusCode;
  @override
  int get contentLength => -1;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform implements PlatformService {
  int calls = 0;
  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    calls++;
    return sw.LocationSuccess(
      position: sw.Position(
        coordinates: _here,
        source: sw.PositionSource.gps,
        accuracyMeters: 12,
        observedAt: '2026-11-08T00:00:00Z',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Network net;
  late _Session session;
  late AuthenticatedNearbyAlertTransport transport;

  setUp(() {
    net = _Network();
    session = _Session();
    transport = AuthenticatedNearbyAlertTransport(
      rpc: net.client(),
      session: session,
      newRequestId: () => _requestId,
    );
  });

  test(
    'SOS sends only coordinates and a request id under the session',
    () async {
      net.body = '3';
      final count = await transport.sendEmergencyAlert(
        senderId: _callerIdentity,
        location: _here,
        radiusMeters: 500,
      );
      expect(count, 3);
      final call = net.sent.single;
      expect(call.url.path, '/rest/v1/rpc/nearby_sos_send');
      expect(call.headers['authorization'], 'Bearer $_token');
      expect(call.headers['apikey'], _config.apiKey);
      expect(call.json, {
        'p_lat': 25.033,
        'p_lng': 121.5654,
        'p_client_request_id': _requestId,
      });
      expect(utf8.decode(call.body), isNot(contains(_callerIdentity)));
      expect(call.url.toString(), isNot(contains('25.033')));
    },
  );

  test(
    'a caller-supplied radius other than 500 m is refused locally',
    () async {
      await expectLater(
        transport.sendEmergencyAlert(
          senderId: _callerIdentity,
          location: _here,
          radiusMeters: 5000,
        ),
        throwsA(isA<NearbyAlertException>()),
      );
      expect(net.sent, isEmpty);
    },
  );

  test('opting in registers consent, then reports one position', () async {
    await transport.setHelperOptIn(
      helperId: _callerIdentity,
      enabled: true,
      location: _here,
    );
    expect(net.sent.map((s) => s.url.path), [
      '/rest/v1/rpc/nearby_helper_opt_in',
      '/rest/v1/rpc/nearby_helper_report_location',
    ]);
    expect(net.sent[0].json, {'p_consent_version': nearbyHelperConsentVersion});
    expect(net.sent[1].json, {'p_lat': 25.033, 'p_lng': 121.5654});
    for (final call in net.sent) {
      expect(call.headers['authorization'], 'Bearer $_token');
      expect(utf8.decode(call.body), isNot(contains(_callerIdentity)));
    }
  });

  test('opting out sends no location at all', () async {
    await transport.setHelperOptIn(
      helperId: _callerIdentity,
      enabled: false,
      location: _here,
    );
    expect(net.sent.single.url.path, '/rest/v1/rpc/nearby_helper_opt_out');
    expect(net.sent.single.json, isEmpty);
  });

  test('opting in without a position is refused before any request', () async {
    await expectLater(
      transport.setHelperOptIn(helperId: _callerIdentity, enabled: true),
      throwsA(isA<NearbyAlertException>()),
    );
    expect(net.sent, isEmpty);
  });

  test(
    'fetch returns alerts addressed to the caller without a sender',
    () async {
      net.body = jsonEncode([
        {
          'alert_id': '40000000-0000-4000-8000-000000000001',
          'lat': 25.0331,
          'lng': 121.5655,
          'radius_m': 500,
          'created_at': '2026-11-08T01:02:03+00:00',
          'expires_at': '2026-11-08T01:32:03+00:00',
        },
      ]);
      final alerts = await transport.fetchPendingAlerts(_callerIdentity);
      expect(alerts, hasLength(1));
      expect(alerts.single.alertId, '40000000-0000-4000-8000-000000000001');
      expect(alerts.single.senderId, isNull);
      expect(alerts.single.location.lat, 25.0331);
      expect(alerts.single.radiusMeters, 500);
      expect(alerts.single.createdAt.toUtc().hour, 1);
      expect(
        net.sent.single.url.path,
        '/rest/v1/rpc/nearby_helper_fetch_alerts',
      );
      expect(
        utf8.decode(net.sent.single.body),
        isNot(contains(_callerIdentity)),
      );
    },
  );

  test('signed out: nothing is sent and the reason is reported', () async {
    session.signedIn = false;
    expect(transport.currentUnavailableReason, isNotNull);
    expect(nearbyBackendUnavailableReason(transport), isNotNull);
    await expectLater(
      transport.sendEmergencyAlert(
        senderId: _callerIdentity,
        location: _here,
        radiusMeters: 500,
      ),
      throwsA(isA<NearbyAlertException>()),
    );
    await expectLater(
      transport.fetchPendingAlerts(_callerIdentity),
      throwsA(isA<NearbyAlertException>()),
    );
    expect(net.sent, isEmpty);
    expect(session.tokenReads, 0);
  });

  test('a missing or malformed token is never put on the wire', () async {
    for (final bad in [null, '', 'not-a-jwt', 'aaa.bbb.ccc\r\nX-Evil: 1']) {
      session.token = bad;
      await expectLater(
        transport.fetchPendingAlerts(_callerIdentity),
        throwsA(isA<NearbyAlertException>()),
      );
    }
    expect(net.sent, isEmpty);
  });

  test('server errors become generic messages without token or body', () async {
    const secretBody = '{"message":"SECRET-DETAIL near 25.033,121.5654"}';
    for (final status in [400, 401, 403, 429, 500, 503, 404]) {
      net.status = status;
      net.body = secretBody;
      try {
        await transport.sendEmergencyAlert(
          senderId: _callerIdentity,
          location: _here,
          radiusMeters: 500,
        );
        fail('HTTP $status must fail');
      } on NearbyAlertException catch (error) {
        expect(error.message, isNot(contains(_token)));
        expect(error.message, isNot(contains('SECRET-DETAIL')));
        expect(error.message, isNot(contains('25.033')));
      }
    }
    net.status = 429;
    await expectLater(
      transport.sendEmergencyAlert(
        senderId: _callerIdentity,
        location: _here,
        radiusMeters: 500,
      ),
      throwsA(
        isA<NearbyAlertException>().having(
          (e) => e.message,
          'message',
          contains('太頻繁'),
        ),
      ),
    );
  });

  test('malformed success bodies are rejected, not guessed', () async {
    for (final body in ['not json', '"3"', '-1', '{}']) {
      net.body = body;
      await expectLater(
        transport.sendEmergencyAlert(
          senderId: _callerIdentity,
          location: _here,
          radiusMeters: 500,
        ),
        throwsA(isA<NearbyAlertException>()),
        reason: body,
      );
    }
    for (final body in ['{}', '[{"alert_id":1}]', '[[]]']) {
      net.body = body;
      await expectLater(
        transport.fetchPendingAlerts(_callerIdentity),
        throwsA(isA<NearbyAlertException>()),
        reason: body,
      );
    }
  });

  test('service refuses before reading GPS while signed out', () async {
    session.signedIn = false;
    final platform = _Platform();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
    );
    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: _callerIdentity,
      userInitiated: true,
    );
    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.backendUnavailable,
    );
    expect(platform.calls, 0);
    expect(net.sent, isEmpty);
  });

  test('service sends once on a user action while signed in', () async {
    net.body = '2';
    final platform = _Platform();
    final service = NearbyEmergencyService(
      platform: platform,
      transport: transport,
    );
    final denied = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: _callerIdentity,
      userInitiated: false,
    );
    expect(denied, isA<NearbyEmergencyNotSent>());
    expect(net.sent, isEmpty);

    final result = await service.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: _callerIdentity,
      userInitiated: true,
    );
    expect((result as NearbyEmergencySent).recipientCount, 2);
    expect(platform.calls, 1);
    expect(net.sent, hasLength(1));
    expect(net.sent.single.json['p_lat'], 25.033);
  });

  test('mock mode never reaches the backend even when signed in', () async {
    final service = NearbyEmergencyService(
      platform: _Platform(),
      transport: transport,
    );
    final result = await service.triggerEmergency(
      mode: sw.DataMode.mock,
      senderId: _callerIdentity,
      userInitiated: true,
    );
    expect(
      (result as NearbyEmergencyNotSent).reason,
      NearbyEmergencyBlock.mockMode,
    );
    expect(net.sent, isEmpty);
  });

  group('guard areas', () {
    NearbyGuardArea area(double lat, int radius) => NearbyGuardArea(
      center: sw.Coordinates(lat: lat, lng: 121.5654),
      radiusMeters: radius,
    );

    test('replace sends only the areas, under the session', () async {
      await transport.replaceGuardAreas([area(25.033, 500), area(25.05, 1000)]);
      final call = net.sent.single;
      expect(call.url.path, '/rest/v1/rpc/nearby_helper_set_areas');
      expect(call.headers['authorization'], 'Bearer $_token');
      expect(call.json, {
        'p_areas': [
          {'lat': 25.033, 'lng': 121.5654, 'radius_m': 500},
          {'lat': 25.05, 'lng': 121.5654, 'radius_m': 1000},
        ],
      });
    });

    test('an empty list clears the areas', () async {
      await transport.replaceGuardAreas(const []);
      expect(net.sent.single.json, {'p_areas': <Object?>[]});
    });

    test(
      'too many areas or an unsupported radius never reach the wire',
      () async {
        await expectLater(
          transport.replaceGuardAreas([
            for (var i = 0; i < 4; i++) area(25, 500),
          ]),
          throwsA(isA<NearbyAlertException>()),
        );
        await expectLater(
          transport.replaceGuardAreas([area(25, 700)]),
          throwsA(isA<NearbyAlertException>()),
        );
        // 2 km was allowed once; the cap is now 1 km.
        await expectLater(
          transport.replaceGuardAreas([area(25, 2000)]),
          throwsA(isA<NearbyAlertException>()),
        );
        expect(net.sent, isEmpty);
      },
    );

    test('fetch parses the stored areas', () async {
      net.body = jsonEncode([
        {'lat': 25.033, 'lng': 121.566, 'radius_m': 1000},
        {'lat': 25.05, 'lng': 121.57, 'radius_m': 500},
      ]);
      final areas = await transport.fetchGuardAreas();
      expect(areas.map((a) => a.radiusMeters), [1000, 500]);
      expect(areas.first.center.lat, 25.033);
      expect(net.sent.single.url.path, '/rest/v1/rpc/nearby_helper_get_areas');
      expect(net.sent.single.json, isEmpty);
    });

    test('malformed area bodies are rejected', () async {
      for (final body in ['not json', '{}', '[{"lat":"x"}]', '[[]]']) {
        net.body = body;
        await expectLater(
          transport.fetchGuardAreas(),
          throwsA(isA<NearbyAlertException>()),
          reason: body,
        );
      }
    });

    test('signed out: no area request is made', () async {
      session.signedIn = false;
      await expectLater(
        transport.fetchGuardAreas(),
        throwsA(isA<NearbyAlertException>()),
      );
      await expectLater(
        transport.replaceGuardAreas([area(25, 500)]),
        throwsA(isA<NearbyAlertException>()),
      );
      expect(net.sent, isEmpty);
    });

    test('the service exposes the capability only when the backend has it', () {
      expect(transport, isA<NearbyHelperAreas>());
      final service = NearbyEmergencyService(
        platform: _Platform(),
        transport: transport,
      );
      expect(service.supportsGuardAreas, isTrue);
    });
  });

  group('identity is made ready before any location is read', () {
    test('no token available: refuses, reads no GPS, sends nothing', () async {
      session.token = null; // signed in as far as it knows, but no token comes
      final platform = _Platform();
      final service = NearbyEmergencyService(
        platform: platform,
        transport: transport,
      );
      final result = await service.triggerEmergency(
        mode: sw.DataMode.live,
        senderId: _callerIdentity,
        userInitiated: true,
      );
      expect(
        (result as NearbyEmergencyNotSent).reason,
        NearbyEmergencyBlock.backendUnavailable,
      );
      await expectLater(
        service.setHelperOptIn(
          mode: sw.DataMode.live,
          helperId: _callerIdentity,
          enabled: true,
          userInitiated: true,
        ),
        throwsA(isA<NearbyAlertException>()),
      );
      expect(platform.calls, 0);
      expect(net.sent, isEmpty);
    });

    test('GPS is read only after the identity is ready', () async {
      final slow = _SlowSession();
      final platform = _Platform();
      final service = NearbyEmergencyService(
        platform: platform,
        transport: AuthenticatedNearbyAlertTransport(
          rpc: net.client(),
          session: slow,
          newRequestId: () => _requestId,
        ),
      );
      net.body = '1';
      final pending = service.triggerEmergency(
        mode: sw.DataMode.live,
        senderId: _callerIdentity,
        userInitiated: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(platform.calls, 0, reason: 'still setting up the identity');
      slow.completer.complete(_token);
      final result = await pending;
      expect((result as NearbyEmergencySent).recipientCount, 1);
      expect(platform.calls, 1);
    });

    test(
      'cancelling while the identity is being set up reads nothing',
      () async {
        final slow = _SlowSession();
        final platform = _Platform();
        final service = NearbyEmergencyService(
          platform: platform,
          transport: AuthenticatedNearbyAlertTransport(
            rpc: net.client(),
            session: slow,
          ),
        );
        final cancel = _Cancel();
        final pending = service.triggerEmergency(
          mode: sw.DataMode.live,
          senderId: _callerIdentity,
          userInitiated: true,
          cancellation: cancel,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        cancel.cancel();
        final result = await pending;
        expect(
          (result as NearbyEmergencyNotSent).reason,
          NearbyEmergencyBlock.cancelled,
        );
        slow.completer.complete(_token);
        await Future<void>.delayed(Duration.zero);
        expect(platform.calls, 0);
        expect(net.sent, isEmpty);
      },
    );

    test('prepare reports ready, or the reason', () async {
      expect(await transport.prepare(), isNull);
      session.token = 'not-a-jwt';
      expect(
        await transport.prepare(),
        AuthenticatedNearbyAlertTransport.identityUnavailableReason,
      );
      session.signedIn = false;
      expect(
        await transport.prepare(),
        AuthenticatedNearbyAlertTransport.identityUnavailableReason,
      );
    });
  });

  group('trusted contacts', () {
    const link = '11111111-2222-4333-8444-555555555555';

    Future<void> expectRefused(Future<Object?> call) =>
        expectLater(call, throwsA(isA<NearbyAlertException>()));

    test(
      'createContactInvite sends the trimmed name and parses the code',
      () async {
        net.body = jsonEncode([
          {'code': 'ABCDEFGH', 'expires_at': '2026-11-09T01:02:03+00:00'},
        ]);
        final invite = await transport.createContactInvite('  小明  ');
        final call = net.sent.single;
        expect(call.url.path, '/rest/v1/rpc/nearby_contact_invite_create');
        expect(call.headers['authorization'], 'Bearer $_token');
        expect(call.json, {'p_display_name': '小明'});
        expect(invite.code, 'ABCDEFGH');
        expect(invite.expiresAt.toUtc(), DateTime.utc(2026, 11, 9, 1, 2, 3));
      },
    );

    test('names are counted in code points, 1 to 20', () async {
      net.body = jsonEncode([
        {'code': 'ABCDEFGH', 'expires_at': '2026-11-09T01:02:03+00:00'},
      ]);
      await transport.createContactInvite('字' * 20);
      await transport.createContactInvite('😀' * 20);
      expect(net.sent, hasLength(2));
      net.sent.clear();
      await expectRefused(transport.createContactInvite(''));
      await expectRefused(transport.createContactInvite('   '));
      await expectRefused(transport.createContactInvite('字' * 21));
      await expectRefused(transport.createContactInvite('😀' * 21));
      expect(net.sent, isEmpty, reason: 'a bad name never reaches the wire');
    });

    test('a malformed invite answer is rejected, not guessed', () async {
      for (final body in [
        'not json',
        '{}',
        '[]',
        '[{"code":1,"expires_at":"x"}]',
        '[{"code":"ABCDEFGH"}]',
        '[{"code":"ABCDEFGH","expires_at":"nope"}]',
      ]) {
        net.body = body;
        await expectRefused(transport.createContactInvite('小明'));
      }
    });

    test('acceptContactInvite normalizes case, spaces and dashes', () async {
      net.body = '"ok"';
      for (final typed in [
        'abcdefgh',
        'ABCD EFGH',
        ' abcd-efgh ',
        'AbCd - EfGh',
      ]) {
        final result = await transport.acceptContactInvite(typed);
        expect(result, NearbyInviteResult.paired, reason: typed);
      }
      expect(net.sent, hasLength(4));
      for (final call in net.sent) {
        expect(call.url.path, '/rest/v1/rpc/nearby_contact_invite_accept');
        expect(call.json, {'p_code': 'ABCDEFGH'});
        expect(call.headers['authorization'], 'Bearer $_token');
      }
    });

    test('a malformed code is invalid and never sent', () async {
      for (final typed in [
        '',
        'ABCDEFG',
        'ABCDEFGHJ',
        'ABCDEFGI', // I is not in the alphabet
        'ABCDEFGL', // L is not either
        'ABCDEFGO',
        'ABCDEFG0',
        'ABCDEFG1',
        'ABCDEF!H',
      ]) {
        expect(
          await transport.acceptContactInvite(typed),
          NearbyInviteResult.invalid,
          reason: typed,
        );
      }
      expect(net.sent, isEmpty, reason: 'it must not use up an attempt');
      expect(session.tokenReads, 0);
    });

    test('the server status strings map to the result', () async {
      const expected = {
        '"ok"': NearbyInviteResult.paired,
        '"invalid"': NearbyInviteResult.invalid,
        '"self"': NearbyInviteResult.self,
        '"owner_full"': NearbyInviteResult.ownerFull,
        '"following_full"': NearbyInviteResult.followingFull,
      };
      for (final entry in expected.entries) {
        net.body = entry.key;
        expect(
          await transport.acceptContactInvite('ABCDEFGH'),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('an unknown or malformed status is an error, not a pairing', () async {
      for (final body in [
        '"weird"',
        '"OK"',
        'null',
        '1',
        'true',
        '{}',
        'not json',
      ]) {
        net.body = body;
        await expectRefused(transport.acceptContactInvite('ABCDEFGH'));
      }
    });

    test('listMyContacts parses ids and dates', () async {
      net.body = jsonEncode([
        {'link_id': link, 'since': '2026-11-08T01:02:03+00:00'},
        {
          'link_id': '99999999-2222-4333-8444-555555555555',
          'since': '2026-11-08T02:00:00+00:00',
        },
      ]);
      final mine = await transport.listMyContacts();
      expect(mine.map((c) => c.id), [
        link,
        '99999999-2222-4333-8444-555555555555',
      ]);
      expect(mine.first.since.toUtc(), DateTime.utc(2026, 11, 8, 1, 2, 3));
      expect(net.sent.single.url.path, '/rest/v1/rpc/nearby_contact_list_mine');
      expect(net.sent.single.json, isEmpty);
    });

    test('listFollowing parses the names the owners chose', () async {
      net.body = jsonEncode([
        {
          'link_id': link,
          'display_name': '小明',
          'since': '2026-11-08T01:02:03+00:00',
        },
      ]);
      final following = await transport.listFollowing();
      expect(following.single.id, link);
      expect(following.single.name, '小明');
      expect(net.sent.single.url.path, '/rest/v1/rpc/nearby_contact_following');
      expect(net.sent.single.json, isEmpty);
    });

    test('malformed list bodies are rejected', () async {
      for (final body in [
        'not json',
        '{}',
        '[1]',
        '[{"link_id":1,"since":"2026-11-08T01:02:03+00:00"}]',
        '[{"link_id":"$link"}]',
        '[{"link_id":"$link","since":"nope"}]',
      ]) {
        net.body = body;
        await expectRefused(transport.listMyContacts());
      }
      for (final body in [
        'not json',
        '{}',
        '[{"link_id":"$link","since":"2026-11-08T01:02:03+00:00"}]',
        '[{"link_id":"$link","display_name":1,"since":"2026-11-08T01:02:03+00:00"}]',
      ]) {
        net.body = body;
        await expectRefused(transport.listFollowing());
      }
    });

    test('remove and unfollow send only the link id', () async {
      await transport.removeContact(link);
      await transport.unfollow(link.toUpperCase());
      expect(net.sent[0].url.path, '/rest/v1/rpc/nearby_contact_remove');
      expect(net.sent[0].json, {'p_link_id': link});
      expect(net.sent[1].url.path, '/rest/v1/rpc/nearby_contact_unfollow');
      expect(net.sent[1].json, {'p_link_id': link.toUpperCase()});
      for (final call in net.sent) {
        expect(call.headers['authorization'], 'Bearer $_token');
      }
    });

    test('a link id that is not a UUID is refused without a request', () async {
      for (final bad in ['', 'x', 'not-a-uuid', '$link; drop', ' $link']) {
        await expectRefused(transport.removeContact(bad));
        await expectRefused(transport.unfollow(bad));
      }
      expect(net.sent, isEmpty);
    });

    test(
      'fetch parses who a contact alert is from, and nothing for a helper',
      () async {
        net.body = jsonEncode([
          {
            'alert_id': '40000000-0000-4000-8000-000000000001',
            'lat': 25.0331,
            'lng': 121.5655,
            'radius_m': 500,
            'created_at': '2026-11-08T01:02:03+00:00',
            'expires_at': '2026-11-08T01:32:03+00:00',
            'from_contact': true,
            'sender_name': '小明',
          },
          {
            'alert_id': '40000000-0000-4000-8000-000000000002',
            'lat': 25.0331,
            'lng': 121.5655,
            'radius_m': 500,
            'created_at': '2026-11-08T01:02:03+00:00',
            'expires_at': '2026-11-08T01:32:03+00:00',
            'from_contact': false,
            'sender_name': null,
          },
          {
            // An older backend row without the new columns at all.
            'alert_id': '40000000-0000-4000-8000-000000000003',
            'lat': 25.0331,
            'lng': 121.5655,
            'radius_m': 500,
            'created_at': '2026-11-08T01:02:03+00:00',
            'expires_at': '2026-11-08T01:32:03+00:00',
          },
        ]);
        final alerts = await transport.fetchPendingAlerts(_callerIdentity);
        expect(alerts[0].fromContact, isTrue);
        expect(alerts[0].senderName, '小明');
        for (final helperAlert in alerts.skip(1)) {
          expect(helperAlert.fromContact, isFalse);
          expect(helperAlert.senderName, isNull);
          expect(helperAlert.senderId, isNull);
        }
      },
    );

    test('404 and 409 become plain messages without token or body', () async {
      const secretBody = '{"message":"SECRET-DETAIL ABCDEFGH"}';
      net.body = secretBody;
      for (final entry in {404: '找不到，或已過期', 409: '已達上限'}.entries) {
        net.status = entry.key;
        for (final call in <Future<Object?> Function()>[
          () => transport.createContactInvite('小明'),
          () => transport.acceptContactInvite('ABCDEFGH'),
          () => transport.listMyContacts(),
          () => transport.removeContact(link),
          () => transport.listFollowing(),
          () => transport.unfollow(link),
        ]) {
          await expectLater(
            call(),
            throwsA(
              isA<NearbyAlertException>()
                  .having((e) => e.message, 'message', entry.value)
                  .having((e) => e.message, 'no token', isNot(contains(_token)))
                  .having(
                    (e) => e.message,
                    'no body',
                    isNot(contains('SECRET-DETAIL')),
                  ),
            ),
            reason: 'HTTP ${entry.key}',
          );
        }
      }
    });

    test('signed out: every contact call is refused with no request', () async {
      session.signedIn = false;
      await expectRefused(transport.createContactInvite('小明'));
      await expectRefused(transport.acceptContactInvite('ABCDEFGH'));
      await expectRefused(transport.listMyContacts());
      await expectRefused(transport.removeContact(link));
      await expectRefused(transport.listFollowing());
      await expectRefused(transport.unfollow(link));
      expect(net.sent, isEmpty);
      expect(session.tokenReads, 0);
    });

    test(
      'a token that is missing or malformed is never sent for contacts',
      () async {
        for (final bad in [null, '', 'not-a-jwt', 'aaa.bbb.ccc\r\nX-Evil: 1']) {
          session.token = bad;
          await expectRefused(transport.listFollowing());
        }
        expect(net.sent, isEmpty);
      },
    );

    test(
      'the service exposes the contact capability only when the backend has it',
      () {
        expect(transport, isA<NearbyTrustedContacts>());
        final service = NearbyEmergencyService(
          platform: _Platform(),
          transport: transport,
        );
        expect(service.supportsContacts, isTrue);
      },
    );
  });

  group('restoring an existing identity', () {
    test(
      'a session that knows existing identities uses only that path',
      () async {
        final existing = _ExistingSession();
        final restoring = AuthenticatedNearbyAlertTransport(
          rpc: net.client(),
          session: existing,
        );
        expect(await restoring.restoreExistingIdentity(), isTrue);
        expect(existing.existingReads, 1);
        expect(existing.tokenReads, 0, reason: 'accessToken would create one');
        expect(net.sent, isEmpty);
      },
    );

    test(
      'no existing identity means false, still without creating one',
      () async {
        final existing = _ExistingSession()..existing = null;
        final restoring = AuthenticatedNearbyAlertTransport(
          rpc: net.client(),
          session: existing,
        );
        expect(await restoring.restoreExistingIdentity(), isFalse);
        expect(existing.tokenReads, 0);
      },
    );

    test('a malformed existing token is not an identity', () async {
      final existing = _ExistingSession()..existing = 'not-a-jwt';
      final restoring = AuthenticatedNearbyAlertTransport(
        rpc: net.client(),
        session: existing,
      );
      expect(await restoring.restoreExistingIdentity(), isFalse);
      existing.existing = 'aaa.bbb.ccc\r\nX-Evil: 1';
      expect(await restoring.restoreExistingIdentity(), isFalse);
    });

    test('a plain session falls back to its access token', () async {
      expect(await transport.restoreExistingIdentity(), isTrue);
      expect(session.tokenReads, 1);
      session.token = null;
      expect(await transport.restoreExistingIdentity(), isFalse);
      session.token = 'not-a-jwt';
      expect(await transport.restoreExistingIdentity(), isFalse);
      expect(net.sent, isEmpty);
    });

    test(
      'the service reports a restored identity, and false on any failure',
      () async {
        final service = NearbyEmergencyService(
          platform: _Platform(),
          transport: transport,
        );
        expect(await service.restoreIdentity(), isTrue);
        session.token = null;
        expect(await service.restoreIdentity(), isFalse);
      },
    );
  });

  group('normalizeNearbyInviteCode', () {
    test('ignores case, spaces and dashes', () {
      expect(normalizeNearbyInviteCode('abcd-efgh'), 'ABCDEFGH');
      expect(normalizeNearbyInviteCode(' ab cd  ef-gh '), 'ABCDEFGH');
      expect(normalizeNearbyInviteCode('PQRS2345'), 'PQRS2345');
      expect(normalizeNearbyInviteCode('jkmn6789'), 'JKMN6789');
    });

    test('the alphabet leaves out I, L, O, 0 and 1', () {
      for (final bad in ['I', 'L', 'O', '0', '1']) {
        expect(normalizeNearbyInviteCode('ABCDEFG$bad'), isNull, reason: bad);
        expect(
          normalizeNearbyInviteCode('ABCDEFG${bad.toLowerCase()}'),
          isNull,
        );
      }
    });

    test('anything that is not exactly eight characters is not a code', () {
      for (final bad in [
        '',
        '-',
        'ABCDEFG',
        'ABCDEFGHJ',
        'ABCD EFG',
        'ABCDEFG!',
        'ＡＢＣＤＥＦＧＨ',
      ]) {
        expect(normalizeNearbyInviteCode(bad), isNull, reason: bad);
      }
    });
  });

  test('no message a person can see tells them to log in or says they were logged out', () async {
    // This app has no login: the identity is made automatically.
    const wording = ['登入', '登出'];
    for (final w in wording) {
      expect(
        AuthenticatedNearbyAlertTransport.identityUnavailableReason,
        isNot(contains(w)),
      );
    }
    session.signedIn = false;
    expect(transport.currentUnavailableReason, isNotNull);
    session.signedIn = true;
    for (final status in [400, 401, 403, 404, 409, 422, 429, 500, 503]) {
      net.status = status;
      net.body = '{}';
      final attempts = <Future<Object?> Function()>[
        () => transport.sendEmergencyAlert(
          senderId: 'x',
          location: _here,
          radiusMeters: 500,
        ),
        () => transport.fetchPendingAlerts('x'),
        () => transport.listMyContacts(),
        () => transport.acceptContactInvite('ABCDEFGH'),
      ];
      for (final attempt in attempts) {
        try {
          await attempt();
          fail('HTTP $status must fail');
        } on NearbyAlertException catch (error) {
          for (final w in wording) {
            expect(error.message, isNot(contains(w)), reason: 'HTTP $status');
          }
        }
      }
    }
  });
}
