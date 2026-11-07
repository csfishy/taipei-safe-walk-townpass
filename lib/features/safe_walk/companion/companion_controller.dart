import 'dart:async';

import 'package:town_pass/features/safe_walk/companion/companion_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

typedef CompanionAssetResolver = String? Function(String wireSource);
typedef CompanionClock = DateTime Function();
typedef CompanionDelay = Future<void> Function(Duration duration);

/// Pure M5 orchestration for approved local companion audio.
///
/// [resolveAsset] is the allow-list boundary between a wire `/audio/...` value
/// and a bundled Flutter asset. Returning null rejects an unapproved source.
final class LocalCompanionController implements CompanionController {
  factory LocalCompanionController({
    required CompanionAudioAdapter audio,
    required CompanionAssetResolver resolveAsset,
    CompanionClock? clock,
    CompanionDelay? delay,
  }) => LocalCompanionController._(
    audio,
    resolveAsset,
    clock ?? DateTime.now,
    delay ?? Future<void>.delayed,
  );

  LocalCompanionController._(
    this._audio,
    this._resolveAsset,
    this._clock,
    this._delay,
  );

  final CompanionAudioAdapter _audio;
  final CompanionAssetResolver _resolveAsset;
  final CompanionClock _clock;
  final CompanionDelay _delay;
  final StreamController<sw.CompanionEvent> _events =
      StreamController<sw.CompanionEvent>.broadcast(sync: true);

  int _operation = 0;
  Completer<void>? _activeInterruption;
  String? _scenarioId;
  sw.CompanionState _state = sw.CompanionState.idle;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  Stream<sw.CompanionEvent> get events => _events.stream;

  @override
  Future<void> start(
    sw.CompanionScenario scenario, {
    SafeWalkCancellation? cancellation,
  }) async {
    _ensureUsable();
    if (cancellation?.isCancelled == true) return;

    _invalidateOperation();
    final operation = _operation;
    final interruption = Completer<void>();
    _activeInterruption = interruption;
    if (_state == sw.CompanionState.playing ||
        _state == sw.CompanionState.paused) {
      await _audio.stop();
    }
    if (!_isCurrent(operation)) return;

    _scenarioId = scenario.id;
    _state = sw.CompanionState.idle;

    for (final step in scenario.steps) {
      if (!_isCurrent(operation) || cancellation?.isCancelled == true) {
        await _cancelOperation(operation);
        return;
      }

      final source = step.audioSrc;
      final asset = source == null ? null : _resolveAsset(source);
      if (asset == null) {
        _emit(sw.CompanionState.ended, sw.CompanionReason.notConfigured);
        _activeInterruption = null;
        return;
      }

      try {
        final playback = await _awaitValueOrInterruption(
          _audio.playAsset(asset, cancellation: cancellation),
          cancellation,
          interruption.future,
        );
        if (playback == null || !_isCurrent(operation)) {
          await _cancelOperation(operation);
          return;
        }
        final cancelledBeforeStart = await _awaitOrInterruption(
          playback.started,
          cancellation,
          interruption.future,
        );
        if (cancelledBeforeStart || !_isCurrent(operation)) {
          await _cancelOperation(operation);
          return;
        }
        _emit(sw.CompanionState.playing, sw.CompanionReason.user);

        final cancelledBeforeCompletion = await _awaitOrInterruption(
          playback.completed,
          cancellation,
          interruption.future,
        );
        if (cancelledBeforeCompletion || !_isCurrent(operation)) {
          await _cancelOperation(operation);
          return;
        }

        final delayCancelled = await _awaitOrInterruption(
          step.pauseAfterMs == 0
              ? Future<void>.value()
              : _delay(Duration(milliseconds: step.pauseAfterMs)),
          cancellation,
          interruption.future,
        );
        if (delayCancelled || !_isCurrent(operation)) {
          await _cancelOperation(operation);
          return;
        }
      } on SafeWalkCancelledException {
        await _cancelOperation(operation);
        return;
      } catch (_) {
        if (_isCurrent(operation)) {
          _invalidateOperation();
          await _audio.stop();
          _emit(sw.CompanionState.error, sw.CompanionReason.audioError);
        }
        return;
      }
    }

    if (_isCurrent(operation)) {
      _emit(sw.CompanionState.ended, sw.CompanionReason.user);
      _activeInterruption = null;
    }
  }

  @override
  Future<void> pause() async {
    _ensureUsable();
    if (_state != sw.CompanionState.playing) return;

    _invalidateOperation();
    await _audio.pause();
    _emit(sw.CompanionState.paused, sw.CompanionReason.user);
  }

  @override
  Future<void> stop(sw.CompanionStopReason reason) async {
    if (_disposed) return;
    await _stop(reason);
  }

  Future<void> _stop(sw.CompanionStopReason reason) async {
    _invalidateOperation();
    await _audio.stop();
    if (_state == sw.CompanionState.ended ||
        _state == sw.CompanionState.error ||
        _scenarioId == null) {
      return;
    }
    _emit(sw.CompanionState.ended, _eventReason(reason));
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    if (_disposed) return;
    await _stop(sw.CompanionStopReason.unmount);
    _disposed = true;
    await _audio.dispose();
    await _events.close();
  }

  Future<bool> _awaitOrInterruption(
    Future<void> work,
    SafeWalkCancellation? cancellation,
    Future<void> interruption,
  ) async {
    return Future.any<bool>([
      work.then((_) => false),
      interruption.then((_) => true),
      if (cancellation != null)
        cancellation.whenCancelled.then((_) => true),
    ]);
  }

  Future<T?> _awaitValueOrInterruption<T>(
    Future<T> work,
    SafeWalkCancellation? cancellation,
    Future<void> interruption,
  ) => Future.any<T?>([
    work.then<T?>((value) => value),
    interruption.then<T?>((_) => null),
    if (cancellation != null)
      cancellation.whenCancelled.then<T?>((_) => null),
  ]);

  Future<void> _cancelOperation(int operation) async {
    if (_operation != operation) return;
    _invalidateOperation();
    await _audio.stop();
  }

  void _invalidateOperation() {
    _operation++;
    final interruption = _activeInterruption;
    _activeInterruption = null;
    if (interruption != null && !interruption.isCompleted) {
      interruption.complete();
    }
  }

  bool _isCurrent(int operation) => !_disposed && _operation == operation;

  void _emit(sw.CompanionState state, sw.CompanionReason reason) {
    if (_disposed || _events.isClosed || _scenarioId == null) return;
    _state = state;
    _events.add(
      sw.CompanionEvent(
        scenarioId: _scenarioId!,
        state: state,
        reason: reason,
        occurredAt: _clock().toUtc().toIso8601String(),
      ),
    );
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('Companion controller has been disposed');
    }
  }
}

sw.CompanionReason _eventReason(sw.CompanionStopReason reason) =>
    switch (reason) {
      sw.CompanionStopReason.user => sw.CompanionReason.user,
      sw.CompanionStopReason.emergency => sw.CompanionReason.emergency,
      sw.CompanionStopReason.unmount => sw.CompanionReason.unmount,
      sw.CompanionStopReason.visibilityHidden =>
        sw.CompanionReason.visibilityHidden,
    };
