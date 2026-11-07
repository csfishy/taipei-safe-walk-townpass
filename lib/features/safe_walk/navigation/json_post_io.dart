import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// HTTPS only, no redirects, 12 s timeout, 2 MB cap. URL and body are never logged.
Future<(int, String)> postJsonText(
  Uri url,
  String body, {
  SafeWalkCancellation? cancellation,
  required bool Function() hasConsent,
  Duration timeout = const Duration(seconds: 12),
  int maxBytes = 2 * 1024 * 1024,
  HttpClient? client,
  bool allowInsecureLocalhost = false,
}) async {
  final localTest =
      allowInsecureLocalhost &&
      url.scheme == 'http' &&
      {'localhost', '127.0.0.1', '::1'}.contains(url.host);
  if (url.scheme != 'https' && !localTest) {
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
  final activeClient = client ?? HttpClient();
  activeClient.connectionTimeout = timeout;
  final cancelled = Completer<(int, String)>();
  if (cancellation != null) {
    unawaited(
      cancellation.whenCancelled.then((_) {
        if (finished) return;
        activeClient.close(force: true);
        cancelled.completeError(const SafeWalkCancelledException());
      }),
    );
  }

  Future<(int, String)> exchange() async {
    final request = await activeClient.postUrl(url);
    // DNS/TLS/connection setup is asynchronous. Revocation during that await
    // must stop the body before any coordinates are written to the request.
    requireActive();
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.add(utf8.encode(body));
    final response = await request.close();
    requireActive();
    if (response.contentLength > maxBytes) {
      throw const JsonTransportException(TransportFailure.tooLarge);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      requireActive();
      if (bytes.length + chunk.length > maxBytes) {
        throw const JsonTransportException(TransportFailure.tooLarge);
      }
      bytes.add(chunk);
    }
    requireActive();
    return (response.statusCode, utf8.decode(bytes.takeBytes()));
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
    activeClient.close(force: true);
  }
}
