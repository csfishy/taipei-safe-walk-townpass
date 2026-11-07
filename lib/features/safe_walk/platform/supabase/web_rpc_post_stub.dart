/// Non-web builds use the dart:io `SupabaseRpcClient`; this is never called.
Future<(int, String)> webRpcPost(Uri url, Map<String, String> headers, String body) =>
    Future.error(UnsupportedError('webRpcPost is web-only'));
