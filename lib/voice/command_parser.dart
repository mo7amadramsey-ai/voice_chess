// Pure Dart (no Flutter imports). The "voice brain": turns a noisy transcript
// into either a command or a move, resolved against the LEGAL moves of the
// current position (so mis-hearings are corrected by chess itself).
import 'dart:math' show min;
import 'lexicon.dart';

/// A legal move in the current position (built from chess.js-style verbose maps).
class LegalMove {
  final String san, from, to, piece;
  final String? promo;
  const LegalMove({
    required this.san,
    required this.from,
    required this.to,
    required this.piece,
    this.promo,
  });

  factory LegalMove.fromMap(Map m) {
    final san = m['san'].toString();
    final c = san[0];
    final piece = 'KQRBN'.contains(c) ? c.toLowerCase() : (c == 'O' ? 'k' : 'p');
    final pm = RegExp(r'=([QRBN])').firstMatch(san);
    return LegalMove(
      san: san,
      from: m['from'].toString(),
      to: m['to'].toString(),
      piece: piece,
      promo: pm?.group(1)?.toLowerCase(),
    );
  }

  bool get isCastle => san.startsWith('O');
  bool get isLongCastle => san.startsWith('O-O-O');
}

enum Cmd { newGame, undo, hint, resign, repeat, flip, level, yes, no, stopListening }

sealed class Parsed {
  const Parsed();
}

class PMove extends Parsed {
  final LegalMove move;
  final bool confirm; // heard something that doesn't fully match -> ask first
  const PMove(this.move, {this.confirm = false});
}

class PAmbiguous extends Parsed {
  final List<LegalMove> options;
  const PAmbiguous(this.options);
}

class PIllegal extends Parsed {
  final String what;
  const PIllegal(this.what);
}

class PCommand extends Parsed {
  final Cmd cmd;
  final String? arg; // newGame: w|b|r ; level: elo:N | idx:N
  const PCommand(this.cmd, [this.arg]);
}

class PUnknown extends Parsed {
  const PUnknown();
}

Map<String, String> _invert(Map<String, List<String>> m) {
  final r = <String, String>{};
  m.forEach((k, ws) {
    for (final w in ws) {
      r[normalize(w)] = k;
    }
  });
  return r;
}

final Map<String, String> _pieceIdx = _invert(kPieces);
final Map<String, String> _fileIdx = _invert(kFiles);
final Map<String, String> _rankIdx = _invert(kRanks);

