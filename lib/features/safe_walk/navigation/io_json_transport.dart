import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// `dart:io` transport for Android and iOS. HTTPS only, no redirects, a
/// timeout, a response size cap, and cancellation that closes the socket.
final class IoJsonTransport implements JsonTransport {
  IoJsonTransport({
    this.timeout = const Duration(seconds: 12),
    this.maxBytes = 2 * 1024 * 1024,
    this.userAgent = 'TownPass-SafeWalk',
    this.allowInsecureHttp = false,
  });

  final Duration timeout;
  final int maxBytes;
  final String userAgent;

  /// Only for tests against a local server.
  final bool allowInsecureHttp;

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) =>
      _send('GET', url, null, cancellation);

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) => _send('POST', url, Uri(queryParameters: form).query, cancellation);

  Future<Object?> _send(
    String method,
    Uri url,
    String? body,
    SafeWalkCancellation? cancellation,
  ) async {
    final secure = url.scheme == 'https';
    if (!secure && !(allowInsecureHttp && url.scheme == 'http')) {
      throw const JsonTransportException(TransportFailure.insecure);
    }
    cancellation?.throwIfCancelled();

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = userAgent;
    var cancelled = false;
    cancellation?.whenCancelled.then((_) {
      cancelled = true;
      client.close(force: true);
    });
    try {
      return await _exchange(client, method, url, body).timeout(timeout);
    } on TimeoutException {
      throw const JsonTransportException(TransportFailure.timeout);
    } on JsonTransportException {
      rethrow;
    } catch (_) {
      if (cancelled) throw const SafeWalkCancelledException();
      throw const JsonTransportException(TransportFailure.network);
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> _exchange(
    HttpClient client,
    String method,
    Uri url,
    String? body,
  ) async {
    final request = await client.openUrl(method, url);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(body);
    }
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw const JsonTransportException(TransportFailure.httpStatus);
    }
    if (response.contentLength > maxBytes) {
      throw const JsonTransportException(TransportFailure.tooLarge);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw const JsonTransportException(TransportFailure.tooLarge);
      }
    }
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw const JsonTransportException(TransportFailure.malformed);
    }
  }
}

JsonTransport createDefaultJsonTransport() => IoJsonTransport();
