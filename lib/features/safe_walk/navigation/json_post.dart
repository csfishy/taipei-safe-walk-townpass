/// `postJsonText(url, body)`: HTTPS POST of a JSON body, returning the status
/// and response text. dart:io on phones; browser fetch on the local web preview.
library;

import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

export 'json_post_io.dart' if (dart.library.js_interop) 'json_post_web.dart';

/// The transport rechecks consent after connection setup, before writing a
/// location-bearing body. Cancellation must reach the underlying request.
typedef JsonPoster = Future<(int, String)> Function(
  Uri url,
  String body, {
  SafeWalkCancellation? cancellation,
  required bool Function() hasConsent,
});
