import 'dart:js_interop';

/// POSTs JSON with the browser's fetch (local web preview of the Supabase RPC).
/// No redirects are followed; the body and URL are never logged.
Future<(int, String)> webRpcPost(Uri url, Map<String, String> headers, String body) async {
  final init = <String, Object?>{'method': 'POST', 'headers': headers, 'body': body, 'redirect': 'error'}.jsify()!;
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
