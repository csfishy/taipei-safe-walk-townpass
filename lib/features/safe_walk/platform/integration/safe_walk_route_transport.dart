import 'dart:async';

import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

final _defaultOsrmDispatchGate = RouteDispatchGate();

/// Paces the default public OSRM transport across route/widget instances.
///
/// This adapter belongs only on the default OSRM path. Other providers and
/// injected widget-test transports keep their own transport policies. The gate
/// stores dispatch times and queue futures, never URLs, coordinates or bodies.
final class RateLimitedRouteTransport implements JsonTransport {
  factory RateLimitedRouteTransport({
    required JsonTransport inner,
    required bool Function() hasConsent,
    RouteDispatchGate? gate,
  }) => RateLimitedRouteTransport._(
    inner,
    hasConsent,
    gate ?? _defaultOsrmDispatchGate,
  );

  RateLimitedRouteTransport._(this._inner, this._hasConsent, this._gate);

  final JsonTransport _inner;
  final bool Function() _hasConsent;
  final RouteDispatchGate _gate;

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) =>
      _gate.dispatch(
        () => _inner.getJson(url, cancellation: cancellation),
        hasConsent: _hasConsent,
        cancellation: cancellation,
      );

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) => _gate.dispatch(
    () => _inner.postFormJson(url, form, cancellation: cancellation),
    hasConsent: _hasConsent,
    cancellation: cancellation,
  );
}

/// Serializes dispatch starts, not the HTTP responses, using a monotonic clock.
/// The production gate is shared per process; tests can inject clock/wait seams.
final class RouteDispatchGate {
  RouteDispatchGate({
    this.minInterval = const Duration(seconds: 1),
    Duration Function()? elapsed,
    Future<void> Function(Duration)? wait,
  }) : _elapsed = elapsed ?? _monotonicClock(),
       _wait = wait ?? ((duration) => Future<void>.delayed(duration)) {
    if (minInterval.isNegative) {
      throw ArgumentError.value(
        minInterval,
        'minInterval',
        'must be nonnegative',
      );
    }
  }

  final Duration minInterval;
  final Duration Function() _elapsed;
  final Future<void> Function(Duration) _wait;
  Future<void> _tail = Future<void>.value();
  Duration? _lastDispatch;

  Future<T> dispatch<T>(
    Future<T> Function() send, {
    required bool Function() hasConsent,
    SafeWalkCancellation? cancellation,
  }) async {
    _checkAllowed(hasConsent, cancellation);
    final previous = _tail;
    final released = Completer<void>();
    // A caller cancelled before its turn may return immediately, but must not
    // release later callers ahead of an earlier, still-waiting dispatch.
    _tail = previous.then((_) => released.future);
    late final Future<T> response;
    try {
      await _untilCancelled(previous, cancellation);
      _checkAllowed(hasConsent, cancellation);
      while (_lastDispatch != null) {
        final remaining = minInterval - (_elapsed() - _lastDispatch!);
        if (remaining <= Duration.zero) break;
        await _untilCancelled(_wait(remaining), cancellation);
        _checkAllowed(hasConsent, cancellation);
      }
      _checkAllowed(hasConsent, cancellation);
      _lastDispatch = _elapsed();
      response = send();
    } finally {
      released.complete();
    }

    final result = await _untilCancelled(response, cancellation);
    _checkAllowed(hasConsent, cancellation);
    return result;
  }
}

Duration Function() _monotonicClock() {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}

void _checkAllowed(
  bool Function() hasConsent,
  SafeWalkCancellation? cancellation,
) {
  cancellation?.throwIfCancelled();
  if (!hasConsent()) throw const ConsentRequiredException();
}

Future<T> _untilCancelled<T>(
  Future<T> pending,
  SafeWalkCancellation? cancellation,
) async {
  if (cancellation == null) return pending;
  // The delegate may cancel synchronously while returning a future that later
  // fails. Observe that future even when cancellation wins before the await.
  if (cancellation.isCancelled) pending.ignore();
  cancellation.throwIfCancelled();
  final result = await Future.any<T>([
    pending,
    cancellation.whenCancelled.then<T>(
      (_) => throw const SafeWalkCancelledException(),
    ),
  ]);
  cancellation.throwIfCancelled();
  return result;
}
