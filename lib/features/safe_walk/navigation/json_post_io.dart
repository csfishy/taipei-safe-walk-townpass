import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// HTTPS only, no redirects, 12 s timeout, 2 MB cap. URL and body are never logged.
Future<(int, String)> postJsonText(Uri url, String body) async {
  if (url.scheme != 'https') throw const SocketException('HTTPS only');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.postUrl(url);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.add(utf8.encode(body));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 12))) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) throw const SocketException('Response too large');
    }
    return (response.statusCode, utf8.decode(bytes));
  } finally {
    client.close(force: true);
  }
}
