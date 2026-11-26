import 'dart:async';
import 'dart:math' as math;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Continuous, low-latency listening.
/// - Prefers the ON-DEVICE recognizer (works with no internet once the offline
///   language pack is installed on the phone).
/// - Commits early: if a partial transcript is already a complete, unambiguous
///   command and stays unchanged for ~0.55s, it is accepted without waiting for
///   the recognizer's own end-of-speech timeout.
class VoiceListener {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false, _active = false, _paused = false, _consumed = false;
  int _errors = 0;
  Timer? _restart, _stable;
  String _last = '';
  List<LocaleName>? _locales;
  String? localeId;

  bool offlineOnly = true;
  bool offlineMissing = false;

  void Function(String text)? onFinal;
  void Function(String text)? onPartial;
  void Function()? onOfflineMissing;
  bool Function(String text)? isComplete;

  Future<bool> init() async {
    _ready = await _stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') _schedule(const Duration(milliseconds: 120));
      },
      onError: _onError,
    );
    return _ready;
  }

  void _onError(SpeechRecognitionError e) {
    if (e.errorMsg.toLowerCase().contains('language') && offlineOnly && !offlineMissing) {
      offlineMissing = true; // no offline pack: fall back to the system recognizer
      onOfflineMissing?.call();
    }
    _errors++;
    _schedule(Duration(milliseconds: math.min(2000, 150 * _errors)));
  }

  void _schedule(Duration d) {
    _restart?.cancel();
    _restart = Timer(d, _listen);
  }

  Future<void> setLanguage(String lang) async {
    if (!_ready) return;
    _locales ??= await _stt.locales();
    final prefs = lang == 'ar' ? ['ar_ps', 'ar_jo', 'ar_sa', 'ar_eg', 'ar'] : ['en_us', 'en_gb', 'en'];
    for (final p in prefs) {
      for (final l in _locales!) {
        if (l.localeId.toLowerCase().replaceAll('-', '_').startsWith(p)) {
          localeId = l.localeId;
          if (_active) {
            _stable?.cancel();
            await _stt.cancel();
            _schedule(const Duration(milliseconds: 80));
          }
          return;
        }
      }
    }
  }

  Future<bool> start() async {
    if (!_ready) return false;
    _active = true;
    _paused = false;
    _errors = 0;
    await _listen();
    return true;
  }

  Future<void> stop() async {
    _active = false;
    _restart?.cancel();
    _stable?.cancel();
    await _stt.cancel();
  }

  /// Stop hearing while the app itself is speaking.
  Future<void> pause() async {
    _paused = true;
    _stable?.cancel();
    if (_stt.isListening) await _stt.cancel();
  }

  Future<void> resume() async {
    _paused = false;
    _schedule(const Duration(milliseconds: 60));
  }

  void _onResult(SpeechRecognitionResult r) {
    final t = r.recognizedWords.trim();
    if (t.isEmpty) return;
    _errors = 0;
    onPartial?.call(t);
    if (_consumed) return;
    if (r.finalResult) {
      _stable?.cancel();
      _consumed = true;
      onFinal?.call(t);
      return;
    }
    if (t != _last) {
      _last = t;
      _stable?.cancel();
      if (isComplete?.call(t) ?? false) {
        _stable = Timer(const Duration(milliseconds: 550), () => _commit(t));
      }
    }
  }

  Future<void> _commit(String t) async {
    if (_consumed || _paused || !_active) return;
    _consumed = true;
    await _stt.cancel(); // the status callback restarts listening
    onFinal?.call(t);
  }

  Future<void> _listen() async {
    if (!_ready || !_active || _paused || _stt.isListening) return;
    _consumed = false;
    _last = '';
    try {
      await _stt.listen(
        onResult: _onResult,
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(milliseconds: 1200),
        listenOptions: SpeechListenOptions(
          onDevice: offlineOnly && !offlineMissing,
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (_) {
      _schedule(const Duration(milliseconds: 500));
    }
  }
}
