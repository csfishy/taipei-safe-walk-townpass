import 'dart:async';

import 'package:flutter/foundation.dart';
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
  CompanionTtsSpeaker(this._engine, {this.languages = const ['en-US', 'en-GB']});

  final CompanionSpeechEngine _engine;
  final List<String> languages;

  bool _ready = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _prepareFuture;

  /// True only after the device confirmed a usable English voice.
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

  Future<void> _run(String text, int generation, void Function()? onDone) async {
    try {
      await _engine.stop();
      if (!_isCurrent(generation)) return;
      await _engine.speak(text);
    } catch (_) {
      // A failed utterance ends like a finished one; nothing claims playback.
      if (_isCurrent(generation)) _ready = false;
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
    } catch (_) {
      _ready = false;
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}

/// [CompanionSpeechEngine] backed by the `flutter_tts` plugin.
///
/// `awaitSpeakCompletion` is deliberately not used: on Android a stopped
/// utterance never completes that future. Completion, cancel and error
/// callbacks, plus [stop] itself, release the pending utterance instead.
final class FlutterTtsEngine implements CompanionSpeechEngine {
  FlutterTtsEngine([FlutterTts? tts]) : _driver = tts == null ? (_deviceDriver ??= _FlutterTtsDriver(FlutterTts())) : _FlutterTtsDriver(tts);

  // flutter_tts owns a static channel. Keep one handler across route handoffs;
  // each facade's owner prevents a late old-route stop from stopping a new one.
  static _FlutterTtsDriver? _deviceDriver;
  final _FlutterTtsDriver _driver;
  final Object _owner = Object();
  int _generation = 0;

  @override
  Future<bool> prepare(List<String> languages) => _driver.prepare(languages);

  @override
  Future<void> speak(String text) {
    final generation = ++_generation;
    return _driver.speak(text, _owner, () => generation == _generation);
  }

  @override
  Future<void> stop() {
    _generation++;
    return _driver.stop(_owner);
  }
}

final class _FlutterTtsDriver {
  _FlutterTtsDriver(this._tts) {
    _tts.setCompletionHandler(_terminalReceived);
    _tts.setCancelHandler(_terminalReceived);
    _tts.setErrorHandler((_) => _terminalReceived());
  }

  final FlutterTts _tts;
  Completer<void>? _pending;
  Completer<void>? _terminal;
  Future<void>? _stopFuture;
  Object? _owner;
  bool _blocked = false;

  void _terminalReceived() {
    final terminal = _terminal;
    _terminal = null;
    if (terminal != null && !terminal.isCompleted) terminal.complete();
    _release();
  }

  void _release() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<bool> prepare(List<String> languages) async {
    final stopping = _stopFuture;
    if (stopping != null) await stopping;
    if (_blocked) return false;
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return false;
    }
    final raw = await _tts.getVoices;
    if (raw is! List) return false;
    // Prefer the most natural-sounding installed voice (higher quality first).
    final voices = [...raw]..sort((x, y) => _voiceQuality(y).compareTo(_voiceQuality(x)));
    for (final language in languages) {
      for (final voice in voices) {
        if (voice is! Map || voice['locale'] != language) continue;
        final name = voice['name'];
        if (name is! String || name.isEmpty) continue;
        final selected = <String, String>{'name': name, 'locale': language};
        if (defaultTargetPlatform == TargetPlatform.android) {
          // flutter_tts 4.2.5 exposes Android Voice's offline/install flags.
          final features = voice['features'];
          if (voice['network_required'] != '0' || features is! String || features.split('\t').contains('notInstalled')) {
            continue;
          }
        } else {
          // iOS getVoices enumerates installed AVSpeechSynthesisVoice objects;
          // AVSpeechSynthesizer generates speech on device (Apple's contract).
          final identifier = voice['identifier'];
          if (identifier is! String || identifier.isEmpty) continue;
          selected['identifier'] = identifier;
        }
        if (await _tts.setVoice(selected) == 1) {
          // Slightly slower than default reads more like a person on the phone.
          await _tts.setSpeechRate(0.46);
          return true;
        }
      }
    }
    return false;
  }

  /// Android reports a numeric quality (300 low … 500 very high);
  /// iOS reports default / enhanced / premium.
  static int _voiceQuality(Object? voice) {
    if (voice is! Map) return 0;
    final q = voice['quality'];
    if (q is num) return q.toInt();
    if (q is! String) return 0;
    return int.tryParse(q) ?? const {'premium': 3, 'enhanced': 2}[q.toLowerCase()] ?? 0;
  }

  Future<void> speak(String text, Object owner, bool Function() isCurrent) async {
    while (true) {
      if (!isCurrent()) return;
      final stopping = _stopFuture;
      if (stopping != null) {
        await stopping;
        continue;
      }
      if (_blocked) throw StateError('TTS stop was not acknowledged');
      if (_terminal != null) {
        await _stopNative();
        continue;
      }
      break;
    }
    _owner = owner;
    final pending = _pending = Completer<void>();
    final terminal = _terminal = Completer<void>();
    final Object? result;
    try {
      result = await _tts.speak(text);
    } catch (_) {
      if (identical(_terminal, terminal)) _terminalReceived();
      rethrow;
    }
    // flutter_tts reports 1 when the utterance was accepted.
    if (result != 1 && identical(_terminal, terminal)) _terminalReceived();
    return pending.future;
  }

  Future<void> stop(Object owner) {
    if (_terminal == null && _stopFuture == null) {
      return Future<void>.value();
    }
    if (_owner != null && !identical(owner, _owner)) {
      return Future<void>.value();
    }
    return _stopNative();
  }

  Future<void> _stopNative() => _stopFuture ??= _stopOnce().whenComplete(() {
    _stopFuture = null;
  });

  Future<void> _stopOnce() async {
    final terminal = _terminal;
    _release();
    try {
      // Callbacks have no utterance ID. Do not submit another utterance until
      // the old one has terminated. Idle stops never enter this method.
      await Future.wait<void>([_tts.stop().then<void>((_) {}), if (!_blocked && terminal != null) terminal.future]).timeout(const Duration(seconds: 1));
    } catch (_) {
      // Missing/failed acknowledgement cannot be guessed away with a delay.
      // This device driver stays text-only until the app restarts.
      _blocked = true;
      rethrow;
    }
  }
}
