import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_connection.dart';

void main() {
  const key = 'sb_publishable_artificial-local-test-key';
  const document = {
    'swagger': '2.0',
    'info': {'title': 'PostgREST API', 'version': '1.0'},
    'paths': <String, Object?>{},
  };
  late HttpServer server;
  late Uri origin;
  late Future<void> Function(HttpRequest request) handler;
  final requests = <HttpRequest>[];
  final requestBodies = <String>[];
  final connections = <SupabaseConnection>[];

  Future<void> respond(
    HttpRequest request,
    String body, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  }

  setUp(() async {
    requests.clear();
    requestBodies.clear();
    connections.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = Uri.parse('http://127.0.0.1:${server.port}');
    handler = (request) => respond(request, jsonEncode(document));
    server.listen((request) async {
      requests.add(request);
      requestBodies.add(await utf8.decoder.bind(request).join());
      await handler(request);
    });
  });

  tearDown(() async {
    for (final connection in connections) {
      connection.close();
    }
    await server.close(force: true);
  });

  SafeWalkSupabaseConfig config({String apiKey = key}) =>
      SafeWalkSupabaseConfig(
        url: origin,
        apiKey: apiKey,
        allowInsecureLocalhost: true,
      );

  SupabaseConnection connection({
    Duration timeout = const Duration(seconds: 3),
    int maxResponseBytes = 1024 * 1024,
  }) {
    final value = SupabaseConnection(
      config: config(),
      timeout: timeout,
      maxResponseBytes: maxResponseBytes,
    );
    connections.add(value);
    return value;
  }

  TypeMatcher<SupabaseConnectionException> failure(
    SupabaseConnectionFailure expected,
  ) => isA<SupabaseConnectionException>().having(
    (error) => error.failure,
    'failure',
    expected,
  );

  test(
    'construction is idle; explicit check only GETs the REST API root',
    () async {
      final client = connection();
      await Future<void>.delayed(Duration.zero);
      expect(requests, isEmpty);

      expect(
        await client.checkConnection(),
        SupabaseConnectionStatus.apiReachable,
      );
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/rest/v1/');
      expect(request.uri.hasQuery, isFalse);
      expect(request.uri.toString(), isNot(contains(key)));
      expect(request.headers.value('apikey'), key);
      expect(request.headers.value('Authorization'), isNull);
      expect(request.headers.value('accept'), 'application/openapi+json');
      expect(requestBodies, ['']);
    },
  );

  test('OpenAPI 3 metadata also confirms the API connection', () async {
    handler = (request) => respond(
      request,
      jsonEncode({...document, 'swagger': null, 'openapi': '3.0.3'}),
    );
    expect(
      await connection().checkConnection(),
      SupabaseConnectionStatus.apiReachable,
    );
  });

  test('401 and 503 stay failures without exposing response bodies', () async {
    for (final status in [401, 503]) {
      handler = (request) => respond(
        request,
        jsonEncode({'error': 'private-response $key'}),
        status: status,
      );
      await expectLater(
        connection().checkConnection(),
        throwsA(
          failure(SupabaseConnectionFailure.httpStatus)
              .having((error) => error.statusCode, 'HTTP status', status)
              .having(
                (error) => error.toString(),
                'redacted error',
                allOf(
                  isNot(contains(key)),
                  isNot(contains('private-response')),
                ),
              ),
        ),
      );
    }
  });

  test(
    'restricted metadata falls back to a zero-row PostgREST probe',
    () async {
      handler = (request) => request.uri.path == '/rest/v1/'
          ? respond(
              request,
              '{"message":"Secret API key required"}',
              status: 401,
            )
          : respond(
              request,
              jsonEncode({
                'code': 'PGRST205',
                'message':
                    'Could not find public.__safe_walk_connection_probe__',
              }),
              status: 404,
            );

      expect(
        await connection().checkConnection(),
        SupabaseConnectionStatus.postgrestReachable,
      );
      expect(requests, hasLength(2));
      final probe = requests.last;
      expect(probe.method, 'GET');
      expect(probe.uri.path, '/rest/v1/__safe_walk_connection_probe__');
      expect(probe.uri.queryParameters, {'select': '*', 'limit': '0'});
      expect(probe.headers.value('apikey'), key);
      expect(probe.headers.value('Authorization'), isNull);
      expect(probe.headers.value('accept'), 'application/json');
      expect(requestBodies, ['', '']);
    },
  );

  test(
    'fallback rejects unrelated 404s and never echoes their messages',
    () async {
      for (final body in [
        '<html>not found</html>',
        jsonEncode({
          'code': 'PGRST205',
          'message': 'private-response $key refers to another_table',
        }),
        jsonEncode({
          'code': 'OTHER',
          'message': 'private-response $key __safe_walk_connection_probe__',
        }),
      ]) {
        handler = (request) => request.uri.path == '/rest/v1/'
            ? respond(request, '{}', status: 401)
            : respond(request, body, status: 404);
        await expectLater(
          connection().checkConnection(),
          throwsA(
            failure(SupabaseConnectionFailure.invalidResponse).having(
              (error) => error.toString(),
              'redacted error',
              allOf(isNot(contains(key)), isNot(contains('private-response'))),
            ),
          ),
        );
      }
    },
  );

  test('404 at the initial API root does not trigger fallback', () async {
    handler = (request) => respond(
      request,
      '{"code":"PGRST205","message":"__safe_walk_connection_probe__"}',
      status: 404,
    );
    await expectLater(
      connection().checkConnection(),
      throwsA(failure(SupabaseConnectionFailure.httpStatus)),
    );
    expect(requests, hasLength(1));
  });

  test('HTML and JSON without an OpenAPI document are not success', () async {
    for (final body in [
      '<html>temporary unavailable</html>',
      '{"ok":true}',
      '[]',
      '{"swagger":"2.0","paths":{}}',
    ]) {
      handler = (request) => respond(request, body);
      await expectLater(
        connection().checkConnection(),
        throwsA(failure(SupabaseConnectionFailure.invalidResponse)),
      );
    }
  });

  test('redirect is rejected without forwarding the API key', () async {
    handler = (request) async {
      request.response.statusCode = HttpStatus.temporaryRedirect;
      request.response.headers.set('location', origin.resolve('/elsewhere'));
      await request.response.close();
    };
    await expectLater(
      connection().checkConnection(),
      throwsA(failure(SupabaseConnectionFailure.httpStatus)),
    );
    expect(requests, hasLength(1));
  });

  test('response size is bounded even for a chunked body', () async {
    handler = (request) async {
      request.response.headers.chunkedTransferEncoding = true;
      request.response.write('x' * 1024);
      await request.response.close();
    };
    await expectLater(
      connection(maxResponseBytes: 100).checkConnection(),
      throwsA(failure(SupabaseConnectionFailure.responseTooLarge)),
    );
  });

  test(
    'an unanswered request times out and can be retried explicitly',
    () async {
      final hold = Completer<void>();
      handler = (_) => hold.future;
      final client = connection(timeout: const Duration(milliseconds: 100));
      await expectLater(
        client.checkConnection(),
        throwsA(failure(SupabaseConnectionFailure.timeout)),
      );
      hold.complete();
      handler = (request) => respond(request, jsonEncode(document));
      expect(
        await client.checkConnection(),
        SupabaseConnectionStatus.apiReachable,
      );
    },
  );

  test('close aborts a running check and blocks later checks', () async {
    final arrived = Completer<void>();
    final hold = Completer<void>();
    handler = (_) {
      arrived.complete();
      return hold.future;
    };
    final client = connection();
    final pending = client.checkConnection();
    final expectation = expectLater(
      pending,
      throwsA(failure(SupabaseConnectionFailure.closed)),
    );
    await arrived.future;
    client.close();
    client.close();
    await expectation;
    hold.complete();
    await expectLater(
      client.checkConnection(),
      throwsA(failure(SupabaseConnectionFailure.closed)),
    );
    expect(requests, hasLength(1));
  });

  test(
    'nearby factory refuses anonymous access without sending any request',
    () async {
      handler = (request) => respond(request, '[]');
      final transport = SupabaseNearbyAlertTransport.fromConfig(config());
      try {
        await Future<void>.delayed(Duration.zero);
        expect(requests, isEmpty);
        await expectLater(
          transport.fetchPendingAlerts('artificial-helper'),
          throwsA(isA<NearbyAlertException>()),
        );
        expect(requests, isEmpty);
      } finally {
        transport.close();
        transport.close();
      }
      await expectLater(
        transport.fetchPendingAlerts('artificial-helper'),
        throwsA(isA<NearbyAlertException>()),
      );
      expect(requests, isEmpty);
    },
  );
}
