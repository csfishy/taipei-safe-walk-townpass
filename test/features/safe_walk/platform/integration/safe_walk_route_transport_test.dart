import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

void main() {
  test('default transport instances share the process dispatch limit', () async {
    final watch = Stopwatch()..start();
    final starts = <int>[];
    final inner = _Inner(_Time())
      ..response = () {
        starts.add(watch.elapsedMicroseconds);
        return Future<Object?>.value({'ok': true});
      };
    RateLimitedRouteTransport transport() =>
        RateLimitedRouteTransport(inner: inner, hasConsent: () => true);
    await Future.wait([
      transport().getJson(_url('first')),
      transport().getJson(_url('second')),
    ]);
    // Small measurement tolerance; independent per-instance gates would send
    // both immediately. Exact one-second spacing is covered by the fake clock.
    expect(starts[1] - starts[0], greaterThanOrEqualTo(950000));
  });

  test(
    'no consent or an already cancelled request never reaches the network',
    () async {
      final time = _Time();
      final inner = _Inner(time);
      final denied = RateLimitedRouteTransport(
        inner: inner,
        hasConsent: () => false,
        gate: time.gate(),
      );
      await expectLater(
        denied.getJson(_url('denied')),
        throwsA(isA<ConsentRequiredException>()),
      );
      final cancelled = _Cancellation()..cancel();
      await expectLater(
        RateLimitedRouteTransport(
          inner: inner,
          hasConsent: () => true,
          gate: time.gate(),
        ).getJson(_url('cancelled'), cancellation: cancelled),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(inner.calls, isEmpty);
      expect(time.waits, isEmpty);
    },
  );

  test(
    'shared gate spaces instances without waiting for HTTP completion',
    () async {
      final time = _Time();
      final gate = time.gate();
      final pendingResponse = Completer<Object?>();
      final inner = _Inner(time)..response = () => pendingResponse.future;
      RateLimitedRouteTransport transport() => RateLimitedRouteTransport(
        inner: inner,
        hasConsent: () => true,
        gate: gate,
      );
      final first = transport().getJson(_url('first'));
      final second = transport().getJson(_url('second'));
      final third = transport().getJson(_url('third'));
      await time.waitForCount(1);
      expect(inner.calls.map((call) => call.at), [Duration.zero]);
      time.advance(const Duration(milliseconds: 999));
      expect(inner.calls, hasLength(1));
      time.advance(const Duration(milliseconds: 1));
      await time.waitForCount(2);
      expect(inner.calls.map((call) => call.at), [
        Duration.zero,
        const Duration(seconds: 1),
      ]);
      time.advance(const Duration(seconds: 1));
      pendingResponse.complete({'ok': true});
      expect(
        await Future.wait([first, second, third]),
        everyElement({'ok': true}),
      );
      expect(inner.calls.map((call) => call.at), [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
    },
  );

  test('cancelling a paced request does not send it or let a later request jump the gate', () async {
    final time = _Time();
    final inner = _Inner(time);
    final transport = RateLimitedRouteTransport(
      inner: inner,
      hasConsent: () => true,
      gate: time.gate(),
    );
    await transport.getJson(_url('first'));
    final token = _Cancellation();
    final cancelled = expectLater(
      transport.getJson(_url('cancelled'), cancellation: token),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    await time.waitForCount(1);
    final following = transport.getJson(_url('following'));
    token.cancel();
    await cancelled;
    await time.waitForCount(2);
    expect(inner.calls.map((call) => call.url.path), ['/first']);
    time.advance(const Duration(seconds: 1));
    await following;
    expect(inner.calls.map((call) => call.url.path), ['/first', '/following']);
    expect(inner.calls.last.at, const Duration(seconds: 1));
  });

  test('a caller cancelled while queued cannot release a still-waiting predecessor', () async {
    final time = _Time();
    final inner = _Inner(time);
    final transport = RateLimitedRouteTransport(
      inner: inner,
      hasConsent: () => true,
      gate: time.gate(),
    );
    await transport.getJson(_url('first'));
    final second = transport.getJson(_url('second'));
    await time.waitForCount(1);
    final token = _Cancellation();
    final cancelled = expectLater(
      transport.getJson(_url('cancelled'), cancellation: token),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    final last = transport.getJson(_url('last'));
    token.cancel();
    await cancelled;
    expect(time.waits, hasLength(1));
    time.advance(const Duration(seconds: 1));
    await second;
    await time.waitForCount(2);
    expect(inner.calls.map((call) => call.url.path), ['/first', '/second']);
    time.advance(const Duration(seconds: 1));
    await last;
    expect(inner.calls.last.url.path, '/last');
    expect(inner.calls.last.at, const Duration(seconds: 2));
  });

  test(
    'consent revoked during the pacing wait is checked before dispatch',
    () async {
      final time = _Time();
      final inner = _Inner(time);
      var consent = true;
      final transport = RateLimitedRouteTransport(
        inner: inner,
        hasConsent: () => consent,
        gate: time.gate(),
      );
      await transport.getJson(_url('first'));
      final rejected = expectLater(
        transport.getJson(_url('revoked')),
        throwsA(isA<ConsentRequiredException>()),
      );
      await time.waitForCount(1);
      consent = false;
      time.advance(const Duration(seconds: 1));
      await rejected;
      expect(inner.calls.map((call) => call.url.path), ['/first']);
      consent = true;
      await transport.getJson(_url('restored'));
      expect(inner.calls.last.at, const Duration(seconds: 1));
    },
  );

  test(
    'POST forwards the body/token and cancellation suppresses a late response',
    () async {
      final time = _Time();
      final pending = Completer<Object?>();
      final inner = _Inner(time)..response = () => pending.future;
      final token = _Cancellation();
      final form = {'request': 'synthetic'};
      final transport = RateLimitedRouteTransport(
        inner: inner,
        hasConsent: () => true,
        gate: time.gate(),
      );
      final rejected = expectLater(
        transport.postFormJson(_url('post'), form, cancellation: token),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await inner.dispatched.future;
      expect(inner.calls.single.form, same(form));
      expect(inner.calls.single.cancellation, same(token));
      token.cancel();
      await rejected;
      pending.complete({'late': true});
    },
  );

  test(
    'synchronous delegate cancellation still observes its response error',
    () async {
      final time = _Time();
      final token = _Cancellation();
      final inner = _Inner(time)
        ..response = () {
          token.cancel();
          return Future<Object?>.error(StateError('synthetic network failure'));
        };
      final transport = RateLimitedRouteTransport(
        inner: inner,
        hasConsent: () => true,
        gate: time.gate(),
      );
      await expectLater(
        transport.getJson(_url('cancel-during-dispatch'), cancellation: token),
        throwsA(isA<SafeWalkCancelledException>()),
      );
    },
  );
}

Uri _url(String name) => Uri.parse('https://example.test/$name');

final class _Time {
  Duration now = Duration.zero;
  final waits = <({Duration due, Completer<void> complete})>[];
  Completer<void>? _added;

  RouteDispatchGate gate() => RouteDispatchGate(elapsed: () => now, wait: wait);

  Future<void> wait(Duration duration) {
    final complete = Completer<void>();
    waits.add((due: now + duration, complete: complete));
    _added?.complete();
    _added = null;
    return complete.future;
  }

  Future<void> waitForCount(int count) async {
    while (waits.length < count) {
      final added = _added ??= Completer<void>();
      await added.future;
    }
  }

  void advance(Duration duration) {
    now += duration;
    for (final wait in waits) {
      if (!wait.complete.isCompleted && wait.due <= now) {
        wait.complete.complete();
      }
    }
  }
}

final class _Cancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();
  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() => _cancelled.complete();
}

final class _Inner implements JsonTransport {
  _Inner(this.time);
  final _Time time;
  final calls =
      <
        ({
          Duration at,
          Uri url,
          Map<String, String>? form,
          SafeWalkCancellation? cancellation,
        })
      >[];
  final dispatched = Completer<void>();
  Future<Object?> Function()? response;

  Future<Object?> record(
    Uri url,
    Map<String, String>? form,
    SafeWalkCancellation? cancellation,
  ) {
    calls.add((at: time.now, url: url, form: form, cancellation: cancellation));
    if (!dispatched.isCompleted) dispatched.complete();
    return response?.call() ?? Future<Object?>.value({'ok': true});
  }

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) =>
      record(url, null, cancellation);

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) => record(url, form, cancellation);
}
