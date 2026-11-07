import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/io_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// These talk to a local HttpServer on 127.0.0.1, never to the internet.
void main() {
  late HttpServer server;
  late Uri base;
  late Future<void> Function(HttpRequest request) handler;
  final seen = <HttpRequest>[];
  final bodies = <String>[];

  setUp(() async {
    seen.clear();
    bodies.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/');
    server.listen((request) async {
      seen.add(request);
      bodies.add(await utf8.decoder.bind(request).join());
      await handler(request);
    });
  });

  tearDown(() => server.close(force: true));

  IoJsonTransport transport({
    Duration timeout = const Duration(seconds: 5),
    int maxBytes = 1024 * 1024,
  }) => IoJsonTransport(
    allowInsecureHttp: true,
    timeout: timeout,
    maxBytes: maxBytes,
    userAgent: 'test-agent',
  );

  Future<void> respond(
    HttpRequest request,
    String body, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.write(body);
    await request.response.close();
  }

  test(
    'GET returns decoded JSON and sends the agent and accept headers',
    () async {
      handler = (r) => respond(r, jsonEncode({'ok': true, 'n': 3}));

      final json = await transport().getJson(base.replace(path: '/route'));

      expect(json, {'ok': true, 'n': 3});
      expect(seen.single.method, 'GET');
      expect(seen.single.headers.value('user-agent'), 'test-agent');
      expect(seen.single.headers.value('accept'), 'application/json');
    },
  );

  test('POST sends a form-encoded body', () async {
    handler = (r) => respond(r, '{"elements":[]}');

    final json = await transport().postFormJson(base, {
      'data': '[out:json];a b',
    });

    expect(json, {'elements': <Object?>[]});
    expect(seen.single.method, 'POST');
    expect(
      seen.single.headers.contentType?.mimeType,
      'application/x-www-form-urlencoded',
    );
    expect(Uri.splitQueryString(bodies.single), {'data': '[out:json];a b'});
  });

  test('a non-200 status fails without returning the body', () async {
    handler = (r) => respond(r, '{"secret":1}', status: 503);

    await expectLater(
      transport().getJson(base),
      throwsA(
        isA<JsonTransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.httpStatus,
        ),
      ),
    );
  });

  test('redirects are not followed', () async {
    handler = (r) async {
      r.response.statusCode = 302;
      r.response.headers.set('location', 'http://127.0.0.1:1/elsewhere');
      await r.response.close();
    };

    await expectLater(
      transport().getJson(base),
      throwsA(
        isA<JsonTransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.httpStatus,
        ),
      ),
    );
    expect(seen, hasLength(1));
  });

  test('malformed JSON is reported as malformed', () async {
    handler = (r) => respond(r, '<html>not json</html>');

    await expectLater(
      transport().getJson(base),
      throwsA(
        isA<JsonTransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.malformed,
        ),
      ),
    );
  });

  test('a response over the size limit is rejected', () async {
    handler = (r) => respond(r, jsonEncode({'pad': 'x' * 5000}));

    await expectLater(
      transport(maxBytes: 100).getJson(base),
      throwsA(
        isA<JsonTransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.tooLarge,
        ),
      ),
    );
  });

  test(
    'a chunked response over the limit is rejected while streaming',
    () async {
      handler = (r) async {
        r.response.headers.chunkedTransferEncoding = true;
        for (var i = 0; i < 20; i++) {
          r.response.write('x' * 50);
          await r.response.flush();
        }
        await r.response.close();
      };

      await expectLater(
        transport(maxBytes: 200).getJson(base),
        throwsA(
          isA<JsonTransportException>().having(
            (e) => e.failure,
            'failure',
            TransportFailure.tooLarge,
          ),
        ),
      );
    },
  );

  test('a server that never answers times out', () async {
    final hold = Completer<void>();
    handler = (r) => hold.future;

    await expectLater(
      transport(timeout: const Duration(milliseconds: 300)).getJson(base),
      throwsA(
        isA<JsonTransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.timeout,
        ),
      ),
    );
    hold.complete();
  });

  test(
    'cancelling mid-flight closes the request and throws cancelled',
    () async {
      final hold = Completer<void>();
      handler = (r) => hold.future;
      final cancellation = ManualCancellation();

      final pending = transport().getJson(base, cancellation: cancellation);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      cancellation.cancel();

      await expectLater(pending, throwsA(isA<SafeWalkCancelledException>()));
      hold.complete();
    },
  );

  test('an already cancelled token never touches the network', () async {
    handler = (r) => respond(r, '{}');
    final cancellation = ManualCancellation()..cancel();

    await expectLater(
      transport().getJson(base, cancellation: cancellation),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    expect(seen, isEmpty);
  });

  test('plain http is refused by default', () async {
    handler = (r) => respond(r, '{}');

    await expectLater(
      IoJsonTransport().getJson(base),
      throwsA(
        isA<JsonTransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.insecure,
        ),
      ),
    );
    expect(seen, isEmpty);
  });

  test(
    'an unreachable host is a network failure without leaking the URL',
    () async {
      final port = server.port;
      await server.close(force: true);

      await expectLater(
        transport().getJson(Uri.parse('http://127.0.0.1:$port/?lat=25.0478')),
        throwsA(
          isA<JsonTransportException>()
              .having((e) => e.failure, 'failure', TransportFailure.network)
              .having((e) => e.toString(), 'text', isNot(contains('25.0478'))),
        ),
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    },
  );
}
