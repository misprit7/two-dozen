import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:two_dozen/engine/frac.dart';
import 'package:two_dozen/engine/generator.dart';
import 'package:two_dozen/engine/solver.dart';
import 'package:two_dozen/engine/target_tiers.dart';
import 'package:two_dozen/games.dart';

/// Replays a solution and checks it reaches the target using only the hand's cards.
void expectValidSolution(List<int> hand, Frac target, List<Step> steps, {required bool useAll}) {
  final pool = hand.map((c) => Frac(c)).toList();
  for (final s in steps) {
    expect(pool.remove(s.a), isTrue, reason: 'operand ${s.a} not available in $pool');
    expect(pool.remove(s.b), isTrue, reason: 'operand ${s.b} not available in $pool');
    expect(s.op.apply(s.a, s.b), s.result);
    pool.add(s.result);
  }
  expect(steps.last.result, target);
  if (useAll) expect(pool, [target]);
}

void main() {
  group('Frac', () {
    test('arithmetic stays reduced', () {
      expect(Frac(2, 4), Frac(1, 2));
      expect(Frac(1, 3) + Frac(1, 6), Frac(1, 2));
      expect(Frac(8) / Frac(1, 3), Frac(24));
      expect(Frac(3, -6), Frac(-1, 2));
    });

    test('parses user input', () {
      expect(Frac.tryParse('24'), Frac(24));
      expect(Frac.tryParse(' 7/3 '), Frac(7, 3));
      expect(Frac.tryParse('-5'), Frac(-5));
      expect(Frac.tryParse('2.5'), Frac(5, 2));
      expect(Frac.tryParse('1 1/2'), Frac(3, 2));
      expect(Frac.tryParse('1/0'), isNull);
      expect(Frac.tryParse('abc'), isNull);
      expect(Frac.tryParse(''), isNull);
    });
  });

  group('Solver', () {
    test('every classic puzzle is solvable with a valid solution', () {
      final solver = Solver(Frac(24));
      for (final g in games) {
        final r = solver.analyze(g);
        expect(r, isNotNull, reason: '$g');
        expectValidSolution(g, Frac(24), r!.solution, useAll: true);
      }
    });

    test('finds exactly the 1362 solvable hands for 24', () {
      final solver = Solver(Frac(24));
      var solvable = 0;
      for (var a = 1; a <= 13; ++a) {
        for (var b = a; b <= 13; ++b) {
          for (var c = b; c <= 13; ++c) {
            for (var d = c; d <= 13; ++d) {
              if (solver.analyze([a, b, c, d]) != null) ++solvable;
            }
          }
        }
      }
      expect(solvable, games.length);
    });

    test('unsolvable hands return null', () {
      expect(Solver(Frac(24)).analyze([1, 1, 1, 1]), isNull);
      expect(Solver(Frac(24)).analyze([13, 13, 13, 13]), isNull);
    });

    test('fraction targets', () {
      final r = Solver(Frac(7, 3)).analyze([1, 2, 3, 4]);
      expect(r, isNotNull);
      expectValidSolution([1, 2, 3, 4], Frac(7, 3), r!.solution, useAll: true);
    });

    test('any-subset mode can skip cards', () {
      // 11 + 2 = 13 leaves cards unused, which is fine in this mode.
      final hand = [2, 3, 4, 5, 11];
      final r = Solver(Frac(13), useAll: false).analyze(hand);
      expect(r, isNotNull);
      expectValidSolution(hand, Frac(13), r!.solution, useAll: false);
      expect(r.solution.length, lessThan(4));
    });

    test('model agrees with the classic ordering', () {
      // Score the classic list and check rank correlation against its order.
      final solver = Solver(Frac(24));
      final scores = [for (final g in games) solver.analyze(g)!.score];
      final order = List.generate(scores.length, (i) => i)..sort((a, b) => scores[a].compareTo(scores[b]));
      final rank = List.filled(scores.length, 0);
      for (var i = 0; i < order.length; ++i) {
        rank[order[i]] = i;
      }
      final n = scores.length;
      var d2 = 0.0;
      for (var i = 0; i < n; ++i) {
        d2 += pow(rank[i] - i, 2);
      }
      final spearman = 1 - 6 * d2 / (n * (n * n - 1));
      expect(spearman, greaterThan(0.8));
    });
  });

  group('Generator', () {
    test('classic pool keeps the measured ordering', () {
      final pool = buildPool(PoolRequest('24', 4, true));
      expect(pool.length, games.length);
      for (var i = 0; i < 20; ++i) {
        expect(pool[i].hand, games[i]);
      }
    });

    test('larger hands generate valid puzzles', () {
      for (final (cards, useAll, target) in [(5, true, '24'), (6, false, '100'), (9, false, '2025')]) {
        final pool = buildPool(PoolRequest(target, cards, useAll, deals: 8, seed: 3));
        expect(pool, isNotEmpty, reason: '$cards $useAll $target');
        for (final r in pool) {
          expect(r.hand.length, cards);
          expectValidSolution(r.hand, Frac.tryParse(target)!, r.solution, useAll: useAll);
        }
        for (var i = 1; i < pool.length; ++i) {
          expect(pool[i].score, greaterThanOrEqualTo(pool[i - 1].score));
        }
      }
    });

    test('dealt hands respect the deck', () {
      final rng = Random(1);
      for (var i = 0; i < 100; ++i) {
        final h = dealHand(9, rng);
        for (var v = 1; v <= 13; ++v) {
          expect(h.where((c) => c == v).length, lessThanOrEqualTo(4));
        }
      }
    });

    test('pickIndex stays in range', () {
      final rng = Random(2);
      for (var i = 0; i < 200; ++i) {
        final idx = pickIndex(100, 0.2, 0.4, rng);
        expect(idx, inInclusiveRange(20, 39));
      }
      expect(pickIndex(1, 0.9, 1.0, rng), 0);
    });

    test('every configuration has random-target tiers', () {
      for (var cards = minCards; cards <= maxCards; ++cards) {
        for (final useAll in [true, false]) {
          if (useAll && cards > maxUseAllCards) continue;
          final tiers = targetTiers['$cards/${useAll ? 'all' : 'any'}'];
          expect(tiers, isNotNull, reason: '$cards $useAll');
          expect(tiers!.where((t) => t.isNotEmpty).length, 4);
          for (final t in tiers.expand((t) => t)) {
            expect(Frac.tryParse(t), isNotNull);
          }
        }
      }
    });
  });
}
