import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// Browser fetch, only in the local preview built with
/// `--dart-define=SAFE_WALK_WEB_ROUTES=true`; otherwise unavailable.
Future<(int, String)> postJsonText(
  Uri url,
  String body, {
  SafeWalkCancellation? cancellation,
  required bool Function() hasConsent,
  Duration timeout = const Duration(seconds: 12),
  int maxBytes = 2 * 1024 * 1024,
}) async {
  if (!const bool.fromEnvironment('SAFE_WALK_WEB_ROUTES')) {
    throw const JsonTransportException(TransportFailure.unsupported);
  }
  if (url.scheme != 'https') {
    throw const JsonTransportException(TransportFailure.insecure);
  }
  var finished = false;
  void requireActive() {
    if (finished) throw const JsonTransportException(TransportFailure.timeout);
    cancellation?.throwIfCancelled();
    if (!hasConsent()) {
      throw const JsonTransportException(TransportFailure.unsupported);
    }
  }

  requireActive();
  final controller = _AbortController();
  final cancelled = Completer<(int, String)>();
  if (cancellation != null) {
    unawaited(
      cancellation.whenCancelled.then((_) {
        if (finished) return;
        controller.abort();
        cancelled.completeError(const SafeWalkCancelledException());
      }),
    );
  }

  Future<(int, String)> exchange() async {
    requireActive();
    final init = <String, Object?>{
      'method': 'POST',
      'headers': {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      'body': body,
      'redirect': 'error',
      'credentials': 'omit',
      'signal': controller.signal,
    }.jsify()!;
    final response = await _fetch(url.toString().toJS, init).toDart;
    requireActive();
    final bytes = BytesBuilder(copy: false);
    final reader = response.body?.getReader();
    if (reader != null) {
      try {
        while (true) {
          final chunk = await reader.read().toDart;
          requireActive();
          if (chunk.done.toDart) break;
          final value = chunk.value?.toDart;
          if (value == null) {
            throw const JsonTransportException(TransportFailure.malformed);
          }
          if (bytes.length + value.length > maxBytes) {
            throw const JsonTransportException(TransportFailure.tooLarge);
          }
          bytes.add(value);
        }
      } finally {
        reader.releaseLock();
      }
    }
    requireActive();
    return (response.status.toDartInt, utf8.decode(bytes.takeBytes()));
  }

  try {
    return await Future.any([
      exchange(),
      if (cancellation != null) cancelled.future,
    ]).timeout(timeout);
  } on SafeWalkCancelledException {
    rethrow;
  } on TimeoutException {
    throw const JsonTransportException(TransportFailure.timeout);
  } on JsonTransportException {
    rethrow;
  } on FormatException {
    throw const JsonTransportException(TransportFailure.malformed);
  } catch (_) {
    cancellation?.throwIfCancelled();
    throw const JsonTransportException(TransportFailure.network);
  } finally {
    finished = true;
    // Also aborts an unread/oversized body and a request whose deadline elapsed.
    controller.abort();
  }
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, JSAny init);

extension type _Response._(JSObject _) implements JSObject {
  external JSNumber get status;
  external _ReadableStream? get body;
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _StreamReader getReader();
}

extension type _StreamReader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
  external void releaseLock();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external JSBoolean get done;
  external JSUint8Array? get value;
}

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}
