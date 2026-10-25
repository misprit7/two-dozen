import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'engine/frac.dart';
import 'engine/generator.dart';
import 'engine/solver.dart';
import 'engine/target_tiers.dart';
import 'settings.dart';

class Puzzle {
  final List<int> hand;
  final Frac target;
  final List<Step> solution;

  /// Where this hand sits in its pool, 0 = easiest, 1 = hardest.
  final double percentile;

  const Puzzle(this.hand, this.target, this.solution, this.percentile);
}

class NoPuzzleException implements Exception {
  final String message;
  const NoPuzzleException(this.message);
  @override
  String toString() => message;
}

/// Hands out puzzles matching the current settings, building pools of ranked
/// hands in a background isolate and prefetching the next puzzle.
class PuzzleService {
  final Random _rng = Random();
  final Map<String, List<RankedHand>> _pools = {};
  final Map<String, Future<List<RankedHand>>> _building = {};
  Future<Puzzle>? _prefetched;
  String? _prefetchKey;

  static const _maxPools = 24;
  static const _dealsPerBatch = 30;
  static const _maxBatches = 4;

  Future<Puzzle> next(Settings s) {
    final f = _prefetched;
    final key = _prefetchKey;
    _prefetched = null;
    _prefetchKey = null;
    if (f != null && key == s.puzzleKey) return f;
    return _generate(s.copy());
  }

  /// Starts generating the puzzle after this one in the background.
  void prefetch(Settings s) {
    _prefetchKey = s.puzzleKey;
    _prefetched = _generate(s.copy())..ignore();
  }

  Future<Puzzle> _generate(Settings s) async {
    final attempts = s.randomTarget ? 6 : 1;
    for (var attempt = 0; attempt < attempts; ++attempt) {
      final target = s.randomTarget ? _randomTarget(s) : s.fixedTarget;
      final pool = await _pool(target, s.cards, s.effectiveUseAll);
      if (pool.isEmpty) continue;
      final i = pickIndex(pool.length, s.minDifficulty, s.maxDifficulty, _rng);
      final r = pool[i];
      final percentile = pool.length == 1 ? 0.5 : i / (pool.length - 1);
      if (s.cards > 4) {
        // Sampled pools: don't repeat hands, top up in the background when low.
        pool.removeAt(i);
        if (pool.length < 12) _refill(target, s.cards, s.effectiveUseAll);
      }
      return Puzzle(List.of(r.hand)..shuffle(_rng), target, r.solution, percentile);
    }
    final mode = s.effectiveUseAll ? 'using all ${s.cards} cards' : 'with ${s.cards} cards';
    throw NoPuzzleException(s.randomTarget
        ? 'Couldn\'t generate a puzzle right now — try again.'
        : 'No hands found that make ${s.fixedTarget} $mode. Try a different target or more cards.');
  }

  Frac _randomTarget(Settings s) {
    final tiers = targetTiers['${s.cards}/${s.effectiveUseAll ? 'all' : 'any'}']!;
    // Fall back to the nearest non-empty tier.
    for (var d = 0; d < tiers.length; ++d) {
      for (final t in [s.targetTier.index - d, s.targetTier.index + d]) {
        if (t >= 0 && t < tiers.length && tiers[t].isNotEmpty) {
          return Frac.tryParse(tiers[t][_rng.nextInt(tiers[t].length)])!;
        }
      }
    }
    return classicTarget;
  }

  String _key(Frac target, int cards, bool useAll) => '$target|$cards|$useAll';

  Future<List<RankedHand>> _pool(Frac target, int cards, bool useAll) async {
    final key = _key(target, cards, useAll);
    final existing = _pools.remove(key);
    if (existing != null && existing.isNotEmpty) {
      _pools[key] = existing; // mark most recently used
      return existing;
    }
    final building = _building[key];
    if (building != null) return building;

    final future = () async {
      var pool = <RankedHand>[];
      // Rare targets may need several batches of deals before anything solvable turns up.
      for (var batch = 0; batch < (cards == 4 ? 1 : _maxBatches) && pool.length < 3; ++batch) {
        pool = _merge(pool, await _build(target, cards, useAll));
      }
      _pools[key] = pool;
      while (_pools.length > _maxPools) {
        _pools.remove(_pools.keys.first);
      }
      return pool;
    }();
    _building[key] = future;
    try {
      return await future;
    } finally {
      _building.remove(key);
    }
  }

  Future<List<RankedHand>> _build(Frac target, int cards, bool useAll) {
    return compute(
      buildPool,
      PoolRequest('$target', cards, useAll, deals: _dealsPerBatch, seed: _rng.nextInt(1 << 30)),
    );
  }

  void _refill(Frac target, int cards, bool useAll) {
    final key = _key(target, cards, useAll);
    if (_building.containsKey(key)) return;
    final future = _build(target, cards, useAll).then((more) {
      final pool = _pools[key];
      if (pool != null) {
        final merged = _merge(pool, more);
        pool
          ..clear()
          ..addAll(merged);
      }
      return pool ?? more;
    });
    _building[key] = future;
    future.whenComplete(() => _building.remove(key)).ignore();
  }

  List<RankedHand> _merge(List<RankedHand> a, List<RankedHand> b) {
    final seen = {for (final h in a) handKey(h.hand)};
    return [...a, ...b.where((h) => seen.add(handKey(h.hand)))]..sort((x, y) => x.score.compareTo(y.score));
  }
}
