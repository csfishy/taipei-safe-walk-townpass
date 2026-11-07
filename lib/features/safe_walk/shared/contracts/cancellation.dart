/// Cooperative cancellation only; it never starts or shares a location request.
abstract interface class SafeWalkCancellation {
  bool get isCancelled;

  /// Completes when cancellation is requested, without throwing.
  Future<void> get whenCancelled;
}

extension SafeWalkCancellationChecks on SafeWalkCancellation {
  void throwIfCancelled() {
    if (isCancelled) throw const SafeWalkCancelledException();
  }
}

/// Internal adapter signal. Wire payloads still use the statuses in the schema.
final class SafeWalkCancelledException implements Exception {
  const SafeWalkCancelledException();

  @override
  String toString() => 'Safe Walk operation cancelled';
}
