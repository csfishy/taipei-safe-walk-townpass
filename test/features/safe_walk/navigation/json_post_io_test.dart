@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/json_post_io.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

void main() {
  final url = Uri.parse('https://artificial.example/route');
  const body = '{"locations":[{"lat":25,"lon":121.5}]}';
  Matcher failure(TransportFailure value) => throwsA(
    isA<JsonTransportException>().having(
      (error) => error.failure,
      'failure',
      value,
    ),
  );

  test('no consent or pre-cancellation creates no request', () async {
    final client = _Client();
    await expectLater(
      postJsonText(url, body, client: client, hasConsent: () => false),
      failure(TransportFailure.unsupported),
    );
    await expectLater(
      postJsonText(
        url,
        body,
        client: client,
        hasConsent: () => true,
        cancellation: ManualCancellation()..cancel(),
      ),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    expect(client.calls, 0);
  });

  test(
    'consent revoked during connection setup prevents writing coordinates',
    () async {
      var consent = true;
      final connected = Completer<HttpClientRequest>();
      final client = _Client()..connection = connected.future;
      final pending = postJsonText(
        url,
        body,
        client: client,
        hasConsent: () => consent,
      );
      final expectation = expectLater(
        pending,
        failure(TransportFailure.unsupported),
      );
      await client.arrived.future;
      consent = false;
      connected.complete(client.request);
      await expectation;
      expect(client.request.written, isEmpty);
      expect(client.request.closeCalls, 0);
      expect(client.closes, greaterThan(0));
    },
  );

  test('cancel during connection setup aborts promptly and rejects a late connection', () async {
    final cancellation = ManualCancellation();
    final connected = Completer<HttpClientRequest>();
    final client = _Client()..connection = connected.future;
    final pending = postJsonText(
      url,
      body,
      client: client,
      hasConsent: () => true,
      cancellation: cancellation,
    );
    final expectation = expectLater(
      pending,
      throwsA(isA<SafeWalkCancelledException>()),
    );
    await client.arrived.future;
    cancellation.cancel();
    await expectation;
    connected.complete(client.request);
    await Future<void>.delayed(Duration.zero);
    expect(client.request.written, isEmpty);
    expect(client.closes, greaterThan(0));
  });

  test('deadline covers connection setup and fences a late request', () async {
    final connected = Completer<HttpClientRequest>();
    final client = _Client()..connection = connected.future;
    await expectLater(
      postJsonText(
        url,
        body,
        client: client,
        hasConsent: () => true,
        timeout: const Duration(milliseconds: 20),
      ),
      failure(TransportFailure.timeout),
    );
    connected.complete(client.request);
    await Future<void>.delayed(Duration.zero);
    expect(client.request.written, isEmpty);
    expect(client.closes, greaterThan(0));
  });

  test('POST preserves JSON/status without following redirects', () async {
    final client = _Client();
    client.request.response = Future.value(
      _Response(
        Stream.value(utf8.encode('{"error_code":442}')),
        statusCode: 400,
      ),
    );
    final result = await postJsonText(
      url,
      body,
      client: client,
      hasConsent: () => true,
    );
    expect(result, (400, '{"error_code":442}'));
    expect(utf8.decode(client.request.written), body);
    expect(client.request.followRedirects, isFalse);
  });

  test('chunked response is bounded before buffering beyond the cap', () async {
    final client = _Client();
    client.request.response = Future.value(
      _Response(
        Stream.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
        ]),
      ),
    );
    await expectLater(
      postJsonText(
        url,
        body,
        client: client,
        hasConsent: () => true,
        maxBytes: 4,
      ),
      failure(TransportFailure.tooLarge),
    );
    expect(client.closes, greaterThan(0));
  });

  test(
    'an advertised oversized response is rejected before reading it',
    () async {
      final client = _Client();
      client.request.response = Future.value(
        _Response(const Stream.empty(), contentLength: 100),
      );
      await expectLater(
        postJsonText(
          url,
          body,
          client: client,
          hasConsent: () => true,
          maxBytes: 4,
        ),
        failure(TransportFailure.tooLarge),
      );
    },
  );

  test('deadline includes a stalled response body', () async {
    final bytes = StreamController<List<int>>();
    addTearDown(bytes.close);
    final client = _Client();
    client.request.response = Future.value(_Response(bytes.stream));
    await expectLater(
      postJsonText(
        url,
        body,
        client: client,
        hasConsent: () => true,
        timeout: const Duration(milliseconds: 20),
      ),
      failure(TransportFailure.timeout),
    );
    expect(client.closes, greaterThan(0));
  });

  test(
    'cancel while reading the body reports cancellation and closes the client',
    () async {
      final listening = Completer<void>();
      final bytes = StreamController<List<int>>(onListen: listening.complete);
      addTearDown(bytes.close);
      final cancellation = ManualCancellation();
      final client = _Client();
      client.request.response = Future.value(_Response(bytes.stream));
      final pending = postJsonText(
        url,
        body,
        client: client,
        hasConsent: () => true,
        cancellation: cancellation,
      );
      final expectation = expectLater(
        pending,
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await listening.future;
      cancellation.cancel();
      await expectation;
      expect(client.closes, greaterThan(0));
    },
  );

  test(
    'insecure remote URL cannot be enabled by the localhost test option',
    () async {
      final client = _Client();
      await expectLater(
        postJsonText(
          Uri.parse('http://artificial.example/route'),
          body,
          client: client,
          hasConsent: () => true,
          allowInsecureLocalhost: true,
        ),
        failure(TransportFailure.insecure),
      );
      expect(client.calls, 0);
    },
  );
}

class _Client implements HttpClient {
  final arrived = Completer<void>();
  final request = _Request();
  Future<HttpClientRequest>? connection;
  int calls = 0;
  int closes = 0;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    calls++;
    arrived.complete();
    return connection ?? Future.value(request);
  }

  @override
  void close({bool force = false}) => closes++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  final written = <int>[];
  final closed = Completer<void>();
  int closeCalls = 0;
  Future<HttpClientResponse> response = Future.value(
    _Response(const Stream.empty()),
  );
  @override
  bool followRedirects = true;
  @override
  final HttpHeaders headers = _Headers();
  @override
  void add(List<int> data) => written.addAll(data);
  @override
  Future<HttpClientResponse> close() {
    closeCalls++;
    closed.complete();
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.stream, {this.statusCode = 200, this.contentLength = -1});
  final Stream<List<int>> stream;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
