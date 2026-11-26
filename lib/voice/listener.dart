import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

/// Continuous listening: restarts itself after each phrase.
/// Milestone 1 uses the Android recognizer; the next step is offline Vosk with a
/// grammar limited to chess vocabulary (see README).
class VoiceListener {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false, _active = false, _paused = false;
  List<LocaleName>? _locales;
  String? localeId;
  void Function(String text)? onFinal;
  void Function(String text)? onPartial;

  Future<bool> init() async {
    _ready = await _stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          Future.delayed(const Duration(milliseconds: 300), _listen);
        }
      },
      onError: (_) => Future.delayed(const Duration(milliseconds: 600), _listen),
    );
    return _ready;
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
            await _stt.cancel();
            _listen();
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
    await _listen();
    return true;
  }

  Future<void> stop() async {
    _active = false;
    await _stt.cancel();
  }

  /// Stop hearing while the app itself is speaking.
  Future<void> pause() async {
    _paused = true;
    if (_stt.isListening) await _stt.cancel();
  }

  Future<void> resume() async {
    _paused = false;
    await _listen();
  }

  Future<void> _listen() async {
    if (!_ready || !_active || _paused || _stt.isListening) return;
    await _stt.listen(
      onResult: (r) {
        onPartial?.call(r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          onFinal?.call(r.recognizedWords);
        }
      },
      localeId: localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      ),
    );
  }
}
