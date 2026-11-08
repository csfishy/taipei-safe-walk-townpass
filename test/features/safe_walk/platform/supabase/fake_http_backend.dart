import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef FakeCall = ({Uri url, String body, Map<String, String> headers});
typedef FakeAnswer = ({int status, String body});

/// Synthetic HTTP only: answers by the handler, records every request, and never
/// opens a socket. A handler that throws simulates a network failure; one that
/// never completes simulates a stalled connection.
class FakeHttpBackend {
  FakeHttpBackend(this.handler);

  final FutureOr<FakeAnswer> Function(FakeCall call) handler;
  final calls = <FakeCall>[];

  /// A fresh client per call, like the real clients create.
  HttpClient client() => _Client(this);

  Iterable<FakeCall> callsTo(String path) =>
      calls.where((c) => c.url.path == path);
}

class _Client implements HttpClient {
  _Client(this._backend);
  final FakeHttpBackend _backend;
  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _Request(url, _backend);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this._url, this._backend) : headers = _Headers();
  final Uri _url;
  final FakeHttpBackend _backend;
  final _body = <int>[];
  @override
  bool followRedirects = true;
  @override
  final _Headers headers;
  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  Future<HttpClientResponse> close() async {
    final call = (
      url: _url,
      body: utf8.decode(_body),
      headers: Map<String, String>.of(headers.values),
    );
    _backend.calls.add(call);
    final answer = await _backend.handler(call);
    return _Response(answer.status, answer.body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value.toString();
  @override
  set contentType(ContentType? type) =>
      values['content-type'] = type.toString();
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

/// A GoTrue-shaped session body.
String authSessionJson({
  String access = 'aaaa.bbbb.cccc',
  String refresh = 'refresh-1',
  int? expiresAt,
  int? expiresIn,
}) => jsonEncode({
  'access_token': access,
  'token_type': 'bearer',
  'refresh_token': refresh,
  'expires_at': ?expiresAt,
  'expires_in': ?expiresIn,
  'user': {'id': '00000000-0000-4000-8000-000000000001', 'is_anonymous': true},
});
