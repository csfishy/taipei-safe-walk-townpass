import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Device text-to-speech used to read companion lines aloud.
///
/// This is on-device speech only: no API key, no network service and no
/// recording. It never claims a real call or a listening person; it only
/// reads the text it is given. Wiring it into the view is M1's integration.
abstract interface class CompanionSpeechEngine {
  /// Selects the first available language; returns false if none is usable.
  Future<bool> prepare(List<String> languages);

  /// Completes when the utterance finishes, is cancelled, fails or is stopped.
  Future<void> speak(String text);

  Future<void> stop();
}

/// Reads one line at a time. A new [speak] or [stop] invalidates the previous
/// line, so a late completion can never clear the indicator of a newer line.
final class CompanionTtsSpeaker {
  CompanionTtsSpeaker(
    this._engine, {
    this.languages = const ['zh-TW', 'zh-CN'],
  });

  final CompanionSpeechEngine _engine;
  final List<String> languages;

  bool _ready = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _prepareFuture;

  /// True only after the device confirmed a usable Chinese voice.
  bool get available => _ready && !_disposed;

  /// Safe to call repeatedly; failures leave the speaker unavailable.
  Future<void> prepare() => _prepareFuture ??= _prepareOnce();

  Future<void> _prepareOnce() async {
    try {
      _ready = await _engine.prepare(languages);
    } catch (_) {
      _ready = false;
    }
  }

  /// Unavailable or empty text calls [onDone] at once, like a text preview.
  void speak(String text, {void Function()? onDone}) {
    if (!available || text.trim().isEmpty) {
      onDone?.call();
      return;
    }
    final generation = ++_generation;
    unawaited(_run(text, generation, onDone));
  }

  Future<void> _run(
    String text,
    int generation,
    void Function()? onDone,
  ) async {
    try {
      await _engine.stop();
      if (!_isCurrent(generation)) return;
      await _engine.speak(text);
    } catch (_) {
      // A failed utterance ends like a finished one; nothing claims playback.
    }
    if (_isCurrent(generation)) onDone?.call();
  }

  void stop() {
    if (_disposed) return;
    _generation++;
    unawaited(_stopQuietly());
  }

  /// Idempotent; stops any current line and makes the speaker unavailable.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _stopQuietly();
  }

  Future<void> _stopQuietly() async {
    try {
      await _engine.stop();
    } catch (_) {}
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}

/// [CompanionSpeechEngine] backed by the `flutter_tts` plugin.
///
/// `awaitSpeakCompletion` is deliberately not used: on Android a stopped
/// utterance never completes that future. Completion, cancel and error
/// callbacks, plus [stop] itself, release the pending utterance instead.
final class FlutterTtsEngine implements CompanionSpeechEngine {
  FlutterTtsEngine([FlutterTts? tts]) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(_release);
    _tts.setCancelHandler(_release);
    _tts.setErrorHandler((_) => _release());
  }

  final FlutterTts _tts;
  Completer<void>? _pending;

  void _release() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  Future<bool> prepare(List<String> languages) async {
    for (final language in languages) {
      if (await _tts.isLanguageAvailable(language) == true) {
        await _tts.setLanguage(language);
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> speak(String text) async {
    _release();
    final pending = _pending = Completer<void>();
    final result = await _tts.speak(text);
    // flutter_tts reports 1 when the utterance was accepted.
    if (result != 1) _release();
    return pending.future;
  }

  @override
  Future<void> stop() async {
    _release();
    await _tts.stop();
  }
}
