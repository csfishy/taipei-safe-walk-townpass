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
      await transport.replaceGuardAreas([area(25.033, 500), area(25.05, 2000)]);
      final call = net.sent.single;
      expect(call.url.path, '/rest/v1/rpc/nearby_helper_set_areas');
      expect(call.headers['authorization'], 'Bearer $_token');
      expect(call.json, {
        'p_areas': [
          {'lat': 25.033, 'lng': 121.5654, 'radius_m': 500},
          {'lat': 25.05, 'lng': 121.5654, 'radius_m': 2000},
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
}
