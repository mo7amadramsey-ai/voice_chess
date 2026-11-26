import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:stockfish/stockfish.dart';
import 'levels.dart';

class _Cand {
  final String move;
  final int cp;
  _Cand(this.move, this.cp);
}

/// Thin wrapper around on-device Stockfish with the 18-level system.
class EngineService {
  Stockfish? _sf;
  StreamSubscription<String>? _sub;
  final Map<int, _Cand> _lines = {};
  Completer<String>? _done;
  final _rng = Random();

  Future<void> init() async {
    _sf = Stockfish();
    _sub = _sf!.stdout.listen((chunk) {
      for (final l in chunk.split('\n')) {
        final t = l.trim();
        if (t.isNotEmpty) _onLine(t);
      }
    });
    var waited = 0;
    while (_sf!.state.value != StockfishState.ready) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (++waited > 150) throw StateError('Stockfish did not start');
    }
    _send('uci');
    final cores = Platform.numberOfProcessors;
    _send('setoption name Threads value ${(cores - 1).clamp(1, 4)}');
    _send('setoption name Hash value 64');
    _send('isready');
  }

  /// Clears the transposition table between games.
  void newGame() {
    stop();
    _send('ucinewgame');
    _send('isready');
  }

  void _send(String c) => _sf!.stdin = c;

  void stop() {
    if (_done != null && !_done!.isCompleted) _send('stop');
  }

  void _onLine(String line) {
    if (line.startsWith('info') && line.contains(' pv ')) {
      final pv = RegExp(r' pv (\S+)').firstMatch(line);
      if (pv == null) return;
      final k = int.tryParse(RegExp(r'multipv (\d+)').firstMatch(line)?.group(1) ?? '1') ?? 1;
      final cp = RegExp(r'score cp (-?\d+)').firstMatch(line);
      final mate = RegExp(r'score mate (-?\d+)').firstMatch(line);
      int score;
      if (cp != null) {
        score = int.parse(cp.group(1)!);
      } else if (mate != null) {
        final m = int.parse(mate.group(1)!);
        score = m > 0 ? 100000 - m : -100000 - m;
      } else {
        return;
      }
      _lines[k] = _Cand(pv.group(1)!, score);
    } else if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      if (_done != null && !_done!.isCompleted) {
        _done!.complete(parts.length > 1 ? parts[1] : '');
      }
    }
  }

  /// Returns a UCI move (e.g. "e2e4", "e7e8q") or null.
  Future<String?> think(String fen, Level lv) async {
    _lines.clear();
    _done = Completer<String>();
    _send('setoption name Skill Level value 20');
    if (lv.full) {
      _send('setoption name UCI_LimitStrength value false');
      _send('setoption name MultiPV value 1');
    } else if (lv.native) {
      _send('setoption name UCI_LimitStrength value true');
      _send('setoption name UCI_Elo value ${lv.elo}');
      _send('setoption name MultiPV value 1');
    } else {
      _send('setoption name UCI_LimitStrength value false');
      _send('setoption name MultiPV value ${lv.multiPv}');
    }
    _send('position fen $fen');
    _send(lv.weak ? 'go depth ${lv.depth}' : 'go movetime ${lv.movetimeMs}');
    final best = await _done!.future.timeout(const Duration(seconds: 25), onTimeout: () {
      _send('stop');
      return '';
    });
    _done = null;
    if (best.isEmpty || best == '(none)') return null;
    return lv.weak ? _humanize(best, lv) : best;
  }

  /// Weak levels: sample among the top lines, plus an occasional outright blunder.
  String _humanize(String best, Level lv) {
    final c = _lines.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (c.length < 2) return best;
    final w = lv.weakness;
    if (_rng.nextDouble() < w * 0.30) {
      return c[_rng.nextInt(c.length)].value.move;
    }
    final top = c.first.value.cp;
    final temp = 30 + w * 350;
    final weights = [
      for (final e in c) exp(-((top - e.value.cp).clamp(0, 2000)) / temp),
    ];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var r = _rng.nextDouble() * total;
    for (var i = 0; i < c.length; i++) {
      r -= weights[i];
      if (r <= 0) return c[i].value.move;
    }
    return best;
  }

  void dispose() {
    _sub?.cancel();
    _sf?.dispose();
  }
}
