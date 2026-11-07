/// `createDefaultJsonTransport()`: the `dart:io` client on Android/iOS, an
/// always-unavailable transport where `dart:io` does not exist (web).
library;

export 'unsupported_json_transport.dart'
    if (dart.library.io) 'io_json_transport.dart'
    show createDefaultJsonTransport;
