import 'dart:convert';

import 'package:get/get.dart';

/// Default [AedJsonFetcher] over the official app's existing GetX dependency.
///
/// Works on Android/iOS. A Flutter **web** build cannot use it: data.taipei
/// only allows browser reads from https://data.taipei (CORS), so the request
/// fails and the repository reports the source as unavailable.
Future<Object?> getConnectAedFetcher(Uri uri) async {
  final connect = GetConnect(timeout: const Duration(seconds: 60));
  try {
    final response = await connect.get<Object?>(
      uri.toString(),
      headers: const {'Accept': 'application/json'},
      decoder: (data) => data,
    );
    final status = response.statusCode;
    if (response.hasError || status == null || status < 200 || status >= 300) {
      throw StateError('HTTP ${status ?? 'no status'}');
    }
    final text = response.bodyString;
    if (text != null && text.isNotEmpty) return jsonDecode(text);
    return response.body;
  } finally {
    connect.dispose();
  }
}
