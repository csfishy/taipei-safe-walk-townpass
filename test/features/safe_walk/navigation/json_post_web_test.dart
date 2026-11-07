@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/json_post_web.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

@JS('globalThis.fetch')
external JSFunction get _fetch;
@JS('globalThis.fetch')
external set _fetch(JSFunction value);

extension type _Init(JSObject _) implements JSObject {
  external JSString get method;
  external JSString get body;
  external JSString get redirect;
  external JSString get credentials;
  external _Signal get signal;
}

extension type _Signal(JSObject _) implements JSObject {
  external JSBoolean get aborted;
}

JSObject _done() => {'done': true}.jsify()! as JSObject;
JSObject _chunk(List<int> bytes) =>
    {'done': false, 'value': Uint8List.fromList(bytes).toJS}.jsify()!
        as JSObject;

JSObject _response(Future<JSObject> Function() read, {int status = 200}) {
  final reader = {
    'read': (() => read().toJS).toJS,
    'releaseLock': (() {}).toJS,
  }.jsify()!;
  return {
        'status': status,
        'body': {'getReader': (() => reader).toJS},
      }.jsify()!
      as JSObject;
}

void main() {
  final url = Uri.parse('https://artificial.example/route');
  const body = '{"locations":[{"lat":25,"lon":121.5}]}';
  late JSFunction savedFetch;
  late Future<JSObject> Function() respond;
  _Init? request;
  var requests = 0;

  setUp(() {
    savedFetch = _fetch;
    requests = 0;
    request = null;
    respond = () async => _response(() async => _done());
    _fetch = ((JSString url, JSObject init) {
      requests++;
      request = _Init(init);
      return respond().toJS;
    }).toJS;
  });
  tearDown(() => _fetch = savedFetch);

  Matcher failure(TransportFailure value) => throwsA(
    isA<JsonTransportException>().having(
      (error) => error.failure,
      'failure',
      value,
    ),
  );

  if (!const bool.fromEnvironment('SAFE_WALK_WEB_ROUTES')) {
    test('default web build cannot send a routing POST', () async {
      await expectLater(
        postJsonText(url, body, hasConsent: () => true),
        failure(TransportFailure.unsupported),
      );
      expect(requests, 0);
    });
    return;
  }

  test(
    'preview POST still needs live consent and an uncancelled operation',
    () async {
      await expectLater(
        postJsonText(url, body, hasConsent: () => false),
        failure(TransportFailure.unsupported),
      );
      await expectLater(
        postJsonText(
          url,
          body,
          hasConsent: () => true,
          cancellation: ManualCancellation()..cancel(),
        ),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(requests, 0);
    },
  );

  test('preview POST rejects redirects, omits credentials, and preserves JSON/status', () async {
    var index = 0;
    respond = () async => _response(
      () async => index++ == 0 ? _chunk([123, 125]) : _done(),
      status: 400,
    );
    expect(await postJsonText(url, body, hasConsent: () => true), (400, '{}'));
    expect(request!.method.toDart, 'POST');
    expect(request!.body.toDart, body);
    expect(request!.redirect.toDart, 'error');
    expect(request!.credentials.toDart, 'omit');
    expect(request!.signal.aborted.toDart, isTrue);
  });

  test(
    'cancellation aborts a stalled body and discards its late bytes',
    () async {
      final cancellation = ManualCancellation();
      final reading = Completer<void>();
      final bytes = Completer<JSObject>();
      respond = () async => _response(() {
        reading.complete();
        return bytes.future;
      });
      final pending = postJsonText(
        url,
        body,
        hasConsent: () => true,
        cancellation: cancellation,
      );
      final expectation = expectLater(
        pending,
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await reading.future;
      cancellation.cancel();
      await expectation;
      expect(request!.signal.aborted.toDart, isTrue);
      bytes.complete(_done());
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
    },
  );

  test('one deadline includes response-body consumption', () async {
    final bytes = Completer<JSObject>();
    respond = () async => _response(() => bytes.future);
    await expectLater(
      postJsonText(
        url,
        body,
        hasConsent: () => true,
        timeout: const Duration(milliseconds: 30),
      ),
      failure(TransportFailure.timeout),
    );
    expect(request!.signal.aborted.toDart, isTrue);
    bytes.complete(_done());
    await Future<void>.delayed(Duration.zero);
  });

  test('streamed bytes cannot exceed the response cap', () async {
    var index = 0;
    respond = () async =>
        _response(() async => index++ < 2 ? _chunk([1, 2, 3]) : _done());
    await expectLater(
      postJsonText(url, body, hasConsent: () => true, maxBytes: 4),
      failure(TransportFailure.tooLarge),
    );
    expect(request!.signal.aborted.toDart, isTrue);
    expect(index, 2);
  });
}
