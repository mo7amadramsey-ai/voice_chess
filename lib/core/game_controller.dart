import 'dart:async';
import 'dart:math';
import 'package:chess/chess.dart' as ch;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../voice/command_parser.dart';
import '../voice/listener.dart';
import '../voice/phrases.dart';
import '../voice/speaker.dart';
import 'engine.dart';
import 'levels.dart';

class GameController extends ChangeNotifier {
  final ch.Chess game = ch.Chess();
  final EngineService engine = EngineService();
  final Speaker speaker = Speaker();
  final VoiceListener listener = VoiceListener();

  bool humanWhite = true, flipped = false, voiceOn = false, soundOn = true;
  bool ready = false, thinking = false, over = false;
  Level level = kLevels[7];
  String banner = 'جارٍ التحميل…', heard = '';
  String? lastFrom, lastTo, selected;
  final List<String> sans = [];

  LegalMove? _confirm;
  bool _busy = false;
  int _gen = 0;
  SharedPreferences? _p;

  String get lang => speaker.lang;
  bool get whiteToMove => game.turn == ch.Color.WHITE;
  bool get humanTurn => whiteToMove == humanWhite;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    level = levelForElo(_p!.getInt('elo') ?? 800);
    humanWhite = _p!.getBool('white') ?? true;
    speaker.lang = _p!.getString('lang') ?? 'ar';
    soundOn = _p!.getBool('sound') ?? true;
    try {
      await engine.init();
    } catch (_) {
      banner = 'تعذّر تشغيل المحرك';
      notifyListeners();
      return;
    }
    listener.onFinal = handleSpeech;
    listener.onPartial = (t) {
      heard = t;
      notifyListeners();
    };
    await listener.init();
    await listener.setLanguage(speaker.lang);
    ready = true;
    banner = humanWhite ? 'تلعب بالأبيض — ابدأ' : 'تلعب بالأسود';
    notifyListeners();
    if (!humanWhite) await _engineTurn();
  }

  // ---------- board state for the UI ----------
  Map<String, String> get pieces {
    final out = <String, String>{};
    final rows = game.fen.split(' ')[0].split('/');
    for (var r = 0; r < 8; r++) {
      var f = 0;
      for (final sym in rows[r].split('')) {
        final n = int.tryParse(sym);
        if (n != null) {
          f += n;
        } else {
          out['${'abcdefgh'[f]}${8 - r}'] = sym;
          f++;
        }
      }
    }
    return out;
  }

  Set<String> get targets =>
      selected == null ? <String>{} : _legal().where((m) => m.from == selected).map((m) => m.to).toSet();

  String? get checkedKing {
    if (!game.in_check) return null;
    final k = whiteToMove ? 'K' : 'k';
    for (final e in pieces.entries) {
      if (e.value == k) return e.key;
    }
    return null;
  }

  List<LegalMove> _legal() =>
      game.moves({'verbose': true}).map((e) => LegalMove.fromMap(e as Map)).toList();

  // ---------- touch play ----------
  void tapSquare(String sq) {
    if (!ready || thinking || over || !humanTurn) return;
    final legal = _legal();
    if (selected != null) {
      final mv = legal.where((m) => m.from == selected && m.to == sq).toList();
      if (mv.isNotEmpty) {
        final m = mv.firstWhere((x) => x.promo == null || x.promo == 'q', orElse: () => mv.first);
        selected = null;
        _humanPlay(m, announce: false);
        return;
      }
    }
    selected = legal.any((m) => m.from == sq) ? sq : null;
    notifyListeners();
  }

  // ---------- game flow ----------
  bool _apply(LegalMove m) {
    final dynamic r = game.move({
      'from': m.from,
      'to': m.to,
      if (m.promo != null) 'promotion': m.promo,
    });
    if (r == false || r == null) return false;
    sans.add(m.san);
    lastFrom = m.from;
    lastTo = m.to;
    selected = null;
    _confirm = null;
    notifyListeners();
    return true;
  }

  Future<void> _say(List<String> ids) async {
    if (!soundOn) return;
    if (voiceOn) await listener.pause();
    await speaker.say(ids);
    if (voiceOn) await listener.resume();
  }

  Future<void> _humanPlay(LegalMove m, {required bool announce}) async {
    if (!_apply(m)) return;
    if (announce) await _say(moveClips(m.san));
    if (await _checkEnd(humanMoved: true)) return;
    await _engineTurn();
  }

  Future<bool> _checkEnd({required bool humanMoved}) async {
    if (game.in_checkmate) {
      over = true;
      banner = humanMoved ? 'كش مات — فزت!' : 'كش مات — فاز المحرك';
      notifyListeners();
      await _say([humanMoved ? 'you_won' : 'i_won']);
      return true;
    }
    if (game.in_stalemate) {
      over = true;
      banner = 'جمود — تعادل';
      notifyListeners();
      await _say(['stalemate']);
      return true;
    }
    if (game.in_draw) {
      over = true;
      banner = 'تعادل';
      notifyListeners();
      await _say(['draw']);
      return true;
    }
    return false;
  }

  Future<void> _engineTurn() async {
    if (_busy || over) return;
    final gen = _gen;
    _busy = true;
    thinking = true;
    banner = 'المحرك يفكّر…';
    notifyListeners();
    try {
      final uci = await engine.think(game.fen, level);
      if (gen != _gen || uci == null || uci.length < 4) return;
      final from = uci.substring(0, 2), to = uci.substring(2, 4);
      final promo = uci.length > 4 ? uci[4] : null;
      final cand = _legal().where((m) => m.from == from && m.to == to).toList();
      if (cand.isEmpty) return;
      final m = cand.firstWhere((x) => promo == null || x.promo == promo, orElse: () => cand.first);
      thinking = false;
      if (!_apply(m)) return;
      banner = 'لعب المحرك ${m.san}';
      notifyListeners();
      await _say(moveClips(m.san));
      if (await _checkEnd(humanMoved: false)) return;
      banner = 'دورك';
    } finally {
      _busy = false;
      thinking = false;
      notifyListeners();
    }
  }

  Future<void> newGame({bool? white}) async {
    if (!ready) return;
    _gen++;
    engine.stop();
    for (var i = 0; i < 40 && _busy; i++) {
      await Future.delayed(const Duration(milliseconds: 75));
    }
    if (white != null) humanWhite = white;
    _p?.setBool('white', humanWhite);
    game.reset();
    sans.clear();
    lastFrom = lastTo = selected = null;
    over = false;
    _confirm = null;
    banner = humanWhite ? 'تلعب بالأبيض' : 'تلعب بالأسود';
    notifyListeners();
    await _say(['new_game', humanWhite ? 'you_white' : 'you_black']);
    if (!humanWhite) await _engineTurn();
  }

  Future<void> undo() async {
    if (!ready || _busy || sans.isEmpty) return;
    do {
      final dynamic r = game.undo();
      if (r == null || r == false) break;
      if (sans.isNotEmpty) sans.removeLast();
    } while (!humanTurn);
    over = false;
    lastFrom = lastTo = selected = null;
    banner = 'تراجعت عن النقلة';
    notifyListeners();
    await _say(['undo_ok']);
    if (!humanTurn) await _engineTurn();
  }

  Future<void> hint() async {
    if (!ready || _busy || over || !humanTurn) return;
    _busy = true;
    thinking = true;
    banner = 'أفكّر لك…';
    notifyListeners();
    try {
      final uci = await engine.think(game.fen, kLevels.last);
      if (uci == null || uci.length < 4) return;
      final cand = _legal().where((m) => m.from == uci.substring(0, 2) && m.to == uci.substring(2, 4)).toList();
      if (cand.isEmpty) return;
      final m = cand.first;
      thinking = false;
      banner = 'نصيحة: ${m.san}';
      notifyListeners();
      await _say(['hint_intro', ...moveClips(m.san)]);
    } finally {
      _busy = false;
      thinking = false;
      notifyListeners();
    }
  }

  Future<void> resign() async {
    if (over) return;
    over = true;
    banner = 'استسلمت';
    notifyListeners();
    await _say(['resigned']);
  }

  void setLevel(String arg) {
    final n = int.tryParse(arg.split(':').last) ?? 800;
    level = arg.startsWith('idx:') ? kLevels[n.clamp(1, 18).toInt() - 1] : levelForElo(n);
    _p?.setInt('elo', level.elo);
    notifyListeners();
  }

  void pickLevel(Level l) {
    level = l;
    _p?.setInt('elo', l.elo);
    notifyListeners();
  }

  void flip() {
    flipped = !flipped;
    notifyListeners();
  }

  void toggleSound() {
    soundOn = !soundOn;
    _p?.setBool('sound', soundOn);
    notifyListeners();
  }

  Future<void> setLang(String l) async {
    speaker.lang = l;
    _p?.setString('lang', l);
    await listener.setLanguage(l);
    notifyListeners();
  }

  Future<void> toggleVoice() async {
    if (voiceOn) {
      voiceOn = false;
      await listener.stop();
      banner = 'توقف الاستماع';
    } else {
      final ok = await listener.start();
      voiceOn = ok;
      banner = ok ? 'أستمع… قل نقلتك' : 'الميكروفون غير متاح — تحقّق من الأذونات';
    }
    notifyListeners();
  }

  // ---------- voice / typed commands ----------
  Future<void> handleSpeech(String text) async {
    if (!ready) return;
    heard = text;
    notifyListeners();
    final p = CommandParser.parse(text, _legal());

    if (_confirm != null) {
      final m = _confirm!;
      _confirm = null;
      if (p is PCommand && p.cmd == Cmd.yes) return _humanPlay(m, announce: true);
      if (p is PCommand && p.cmd == Cmd.no) {
        banner = 'حسنًا، أعد النقلة';
        notifyListeners();
        return;
      }
    }
    if (p is PCommand) return _command(p);
    if (p is PMove) {
      if (!humanTurn || _busy || over) return;
      if (p.confirm) {
        _confirm = p.move;
        banner = 'هل تقصد ${p.move.san}؟';
        notifyListeners();
        return _say(['did_you_mean', ...moveClips(p.move.san)]);
      }
      return _humanPlay(p.move, announce: true);
    }
    if (p is PAmbiguous) {
      banner = 'أي قطعة؟ كرّر مع مربع الانطلاق';
      notifyListeners();
      return _say(['which_piece']);
    }
    if (p is PIllegal) {
      banner = 'نقلة غير ممكنة';
      notifyListeners();
      return _say(['illegal']);
    }
    banner = 'لم أفهم: $text';
    notifyListeners();
    return _say(['not_understood']);
  }

  Future<void> _command(PCommand p) async {
    switch (p.cmd) {
      case Cmd.newGame:
        return newGame(white: p.arg == 'w' ? true : p.arg == 'b' ? false : p.arg == 'r' ? Random().nextBool() : null);
      case Cmd.undo:
        return undo();
      case Cmd.hint:
        return hint();
      case Cmd.resign:
        return resign();
      case Cmd.repeat:
        if (sans.isNotEmpty) await _say(moveClips(sans.last));
        return;
      case Cmd.flip:
        flip();
        return;
      case Cmd.level:
        setLevel(p.arg!);
        await _say(['level_set']);
        return;
      case Cmd.stopListening:
        if (voiceOn) await toggleVoice();
        return;
      case Cmd.yes:
      case Cmd.no:
        return;
    }
  }

  @override
  void dispose() {
    listener.stop();
    engine.dispose();
    speaker.dispose();
    super.dispose();
  }
}
