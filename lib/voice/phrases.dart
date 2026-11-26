/// Turns a SAN move into the list of voice-clip ids to play.
List<String> moveClips(String san) {
  final ids = <String>[];
  if (san.startsWith('O-O-O')) {
    ids.add('castle_long');
  } else if (san.startsWith('O-O')) {
    ids.add('castle_short');
  } else {
    final piece = 'KQRBN'.contains(san[0]) ? san[0].toLowerCase() : 'p';
    ids.add('piece_$piece');
    ids.add(san.contains('x') ? 'takes' : 'to');
    final sq = RegExp(r'[a-h][1-8]').allMatches(san).last.group(0)!;
    ids..add('file_${sq[0]}')..add('rank_${sq[1]}');
    final pm = RegExp(r'=([QRBN])').firstMatch(san);
    if (pm != null) ids..add('promote')..add('piece_${pm.group(1)!.toLowerCase()}');
  }
  if (san.endsWith('#')) {
    ids.add('mate');
  } else if (san.endsWith('+')) {
    ids.add('check');
  }
  return ids;
}
