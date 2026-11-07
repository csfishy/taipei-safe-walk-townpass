import 'dart:async';

import 'package:town_pass/features/safe_walk/companion/companion_controller.dart';
import 'package:town_pass/features/safe_walk/companion/companion_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

typedef CompanionTextPreviewMapper = sw.CompanionScenario? Function(
  String text,
);

/// M1's text-only bridge between the M3 view and the real M5 controller.
///
/// No recordings/player are configured in this integration. Even an injected
/// mapper cannot enable audio: non-null audio sources are rejected. A future
/// audible implementation needs separate asset/player approval and integration.
final class CompanionSpeakerAdapter implements SafeWalkRouteSpeaker {
  factory CompanionSpeakerAdapter({
    required CompanionController controller,
    CompanionTextPreviewMapper? scenarioForText,
  }) => CompanionSpeakerAdapter._(controller, scenarioForText ?? _textPreview);

  CompanionSpeakerAdapter._(this._controller, this._scenarioForText);

  factory CompanionSpeakerAdapter.unavailable() => CompanionSpeakerAdapter(
    controller: LocalCompanionController(
      audio: const UnavailableCompanionAudioAdapter(),
      resolveAsset: (_) => null,
    ),
  );

  final CompanionController _controller;
  final CompanionTextPreviewMapper _scenarioForText;
  _SpeechCancellation? _active;
  int _generation = 0;
  bool _emergencyStopped = false;
  bool _lifecycleActive = true;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  Object? _lastError;

  @override
  bool get available => false;

  /// Observable lifecycle failures; never logged or used to claim playback.
  Object? get lastError => _lastError;

  /// M5 events remain available to composition/tests. Text previews emit
  /// not_configured through M5, never a synthetic playing acknowledgement.
  Stream<sw.CompanionEvent> get events => _controller.events;

  @override
  void speak(String text, {void Function()? onDone}) {
    if (_disposed) return;
    if (!_lifecycleActive || _emergencyStopped) {
      // Clear the view's text-preview indicator without restarting M5 work.
      onDone?.call();
      return;
    }
    _invalidate();
    final generation = _generation;
    final cancellation = _SpeechCancellation();
    _active = cancellation;
    unawaited(_preview(text, onDone, generation, cancellation));
  }

  Future<void> _preview(
    String text,
    void Function()? onDone,
    int generation,
    _SpeechCancellation cancellation,
  ) async {
    try {
      // Invalidate any previous controller run before attempting this preview.
      await _controller.stop(sw.CompanionStopReason.user);
      if (!_isCurrent(generation)) return;
      final scenario = _scenarioForText(text);
      if (scenario == null ||
          scenario.steps.any((step) => step.audioSrc != null)) {
        throw UnsupportedError(
          'Only approved text-only companion previews are configured',
        );
      }
      await Future.any<void>([
        _controller.start(scenario, cancellation: cancellation),
        cancellation.whenCancelled,
      ]);
    } on SafeWalkCancelledException {
      // Intentional interruption is not an audio failure.
    } catch (error) {
      if (_isCurrent(generation)) _lastError = error;
    }
    if (_isCurrent(generation)) {
      _active = null;
      onDone?.call();
    }
  }

  @override
  void stop() {
    if (_disposed) return;
    _invalidate();
    unawaited(_observe(() => _controller.stop(sw.CompanionStopReason.user)));
  }

  @override
  void setLifecycleActive(bool active) {
    if (_disposed || _lifecycleActive == active) return;
    _lifecycleActive = active;
    if (!active) stop();
  }

  Future<void> pause() {
    if (_disposed) return Future<void>.value();
    _invalidate();
    return _observe(_controller.pause);
  }

  /// Latches the bridge off immediately, before awaiting M5 cleanup. Late view
  /// replies cannot restart a run. A new flow creates a new bridge instance.
  @override
  Future<void> stopForEmergency() {
    if (_disposed) return Future<void>.value();
    _emergencyStopped = true;
    _invalidate();
    // Call now, rather than queueing behind an unfinished start/preview.
    return _observe(() => _controller.stop(sw.CompanionStopReason.emergency));
  }

  /// This bridge owns the injected controller; disposal is idempotent.
  @override
  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    _disposed = true;
    _invalidate();
    await _observe(() => _controller.stop(sw.CompanionStopReason.unmount));
    // Still release the controller if its stop operation failed.
    await _observe(_controller.dispose);
  }

  Future<void> _observe(Future<void> Function() action) async {
    try {
      await action();
    } on SafeWalkCancelledException {
      // Cooperative cancellation is expected cleanup.
    } catch (error) {
      _lastError = error;
    }
  }

  void _invalidate() {
    _generation++;
    _active?.cancel();
    _active = null;
  }

  bool _isCurrent(int generation) =>
      !_disposed &&
      _lifecycleActive &&
      !_emergencyStopped &&
      _generation == generation;
}

sw.CompanionScenario? _textPreview(String text) {
  if (text.isEmpty || text.runes.length > 300) return null;
  return sw.CompanionScenario(
    id: 'm1-unavailable-preview',
    label: '模擬陪伴文字預覽',
    steps: [
      sw.CompanionStep(
        id: 'text-preview',
        text: text,
        audioSrc: null,
        pauseAfterMs: 0,
      ),
    ],
  );
}

/// Explicitly unavailable native audio. It never manufactures lifecycle
/// milestones, opens a microphone, fetches a URL, or claims a real call.
final class UnavailableCompanionAudioAdapter implements CompanionAudioAdapter {
  const UnavailableCompanionAudioAdapter();

  @override
  Future<CompanionPlayback> playAsset(
    String assetPath, {
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    throw UnsupportedError(
      'Companion recordings and native playback are not configured',
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

final class _SpeechCancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();
  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
