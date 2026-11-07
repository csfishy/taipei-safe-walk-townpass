import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Synthetic HTTP only. A connection may complete after close to exercise the
/// caller's late-write fence without DNS, TLS, sockets or a real recipient.
class FakeRpcHttpClient implements HttpClient {
  final arrived = Completer<void>();
  final request = FakeRpcRequest();
  Future<HttpClientRequest>? connection;
  int calls = 0;
  int closes = 0;
  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    if (closes > 0) throw StateError('Closed synthetic client was reused');
    calls++;
    arrived.complete();
    return connection ?? Future.value(request);
  }

  @override
  void close({bool force = false}) => closes++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRpcRequest implements HttpClientRequest {
  final written = <int>[];
  final closed = Completer<void>();
  int closeCalls = 0;
  Future<HttpClientResponse> response = Future.value(
    FakeRpcResponse.text('{}'),
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

class FakeRpcResponse extends Stream<List<int>> implements HttpClientResponse {
  FakeRpcResponse(this.stream);
  FakeRpcResponse.text(String body) : stream = Stream.value(utf8.encode(body));
  final Stream<List<int>> stream;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => -1;
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
