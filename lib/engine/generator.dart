import 'dart:math';

import '../games.dart';
import 'frac.dart';
import 'solver.dart';

const int minCards = 4;
const int maxCards = 9;

/// Beyond this many cards, finding every all-card solution gets too slow.
const int maxUseAllCards = 6;

final Frac classicTarget = Frac(24);

bool isClassic(Frac target, int cards, bool useAll) => target == classicTarget && cards == 4 && useAll;

/// Search limits per hand size, tuned to keep each analysis to tens of ms.
Solver makeSolver(Frac? target, int cards, bool useAll) {
  if (useAll) return Solver(target, useAll: true, pruneK: 300);
  return switch (cards) {
    <= 6 => Solver(target, useAll: false, pruneK: 300),
    7 => Solver(target, useAll: false, pruneK: 120, maxRootSize: 6),
    8 => Solver(target, useAll: false, pruneK: 300, maxRootSize: 5),
    _ => Solver(target, useAll: false, pruneK: 120, maxRootSize: 5),
  };
}

class RankedHand {
  final List<int> hand;
  final double score;
  final List<Step> solution;
  const RankedHand(this.hand, this.score, this.solution);
}

/// Deals [n] cards from a standard 52-card deck (ace = 1 … king = 13).
List<int> dealHand(int n, Random rng) {
  final deck = [for (var v = 1; v <= maxCard; ++v) for (var s = 0; s < 4; ++s) v]..shuffle(rng);
  return deck.sublist(0, n)..sort();
}

class PoolRequest {
  final String target;
  final int cards;
  final bool useAll;
  final int deals;
  final int seed;
  const PoolRequest(this.target, this.cards, this.useAll, {this.deals = 30, this.seed = 0});
}

/// Solvable hands for a configuration, easiest first. Runs in a background isolate.
///
/// Four-card hands are enumerated exhaustively (the classic 24 game keeps its
/// empirically measured ordering); larger hands are a random sample of [deals].
List<RankedHand> buildPool(PoolRequest req) {
  final target = Frac.tryParse(req.target)!;
  final solver = makeSolver(target, req.cards, req.useAll);
  // When not every card must be used, a hand already holding the target is trivial.
  bool allowed(List<int> h) => req.useAll || !(target.isInteger && h.contains(target.n));

  if (isClassic(target, req.cards, req.useAll)) {
    return [
      for (var i = 0; i < games.length; ++i) RankedHand(games[i], i.toDouble(), solver.analyze(games[i])!.solution),
    ];
  }

  final pool = <RankedHand>[];
  if (req.cards == 4) {
    for (var a = 1; a <= maxCard; ++a) {
      for (var b = a; b <= maxCard; ++b) {
        for (var c = b; c <= maxCard; ++c) {
          for (var d = c; d <= maxCard; ++d) {
            final h = [a, b, c, d];
            if (!allowed(h)) continue;
            final r = solver.analyze(h);
            if (r != null) pool.add(RankedHand(h, r.score, r.solution));
          }
        }
      }
    }
  } else {
    final rng = Random(req.seed);
    final seen = <int>{};
    for (var i = 0; i < req.deals; ++i) {
      final h = dealHand(req.cards, rng);
      if (!allowed(h) || !seen.add(handKey(h))) continue;
      final r = solver.analyze(h);
      if (r != null) pool.add(RankedHand(h, r.score, r.solution));
    }
  }
  pool.sort((x, y) => x.score.compareTo(y.score));
  return pool;
}

/// Picks a hand whose difficulty percentile lies in [lo, hi] (0 = easiest, 1 = hardest).
int pickIndex(int length, double lo, double hi, Random rng) {
  final a = (lo * length).floor().clamp(0, length - 1);
  final b = (hi * length).ceil().clamp(a + 1, length);
  return a + rng.nextInt(b - a);
}
