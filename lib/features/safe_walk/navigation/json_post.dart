/// `postJsonText(url, body)`: HTTPS POST of a JSON body, returning the status
/// and response text. dart:io on phones; browser fetch on the local web preview.
library;

export 'json_post_io.dart' if (dart.library.js_interop) 'json_post_web.dart';
