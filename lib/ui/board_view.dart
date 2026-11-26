import 'package:flutter/material.dart';
import '../core/game_controller.dart';

class BoardView extends StatelessWidget {
  final GameController c;
  const BoardView(this.c, {super.key});

  static const _glyph = {'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟'};
  static const _light = Color(0xFFEBD9B4), _dark = Color(0xFFA67B52);

  @override
  Widget build(BuildContext context) {
    final pieces = c.pieces, targets = c.targets, king = c.checkedKing;
    return Directionality(
      textDirection: TextDirection.ltr, // the board is always a..h left to right
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: LayoutBuilder(builder: (ctx, bc) {
              final sz = bc.maxWidth / 8;
              return Column(children: [
                for (var row = 0; row < 8; row++)
                  Expanded(
                    child: Row(children: [
                      for (var col = 0; col < 8; col++)
                        Expanded(child: _cell(row, col, sz, pieces, targets, king)),
                    ]),
                  ),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _cell(int row, int col, double sz, Map<String, String> pieces, Set<String> targets, String? king) {
    final file = c.flipped ? 7 - col : col;
    final rank = c.flipped ? row : 7 - row;
    final sq = '${'abcdefgh'[file]}${rank + 1}';
    final dark = (file + rank) % 2 == 0;
    var bg = dark ? _dark : _light;
    if (sq == c.lastFrom || sq == c.lastTo) bg = Color.alphaBlend(const Color(0x66F2C94C), bg);
    if (sq == c.selected) bg = Color.alphaBlend(const Color(0x8856C271), bg);
    if (sq == king) bg = Color.alphaBlend(const Color(0xAAE5484D), bg);
    final p = pieces[sq];
    final isWhite = p != null && p == p.toUpperCase();
    final labelColor = dark ? _light : _dark;

    return GestureDetector(
      onTap: () => c.tapSquare(sq),
      child: Container(
        color: bg,
        child: Stack(children: [
          if (p != null)
            Center(
              child: Text(
                '${_glyph[p.toLowerCase()]}\uFE0E',
                style: TextStyle(
                  fontSize: sz * 0.78,
                  height: 1.0,
                  color: isWhite ? const Color(0xFFFFFDF5) : const Color(0xFF15161A),
                  shadows: [
                    Shadow(color: isWhite ? Colors.black87 : Colors.white30, blurRadius: 2, offset: const Offset(0, 1)),
                  ],
                ),
              ),
            ),
          if (targets.contains(sq))
            Center(
              child: Container(
                width: p == null ? sz * 0.3 : sz * 0.9,
                height: p == null ? sz * 0.3 : sz * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p == null ? const Color(0x5527AE60) : Colors.transparent,
                  border: p == null ? null : Border.all(color: const Color(0x8827AE60), width: 3),
                ),
              ),
            ),
          if (col == 0)
            Positioned(left: 3, top: 1, child: Text('${rank + 1}', style: TextStyle(fontSize: sz * 0.2, color: labelColor, fontWeight: FontWeight.bold))),
          if (row == 7)
            Positioned(right: 3, bottom: 1, child: Text('abcdefgh'[file], style: TextStyle(fontSize: sz * 0.2, color: labelColor, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }
}
