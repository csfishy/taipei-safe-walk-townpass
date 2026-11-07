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
  Future<void>? _stopInFlight;
  bool _disposing = false;
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
      await _stopAudio();
    } else if (_stopInFlight case final stop?) {
      await stop;
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
        final started = _observeMilestone(playback.started);
        final completed = _observeMilestone(playback.completed);
        final cancelledBeforeStart = await _awaitOrInterruption(
          started,
          cancellation,
          interruption.future,
        );
        if (cancelledBeforeStart || !_isCurrent(operation)) {
          await _cancelOperation(operation);
          return;
        }
        _rethrowMilestoneFailure(await started);
        _emit(sw.CompanionState.playing, sw.CompanionReason.user);

        final cancelledBeforeCompletion = await _awaitOrInterruption(
          completed,
          cancellation,
          interruption.future,
        );
        if (cancelledBeforeCompletion || !_isCurrent(operation)) {
          await _cancelOperation(operation);
          return;
        }
        _rethrowMilestoneFailure(await completed);

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
          final errorOperation = _operation;
          await _stopAudio();
          if (_isCurrent(errorOperation)) {
            _emit(sw.CompanionState.error, sw.CompanionReason.audioError);
          }
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
    final pauseOperation = _operation;
    await _audio.pause();
    if (_isCurrent(pauseOperation)) {
      _emit(sw.CompanionState.paused, sw.CompanionReason.user);
    }
  }

  @override
  Future<void> stop(sw.CompanionStopReason reason) async {
    if (_disposing || _disposed) return;
    await _stop(reason);
  }

  Future<void> _stop(sw.CompanionStopReason reason) async {
    _invalidateOperation();
    final stopOperation = _operation;
    await _stopAudio();
    if (!_isCurrent(stopOperation)) return;
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
    if (_disposing || _disposed) return;
    _disposing = true;
    await _stop(sw.CompanionStopReason.unmount);
    _disposed = true;
    await _audio.dispose();
    await _events.close();
  }

  Future<bool> _awaitOrInterruption<T>(
    Future<T> work,
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
    await _stopAudio();
  }

  Future<void> _stopAudio() {
    final pending = _stopInFlight;
    if (pending != null) return pending;

    late final Future<void> stop;
    stop = Future<void>.sync(_audio.stop).whenComplete(() {
      if (identical(_stopInFlight, stop)) _stopInFlight = null;
    });
    _stopInFlight = stop;
    return stop;
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
    if (_disposing || _disposed) {
      throw StateError('Companion controller has been disposed');
    }
  }
}

final class _MilestoneResult {
  const _MilestoneResult.success() : error = null, stackTrace = null;

  const _MilestoneResult.failure(this.error, this.stackTrace);

  final Object? error;
  final StackTrace? stackTrace;
}

Future<_MilestoneResult> _observeMilestone(Future<void> milestone) async {
  try {
    await milestone;
    return const _MilestoneResult.success();
  } catch (error, stackTrace) {
    return _MilestoneResult.failure(error, stackTrace);
  }
}

void _rethrowMilestoneFailure(_MilestoneResult result) {
  final error = result.error;
  if (error != null) {
    Error.throwWithStackTrace(error, result.stackTrace ?? StackTrace.current);
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
