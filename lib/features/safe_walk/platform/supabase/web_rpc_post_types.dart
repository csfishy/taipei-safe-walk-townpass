enum WebRpcPostFailure { unsupported, insecure, tooLarge, malformed, network }

/// A fixed failure category; never includes a URL, key, body or coordinates.
final class WebRpcPostException implements Exception {
  const WebRpcPostException(this.failure);
  final WebRpcPostFailure failure;

  @override
  String toString() => 'Web RPC failed: ${failure.name}';
}
