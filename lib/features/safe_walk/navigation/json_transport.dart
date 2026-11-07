import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

enum TransportFailure {
  network,
  timeout,
  httpStatus,
  tooLarge,
  malformed,
  insecure,
  unsupported,
}

/// Carries no URL or body: both contain the user location.
final class JsonTransportException implements Exception {
  const JsonTransportException(this.failure);

  final TransportFailure failure;

  @override
  String toString() => 'JSON transport failed: ${failure.name}';
}

/// Minimal HTTPS JSON client so navigation needs no extra package. M1 may
/// replace it. Implementations must honour cancellation, enforce a timeout
/// and size limit, and never log URLs or bodies.
abstract interface class JsonTransport {
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation});

  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  });
}
