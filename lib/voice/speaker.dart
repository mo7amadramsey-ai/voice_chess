import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

/// Plays the app's own voice: pre-generated neural-voice clips
/// (assets/voice/<lang>/<id>.mp3) joined into sentences. Fully offline.
/// Two players ping-pong so the NEXT clip is already loaded while the current
/// one plays -> no gaps between words.
class Speaker {
  final List<AudioPlayer> _pl = [AudioPlayer(), AudioPlayer()];
  String lang = 'ar';
  Future<void> _chain = Future.value();

  Speaker() {
    for (final p in _pl) {
      p.setReleaseMode(ReleaseMode.stop);
    }
  }

  Future<void> say(List<String> ids) {
    final f = _chain.then((_) => _run(ids));
    _chain = f.catchError((_) {});
    return f;
  }

  Future<bool> _load(int slot, String id) async {
    try {
      await _pl[slot].setSource(AssetSource('voice/$lang/$id.mp3'));
      return true;
    } catch (_) {
      return false; // missing clip: skipped silently
    }
  }

  Future<void> _run(List<String> ids) async {
    if (ids.isEmpty) return;
    Future<bool> pre = _load(0, ids[0]);
    for (var i = 0; i < ids.length; i++) {
      final slot = i % 2;
      final ok = await pre;
      if (i + 1 < ids.length) pre = _load((i + 1) % 2, ids[i + 1]);
      if (!ok) continue;
      final p = _pl[slot];
      final done = Completer<void>();
      final sub = p.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      try {
        await p.resume();
        await done.future.timeout(const Duration(seconds: 6));
      } catch (_) {
        // playback error / timeout: move on
      } finally {
        await sub.cancel();
      }
    }
  }

  void dispose() {
    for (final p in _pl) {
      p.dispose();
    }
  }
}
