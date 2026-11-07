import 'dart:js_interop';

/// Browser fetch, only in the local preview built with
/// `--dart-define=SAFE_WALK_WEB_ROUTES=true`; otherwise unavailable.
Future<(int, String)> postJsonText(Uri url, String body) async {
  if (!const bool.fromEnvironment('SAFE_WALK_WEB_ROUTES') || url.scheme != 'https') {
    throw UnsupportedError('Web routing is only enabled in the local preview');
  }
  final init = <String, Object?>{
    'method': 'POST',
    'headers': {'Content-Type': 'application/json', 'Accept': 'application/json'},
    'body': body,
    'redirect': 'error',
  }.jsify()!;
  final response = await _fetch(url.toString().toJS, init).toDart.timeout(const Duration(seconds: 12));
  final text = (await response.text().toDart).toDart;
  return (response.status.toDartInt, text);
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, JSAny init);

extension type _Response._(JSObject _) implements JSObject {
  external JSNumber get status;
  external JSPromise<JSString> text();
}
