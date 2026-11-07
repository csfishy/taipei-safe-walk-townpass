import 'dart:async';

import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// Completes with [future], or throws [SafeWalkCancelledException] as soon as
/// [cancellation] fires. A result or error that arrives later is ignored.
Future<T> raceCancellation<T>(
  Future<T> future,
  SafeWalkCancellation? cancellation,
) {
  if (cancellation == null) return future;
  final completer = Completer<T>();
  future.then(
    (value) {
      if (!completer.isCompleted) completer.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  cancellation.whenCancelled.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(const SafeWalkCancelledException());
    }
  });
  return completer.future;
}

/// A cancellation that code can trigger itself, e.g. to stop slower mirrors
/// once one has answered.
final class ManualCancellation implements SafeWalkCancellation {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Completes with the first future that succeeds; fails only when all fail.
Future<T> firstSuccess<T>(List<Future<T>> futures) {
  final completer = Completer<T>();
  var pending = futures.length;
  if (pending == 0) {
    completer.completeError(StateError('No futures'));
    return completer.future;
  }
  for (final future in futures) {
    future.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );
  }
  return completer.future;
}
