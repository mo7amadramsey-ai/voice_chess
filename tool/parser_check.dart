// Run: dart tool/parser_check.dart   (pure Dart, no Flutter needed)
import '../lib/voice/command_parser.dart';

LegalMove mv(String san, String from, String to) =>
    LegalMove.fromMap({'san': san, 'from': from, 'to': to});

final legal = <LegalMove>[
  mv('Nf3', 'g1', 'f3'),
  mv('Ndf3', 'd2', 'f3'),
  mv('e4', 'e2', 'e4'),
  mv('Nce4', 'c3', 'e4'),
  mv('Bc4', 'f1', 'c4'),
  mv('O-O', 'e1', 'g1'),
  mv('O-O-O', 'e1', 'c1'),
  mv('b8=Q', 'b7', 'b8'),
  mv('b8=R', 'b7', 'b8'),
  mv('b8=B', 'b7', 'b8'),
  mv('b8=N', 'b7', 'b8'),
];

var fails = 0, total = 0;
void check(String said, bool Function(Parsed p) ok, String label) {
  total++;
  final p = CommandParser.parse(said, legal);
  if (!ok(p)) {
    fails++;
    print('FAIL  "$said"  -> ${p.runtimeType} ${p is PMove ? p.move.san : ''}   (expected: $label)');
  }
}

bool san(Parsed p, String s, {bool confirm = false}) =>
    p is PMove && p.move.san == s && p.confirm == confirm;
bool cmd(Parsed p, Cmd c, [String? arg]) => p is PCommand && p.cmd == c && (arg == null || p.arg == arg);

void main() {
  // moves: Arabic / English / mixed / noisy
  check('جندي اي 4', (p) => san(p, 'e4'), 'e4');
  check('e4', (p) => san(p, 'e4'), 'e4 (bare square = pawn)');
  check('E 4', (p) => san(p, 'e4'), 'e4');
  check('بون e4', (p) => san(p, 'e4'), 'e4');
  check('knight e4', (p) => san(p, 'Nce4'), 'Nce4');
  check('نايت اي ٤', (p) => san(p, 'Nce4'), 'Nce4 (Arabic digit)');
  check('Night E4', (p) => san(p, 'Nce4'), 'Nce4 (night = knight)');
  check('حصان على اف 3', (p) => p is PAmbiguous, 'ambiguous (2 knights reach f3)');
  check('الحصان اف ثلاثة', (p) => p is PAmbiguous, 'ambiguous with ال + Arabic number');
  check('حصان دي 2 الى اف 3', (p) => san(p, 'Ndf3'), 'Ndf3 (from-square resolves)');
  check('knight d2 to f3', (p) => san(p, 'Ndf3'), 'Ndf3');
  check('يا حصان d2 إلى f3', (p) => san(p, 'Ndf3'), 'Ndf3 with filler words');
  check('بيشوب سي 4', (p) => san(p, 'Bc4'), 'Bc4');
  check('فيل c4', (p) => san(p, 'Bc4'), 'Bc4');
  check('البيشوب جيم 4', (p) => san(p, 'Bc4'), 'Bc4 (جيم = c)');
  check('حصان c4', (p) => san(p, 'Bc4', confirm: true), 'Bc4 with confirm (wrong piece)');
  check('حصان f6', (p) => p is PIllegal, 'illegal');
  check('تبييت قصير', (p) => san(p, 'O-O'), 'O-O');
  check('castle long', (p) => san(p, 'O-O-O'), 'O-O-O');
  check('تبييت', (p) => p is PAmbiguous, 'ambiguous castle');
  check('b8 وزير', (p) => san(p, 'b8=Q'), 'b8=Q');
  check('b8 knight', (p) => san(p, 'b8=N'), 'b8=N');
  check('b8', (p) => san(p, 'b8=Q'), 'default queen');

  // commands
  check('نيو جيم', (p) => cmd(p, Cmd.newGame) && (p as PCommand).arg == null, 'newGame');
  check('نيو جيم وايت', (p) => cmd(p, Cmd.newGame, 'w'), 'newGame white');
  check('نيو جيم بلاك', (p) => cmd(p, Cmd.newGame, 'b'), 'newGame black');
  check('new game black', (p) => cmd(p, Cmd.newGame, 'b'), 'newGame black');
  check('ابدأ لعبة جديدة بالأسود', (p) => cmd(p, Cmd.newGame, 'b'), 'newGame black');
  check('لعبة جديدة بالأبيض', (p) => cmd(p, Cmd.newGame, 'w'), 'newGame white');
  check('مستوى 1200', (p) => cmd(p, Cmd.level, 'elo:1200'), 'level elo');
  check('level 5', (p) => cmd(p, Cmd.level, 'idx:5'), 'level idx');
  check('تراجع', (p) => cmd(p, Cmd.undo), 'undo');
  check('hint', (p) => cmd(p, Cmd.hint), 'hint');
  check('استسلم', (p) => cmd(p, Cmd.resign), 'resign');
  check('كرر', (p) => cmd(p, Cmd.repeat), 'repeat');
  check('نعم', (p) => cmd(p, Cmd.yes), 'yes');
  check('لا', (p) => cmd(p, Cmd.no), 'no');
  check('blah blah', (p) => p is PUnknown, 'unknown');

  print('${total - fails}/$total passed');
}
