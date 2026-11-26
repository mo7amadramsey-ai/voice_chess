import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

/// Plays the app's own voice: pre-generated neural-voice clips (assets/voice/<lang>/<id>.mp3)
/// joined into sentences. Same voice every time, offline, zero latency.
class Speaker {
  final AudioPlayer _p = AudioPlayer();
  String lang = 'ar';
  Future<void> _chain = Future.value();

  Future<void> say(List<String> ids) {
    _chain = _chain.then((_) => _run(ids));
    return _chain;
  }

  Future<void> _run(List<String> ids) async {
    for (final id in ids) {
      final done = Completer<void>();
      final sub = _p.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      try {
        await _p.play(AssetSource('voice/$lang/$id.mp3'));
        await done.future.timeout(const Duration(seconds: 6));
      } catch (_) {
        // missing clip or playback error: skip silently
      } finally {
        await sub.cancel();
      }
    }
  }

  void dispose() => _p.dispose();
}
