/// `createDefaultJsonTransport()`: the `dart:io` client on Android/iOS, an
/// always-unavailable transport on web unless the local preview is built with
/// `--dart-define=SAFE_WALK_WEB_ROUTES=true` (browser fetch).
library;

export 'unsupported_json_transport.dart'
    if (dart.library.io) 'io_json_transport.dart'
    if (dart.library.js_interop) 'web_json_transport.dart'
    show createDefaultJsonTransport;
