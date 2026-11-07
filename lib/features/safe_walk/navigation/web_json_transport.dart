import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/unsupported_json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// Browser `fetch` client for the local web preview only. Built in when the app
/// is compiled with `--dart-define=SAFE_WALK_WEB_ROUTES=true`; otherwise the
/// web build keeps the always-unavailable transport. HTTPS only, 12 s timeout,
/// 2 MB cap; URLs and bodies are never logged.
final class WebJsonTransport implements JsonTransport {
  const WebJsonTransport({
    this.timeout = const Duration(seconds: 12),
    this.maxBytes = 2 * 1024 * 1024,
  });

  final Duration timeout;
  final int maxBytes;

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) async {
    if (url.scheme != 'https') {
      throw const JsonTransportException(TransportFailure.insecure);
    }
    cancellation?.throwIfCancelled();
    return _decode(
      () => _fetch(url.toString().toJS).toDart.timeout(timeout),
      cancellation,
    );
  }

  /// Form POST (Overpass). A urlencoded body is a CORS "simple" request, so
  /// the browser sends no preflight.
  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) async {
    if (url.scheme != 'https') {
      throw const JsonTransportException(TransportFailure.insecure);
    }
    cancellation?.throwIfCancelled();
    final init = <String, Object?>{
      'method': 'POST',
      'headers': {'Content-Type': 'application/x-www-form-urlencoded'},
      'body': Uri(queryParameters: form).query,
      'credentials': 'omit',
    }.jsify()!;
    return _decode(
      () => _fetchWith(url.toString().toJS, init).toDart.timeout(timeout),
      cancellation,
    );
  }

  Future<Object?> _decode(
    Future<_Response> Function() send,
    SafeWalkCancellation? cancellation,
  ) async {
    final _Response response;
    try {
      response = await send();
    } catch (error) {
      debugPrint('[safe-walk web transport] ${error.runtimeType}');
      throw JsonTransportException(
        error is TimeoutException
            ? TransportFailure.timeout
            : TransportFailure.network,
      );
    }
    cancellation?.throwIfCancelled();
    final int status;
    final String text;
    try {
      status = response.status.toDartInt;
      text = (await response.text().toDart).toDart;
    } catch (error) {
      debugPrint('[safe-walk web transport] read ${error.runtimeType}');
      throw const JsonTransportException(TransportFailure.network);
    }
    cancellation?.throwIfCancelled();
    if (status != 200) {
      throw const JsonTransportException(TransportFailure.httpStatus);
    }
    if (text.length > maxBytes) {
      throw const JsonTransportException(TransportFailure.tooLarge);
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const JsonTransportException(TransportFailure.malformed);
    }
  }
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

@JS('fetch')
external JSPromise<_Response> _fetchWith(JSString url, JSAny init);

extension type _Response._(JSObject _) implements JSObject {
  external JSNumber get status;
  external JSPromise<JSString> text();
}

JsonTransport createDefaultJsonTransport() =>
    const bool.fromEnvironment('SAFE_WALK_WEB_ROUTES')
    ? const WebJsonTransport()
    : const UnsupportedJsonTransport();