int _lev(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

class _Atom {
  final String kind, v; // kind: piece | file | rank
  const _Atom(this.kind, this.v);
}

_Atom? _exact(String t) {
  final r = _rankIdx[t];
  if (r != null) return _Atom('rank', r);
  final f = _fileIdx[t];
  if (f != null) return _Atom('file', f);
  final p = _pieceIdx[t];
  if (p != null) return _Atom('piece', p);
  return null;
}

_Atom? _atom(String t) {
  var x = _exact(t);
  if (x != null) return x;
  if (t.startsWith('ال') && t.length > 3) {
    x = _exact(t.substring(2)); // "الحصان" -> "حصان"
    if (x != null) return x;
  }
  if (t.length >= 5) {
    // fuzzy: one edit away from a long-enough lexicon word
    _Atom? best;
    var bd = 2;
    void scan(Map<String, String> m, String kind) {
      m.forEach((w, v) {
        if (w.length >= 5 && (w.length - t.length).abs() <= 1) {
          final d = _lev(t, w);
          if (d < bd) {
            bd = d;
            best = _Atom(kind, v);
          }
        }
      });
    }

    scan(_pieceIdx, 'piece');
    scan(_fileIdx, 'file');
    scan(_rankIdx, 'rank');
    return best;
  }
  return null;
}

class _Scan {
  final String? mover, promo;
  final List<String> squares;
  const _Scan(this.mover, this.squares, this.promo);
}

_Scan _scan(String s) {
  final squares = <String>[];
  String? pendingFile;
  final pcs = <(int, String)>[];
  for (final t in s.split(' ')) {
    final a = _atom(t);
    if (a == null) {
      pendingFile = null;
      continue;
    }
    switch (a.kind) {
      case 'file':
        pendingFile = a.v;
      case 'rank':
        if (pendingFile != null) squares.add('$pendingFile${a.v}');
        pendingFile = null;
      default:
        pcs.add((squares.length, a.v));
        pendingFile = null;
    }
  }
  String? mover;
  for (final p in pcs) {
    if (p.$1 == 0) {
      mover = p.$2;
      break;
    }
  }
  String? promo;
  for (final p in pcs.reversed) {
    if (p.$1 >= 1 && 'qrbn'.contains(p.$2)) {
      promo = p.$2;
      break;
    }
  }
  return _Scan(mover, squares, promo);
}

bool _has(String s, List<String> ws) {
  final padded = ' $s ';
  return ws.any((w) => padded.contains(' ${normalize(w)} '));
}

class CommandParser {
  static Parsed parse(String raw, List<LegalMove> legal) {
    final s = normalize(raw);
    if (s.isEmpty) return const PUnknown();

    final lvl = _level(s);
    if (lvl != null) return lvl;
    final ng = _newGame(s);
    if (ng != null) return ng;

    final castle = _castle(s, legal);
    if (castle != null) return castle;

    final sc = _scan(s);
    if (sc.squares.isEmpty) {
      final c = _simple(s);
      return c ?? const PUnknown();
    }
    return _resolve(sc, legal);
  }

  static PCommand? _level(String s) {
    if (!_has(s, ['مستوى', 'level', 'لفل', 'ليفل', 'رتبة', 'تصنيف', 'elo', 'ايلو'])) return null;
    final m = RegExp(r'(^| )(\d{1,4})( |$)').firstMatch(s);
    if (m == null) return null;
    final n = int.parse(m.group(2)!);
    return PCommand(Cmd.level, n > 18 ? 'elo:$n' : 'idx:$n');
  }

  static PCommand? _newGame(String s) {
    final white = _has(s, ['وايت', 'white', 'وايط']) || s.contains('ابيض');
    final black = _has(s, ['بلاك', 'black', 'بلك']) || s.contains('اسود');
    final rnd = _has(s, ['عشوائي', 'random']);
    final isNew = _has(s, ['نيو', 'new', 'جديدة', 'جديد', 'ابدا', 'start', 'restart', 'ريستارت', 'نيوو']);
    final isGame = _has(s, ['جيم', 'game', 'لعبة', 'مباراة', 'غيم', 'قيم']);
    if (isNew && (isGame || white || black || rnd)) {
      return PCommand(Cmd.newGame, white ? 'w' : black ? 'b' : rnd ? 'r' : null);
    }
    return null;
  }

  static Parsed? _castle(String s, List<LegalMove> legal) {
    final isCastle = _has(s, ['تبييت', 'تبيت', 'castle', 'castling', 'castles']) ||
        RegExp(r'(^| )(o o|0 0)( |$)').hasMatch(s);
    if (!isCastle) return null;
    final cs = legal.where((m) => m.isCastle).toList();
    if (cs.isEmpty) return const PIllegal('castle');
    final long = _has(s, ['طويل', 'طويلة', 'long', 'queenside', 'كبير', 'كبيرة']) ||
        RegExp(r'(^| )(o o o|0 0 0)( |$)').hasMatch(s);
    final short = !long && _has(s, ['قصير', 'قصيرة', 'short', 'kingside', 'صغير', 'صغيرة']);
    if (long) {
      final l = cs.where((m) => m.isLongCastle).toList();
      return l.isEmpty ? const PIllegal('castle') : PMove(l.first);
    }
    final shorts = cs.where((m) => !m.isLongCastle).toList();
    if (short || RegExp(r'(^| )(o o|0 0)( |$)').hasMatch(s)) {
      return shorts.isEmpty ? const PIllegal('castle') : PMove(shorts.first);
    }
    return cs.length == 1 ? PMove(cs.first) : PAmbiguous(cs);
  }

  static PCommand? _simple(String s) {
    final toks = s.split(' ');
    if (toks.length <= 2) {
      if (toks.every((t) => _has(t, ['نعم', 'ايوه', 'ايوا', 'yes', 'yeah', 'اكيد', 'تمام', 'صح', 'اوكي', 'ok']))) {
        return const PCommand(Cmd.yes);
      }
      if (toks.every((t) => _has(t, ['لا', 'no', 'nope', 'غلط', 'كلا']))) {
        return const PCommand(Cmd.no);
      }
    }
    if (_has(s, ['تراجع', 'ارجع', 'رجوع', 'الغي', 'undo', 'رجعها'])) return const PCommand(Cmd.undo);
    if (_has(s, ['تلميح', 'hint', 'ساعدني', 'ساعد', 'اقترح', 'help', 'نصيحة'])) return const PCommand(Cmd.hint);
    if (_has(s, ['استسلم', 'استسلام', 'resign', 'انسحب'])) return const PCommand(Cmd.resign);
    if (_has(s, ['كرر', 'repeat', 'عيد', 'اعد', 'اعيد'])) return const PCommand(Cmd.repeat);
    if (_has(s, ['اقلب', 'قلب', 'flip'])) return const PCommand(Cmd.flip);
    if (_has(s, ['توقف', 'stop', 'كفاية', 'اسكت'])) return const PCommand(Cmd.stopListening);
    return null;
  }

  static Parsed _resolve(_Scan sc, List<LegalMove> legal) {
    final to = sc.squares.last;
    final from = sc.squares.length > 1 ? sc.squares[sc.squares.length - 2] : null;
    var c = legal.where((m) => m.to == to).toList();
    if (c.isEmpty) return PIllegal(to);
    var confirm = false;

    if (from != null) {
      final cf = c.where((m) => m.from == from).toList();
      if (cf.isNotEmpty) {
        c = cf;
      } else {
        confirm = true; // from-square didn't match: fall back, but ask
      }
    }
    if (sc.mover != null) {
      final cp = c.where((m) => m.piece == sc.mover).toList();
      if (cp.isNotEmpty) {
        c = cp;
      } else {
        confirm = true; // heard a piece that cannot go there
      }
    } else if (from == null) {
      final pawns = c.where((m) => m.piece == 'p').toList();
      if (pawns.isNotEmpty) c = pawns; // bare "e4" means the pawn move
    }
    if (c.any((m) => m.promo != null)) {
      final want = sc.promo ?? 'q';
      final pm = c.where((m) => m.promo == want).toList();
      if (pm.isNotEmpty) c = pm;
    }
    if (c.length == 1) return PMove(c.first, confirm: confirm);
    return PAmbiguous(c);
  }
}
