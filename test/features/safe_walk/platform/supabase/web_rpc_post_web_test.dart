@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/web_rpc_post.dart';
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

final class _Cancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

JSObject _done() => {'done': true}.jsify()! as JSObject;
JSObject _chunk(List<int> bytes) =>
    {'done': false, 'value': Uint8List.fromList(bytes).toJS}.jsify()!
        as JSObject;

JSObject _response(
  Future<JSObject> Function() read, {
  int status = 200,
  void Function()? release,
}) {
  final reader = {
    'read': (() => read().toJS).toJS,
    'releaseLock': (() => release?.call()).toJS,
  }.jsify()!;
  return {
        'status': status,
        'body': {'getReader': (() => reader).toJS},
      }.jsify()!
      as JSObject;
}

void main() {
  final url = Uri.parse('https://artificial.example/rest/v1/rpc/query');
  const body = '{"p_min_lat":25,"p_min_lng":121.5}';
  const headers = {'Content-Type': 'application/json'};
  late JSFunction savedFetch;
  late Future<JSObject> Function() respond;
  late List<_Init> requests;

  setUp(() {
    savedFetch = _fetch;
    requests = [];
    respond = () async => _response(() async => _done());
    _fetch = ((JSString _, JSObject init) {
      final request = _Init(init);
      expect(request.signal.aborted.toDart, isFalse);
      requests.add(request);
      return respond().toJS;
    }).toJS;
  });
  tearDown(() => _fetch = savedFetch);

  Matcher failure(WebRpcPostFailure value) => throwsA(
    isA<WebRpcPostException>().having(
      (error) => error.failure,
      'failure',
      value,
    ),
  );

  if (!const bool.fromEnvironment('SAFE_WALK_WEB_ROUTES')) {
    test('default web build never sends an RPC request', () async {
      await expectLater(
        webRpcPost(url, headers, body),
        failure(WebRpcPostFailure.unsupported),
      );
      expect(requests, isEmpty);
    });
    return;
  }

  test(
    'an already cancelled operation never passes its body to fetch',
    () async {
      await expectLater(
        webRpcPost(url, headers, body, cancellation: _Cancellation()..cancel()),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(requests, isEmpty);
    },
  );

  test('preview rejects insecure RPC URLs without calling fetch', () async {
    for (final uri in [
      Uri.parse('http://artificial.example/rpc'),
      Uri.parse('https://user@artificial.example/rpc'),
    ]) {
      await expectLater(
        webRpcPost(uri, headers, body),
        failure(WebRpcPostFailure.insecure),
      );
    }
    expect(requests, isEmpty);
  });

  test(
    'JSON/status are preserved; redirects and browser credentials are blocked',
    () async {
      var index = 0;
      respond = () async => _response(
        () async => index++ == 0 ? _chunk([123, 125]) : _done(),
        status: 400,
      );
      expect(await webRpcPost(url, headers, body), (400, '{}'));
      expect(requests.single.method.toDart, 'POST');
      expect(requests.single.body.toDart, body);
      expect(requests.single.redirect.toDart, 'error');
      expect(requests.single.credentials.toDart, 'omit');
      expect(requests.single.signal.aborted.toDart, isTrue);
    },
  );

  test(
    'header cancellation aborts only that request and leaves retry usable',
    () async {
      final delayedHeaders = Completer<JSObject>();
      final cancellation = _Cancellation();
      var lateBodyReads = 0;
      respond = () => delayedHeaders.future;
      final pending = webRpcPost(
        url,
        headers,
        body,
        cancellation: cancellation,
      );
      final expectation = expectLater(
        pending,
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(requests, hasLength(1));
      cancellation.cancel();
      await expectation;
      expect(requests.first.signal.aborted.toDart, isTrue);

      respond = () async => _response(() async => _done());
      expect(await webRpcPost(url, headers, body), (200, ''));
      expect(requests, hasLength(2));
      delayedHeaders.complete(
        _response(() async {
          lateBodyReads++;
          return _done();
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(lateBodyReads, 0);
    },
  );

  test('body cancellation aborts fetch and discards late bytes', () async {
    final cancellation = _Cancellation();
    final reading = Completer<void>();
    final bytes = Completer<JSObject>();
    var released = false;
    respond = () async => _response(() {
      reading.complete();
      return bytes.future;
    }, release: () => released = true);
    final pending = webRpcPost(url, headers, body, cancellation: cancellation);
    final expectation = expectLater(
      pending,
      throwsA(isA<SafeWalkCancelledException>()),
    );
    await reading.future;
    cancellation.cancel();
    await expectation;
    expect(requests.single.signal.aborted.toDart, isTrue);
    bytes.complete(_chunk([123, 125]));
    await Future<void>.delayed(Duration.zero);
    expect(released, isTrue);
    expect(requests, hasLength(1));
  });

  test(
    'timeout aborts stalled headers and never reads their late body',
    () async {
      final delayedHeaders = Completer<JSObject>();
      var bodyReads = 0;
      respond = () => delayedHeaders.future;
      await expectLater(
        webRpcPost(
          url,
          headers,
          body,
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(requests.single.signal.aborted.toDart, isTrue);
      delayedHeaders.complete(
        _response(() async {
          bodyReads++;
          return _done();
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bodyReads, 0);
    },
  );

  test('the same timeout also covers response-body consumption', () async {
    final bytes = Completer<JSObject>();
    respond = () async => _response(() => bytes.future);
    await expectLater(
      webRpcPost(url, headers, body, timeout: const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );
    expect(requests.single.signal.aborted.toDart, isTrue);
    bytes.complete(_done());
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'response limits abort the stream before accepting oversized content',
    () async {
      var index = 0;
      respond = () async =>
          _response(() async => index++ < 2 ? _chunk([1, 2, 3]) : _done());
      await expectLater(
        webRpcPost(url, headers, body, maxBytes: 4),
        failure(WebRpcPostFailure.tooLarge),
      );
      expect(requests.single.signal.aborted.toDart, isTrue);
      expect(index, 2);
    },
  );

  test('malformed UTF-8 fails without exposing the URL or RPC body', () async {
    var index = 0;
    respond = () async =>
        _response(() async => index++ == 0 ? _chunk([0xff]) : _done());
    await expectLater(
      webRpcPost(url, headers, body),
      throwsA(
        isA<WebRpcPostException>()
            .having(
              (error) => error.failure,
              'failure',
              WebRpcPostFailure.malformed,
            )
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains(body)),
            )
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains(url.host)),
            ),
      ),
    );
    expect(requests.single.signal.aborted.toDart, isTrue);
  });
}
