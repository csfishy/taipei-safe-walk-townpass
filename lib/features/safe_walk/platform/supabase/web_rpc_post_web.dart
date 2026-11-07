import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/platform/supabase/web_rpc_post_types.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// Browser-only preview of the reviewed read-only RPC. The caller owns consent
/// and cancels this operation when consent/navigation/lifecycle changes.
/// Default builds cannot fetch, even if the public configuration is present.
Future<(int, String)> webRpcPost(
  Uri url,
  Map<String, String> headers,
  String body, {
  SafeWalkCancellation? cancellation,
  Duration timeout = const Duration(seconds: 12),
  int maxBytes = 2 * 1024 * 1024,
}) async {
  if (!const bool.fromEnvironment('SAFE_WALK_WEB_ROUTES')) {
    throw const WebRpcPostException(WebRpcPostFailure.unsupported);
  }
  if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
    throw const WebRpcPostException(WebRpcPostFailure.insecure);
  }
  if (timeout <= Duration.zero || maxBytes < 1) {
    throw ArgumentError('A positive timeout and response limit are required');
  }
  var finished = false;
  void requireActive() {
    cancellation?.throwIfCancelled();
    if (finished) throw TimeoutException('Web RPC deadline elapsed');
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
      'headers': headers,
      'body': body,
      'redirect': 'error',
      'credentials': 'omit',
      'signal': controller.signal,
    }.jsify()!;
    requireActive();
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
            throw const WebRpcPostException(WebRpcPostFailure.malformed);
          }
          if (bytes.length + value.length > maxBytes) {
            throw const WebRpcPostException(WebRpcPostFailure.tooLarge);
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
    final result = await Future.any([
      exchange(),
      if (cancellation != null) cancelled.future,
    ]).timeout(timeout);
    requireActive();
    return result;
  } on SafeWalkCancelledException {
    rethrow;
  } on TimeoutException {
    cancellation?.throwIfCancelled();
    rethrow;
  } on WebRpcPostException {
    rethrow;
  } on FormatException {
    throw const WebRpcPostException(WebRpcPostFailure.malformed);
  } catch (_) {
    cancellation?.throwIfCancelled();
    throw const WebRpcPostException(WebRpcPostFailure.network);
  } finally {
    finished = true;
    // Includes stalled headers/body, response limits, and a total deadline.
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
