import 'dart:convert';

import 'package:get/get.dart';

/// Default [ViolentCrimeTextFetcher] over the official app's existing GetX
/// dependency (no new package).
///
/// The statistics CSV is UTF-8 but is served as `application/octet-stream`
/// without a charset, so a client may decode it as Latin-1. The body is
/// re-decoded as UTF-8 when that is lossless; if the text is still wrong the
/// repository's header check reports the source as unavailable.
///
/// Not verified on Flutter **web**: browser CORS rules for data.taipei and
/// tsis.dbas.gov.taipei may block the request, which then surfaces as an
/// unavailable source rather than data.
Future<String> getConnectTextFetcher(Uri uri) async {
  final connect = GetConnect(timeout: const Duration(seconds: 60));
  try {
    final response = await connect.get<String>(
      uri.toString(),
      decoder: (data) => data is String ? data : jsonEncode(data),
    );
    final status = response.statusCode;
    if (response.hasError || status == null || status < 200 || status >= 300) {
      throw StateError('HTTP ${status ?? 'no status'}');
    }
    final text = response.bodyString ?? response.body;
    if (text == null) throw StateError('empty response');
    return redecodeLatin1AsUtf8(text);
  } finally {
    connect.dispose();
  }
}

/// Undoes a Latin-1 decode of UTF-8 bytes. Text that cannot have come from a
/// Latin-1 decode, or whose bytes are not UTF-8, is returned unchanged.
String redecodeLatin1AsUtf8(String text) {
  try {
    return utf8.decode(latin1.encode(text));
  } on ArgumentError {
    return text; // contains characters above U+00FF: already decoded
  } on FormatException {
    return text; // the bytes are not UTF-8
  }
}
