/// 18 strength levels (1..18) on an Elo-like scale.
/// Stockfish natively supports UCI_Elo from ~1320 up to ~3190, so below that
/// we weaken it ourselves (shallow depth + sampling among MultiPV lines).
class Level {
  final int index, elo;
  const Level(this.index, this.elo);

  bool get full => elo >= 3200; // unrestricted Stockfish
  bool get native => elo >= 1320 && !full; // UCI_LimitStrength + UCI_Elo
  bool get weak => elo < 1320; // custom "human-like" weakening

  int get depth => elo < 500 ? 1 : (elo < 900 ? 2 : 3);
  int get multiPv => 8;
  double get weakness => ((1320 - elo) / 1220).clamp(0.0, 1.0).toDouble();
  int get movetimeMs => full ? 1500 : 300 + (elo - 1320) ~/ 3;
}

const List<Level> kLevels = [
  Level(1, 100), Level(2, 200), Level(3, 300), Level(4, 400), Level(5, 500),
  Level(6, 600), Level(7, 700), Level(8, 800), Level(9, 1000), Level(10, 1200),
  Level(11, 1500), Level(12, 1800), Level(13, 2000), Level(14, 2200),
  Level(15, 2500), Level(16, 2800), Level(17, 3000), Level(18, 3200),
];

Level levelForElo(int elo) {
  var best = kLevels.first;
  for (final l in kLevels) {
    if ((l.elo - elo).abs() < (best.elo - elo).abs()) best = l;
  }
  return best;
}
