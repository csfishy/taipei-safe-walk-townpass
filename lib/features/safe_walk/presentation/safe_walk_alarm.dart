abstract interface class SafeWalkAlarm {
  bool get available;

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

final class UnavailableSafeWalkAlarm implements SafeWalkAlarm {
  const UnavailableSafeWalkAlarm();

  @override
  bool get available => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
