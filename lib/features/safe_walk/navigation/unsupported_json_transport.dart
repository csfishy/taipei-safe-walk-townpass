import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// Used where `dart:io` does not exist (the web preview). It always fails
/// with [TransportFailure.unsupported] so callers report the service as
/// unavailable instead of pretending to have fetched anything.
final class UnsupportedJsonTransport implements JsonTransport {
  const UnsupportedJsonTransport();

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) =>
      Future.error(const JsonTransportException(TransportFailure.unsupported));

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) =>
      Future.error(const JsonTransportException(TransportFailure.unsupported));
}

JsonTransport createDefaultJsonTransport() => const UnsupportedJsonTransport();
