import 'dart:isolate';

import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// A cancelled request kills its own isolate, including parsing/A* work.
Future<T> runOfflineWorker<T>(
  T Function() work,
  SafeWalkCancellation? cancellation,
) async {
  cancellation?.throwIfCancelled();
  final port = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn((SendPort out) {
      try {
        out.send((true, work()));
      } catch (_) {
        out.send((false, null));
      }
    }, port.sendPort);
    final result = await raceCancellation(
      port.first,
      cancellation,
    ).timeout(const Duration(seconds: 15)) as (bool, Object?);
    if (!result.$1) throw const FormatException('Offline route unavailable');
    return result.$2 as T;
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}
