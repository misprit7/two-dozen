import 'dart:math' as math;

import 'frac.dart';

/// Difficulty model weights, fitted (Spearman ρ ≈ 0.85) so that ranking every
/// solvable 4-card hand for target 24 reproduces the empirical solve-time
/// ordering in games.dart as closely as possible.
///
/// A puzzle's score is −log Z + hand terms, where Z sums exp(−cost) over every
/// distinct way of making the target and each derivation's cost is the sum of
/// its step costs. Lots of cheap routes to the target → easy puzzle.
class Weights {
  // Per-step costs, indexed by Op.
  static const op = [1.8449, 1.7415, 1.5617, 1.1961];
  // Extra cost of the final step, indexed by Op (replaces [factor]).
  static const finalOp = [-0.1469, -0.3569, -0.6510, -0.5321];
  static const fraction = 15.4509; // step produces a non-integer
  static const logDenominator = -0.8154; // × log(denominator) for fractions
  static const negative = 0.5818; // step produces a negative number
  static const zero = 0.0089; // step produces 0
  static const pair = -0.3098; // combining two compound sub-expressions
  static const big = 1.7345; // × log(|r| / ref) when |r| > ref
  static const factor = 0.2700; // intermediate is a divisor of the target

  // Whole-hand terms.
  static const meanLogCard = -0.5555;
  static const distinctCards = 0.3921;
  static const ones = -0.6438;
  static const logCount = 0.5638;
}

enum Op {
  add('+'),
  sub('−'),
  mul('×'),
  div('÷');

  final String symbol;
  const Op(this.symbol);

  Frac apply(Frac a, Frac b) => switch (this) {
        Op.add => a + b,
        Op.sub => a - b,
        Op.mul => a * b,
        Op.div => a / b,
      };
}

class Step {
  final Frac a;
  final Op op;
  final Frac b;
  final Frac result;
  const Step(this.a, this.op, this.b, this.result);

  @override
  String toString() => '$a ${op.symbol} $b = $result';
}

class Analysis {
  final double score;
  final List<Step> solution;
  const Analysis(this.score, this.solution);
}

/// All values reachable from one sub-multiset of cards, with the summed
/// weight Z, derivation count and cheapest derivation of each.
class _Node {
  final int size;
  final List<int> nums = [];
  final List<int> dens = [];
  final List<double> z = [];
  final List<double> cnt = [];
  final List<double> best = [];
  // Back-pointers for the cheapest derivation: left (key, idx) op right (key, idx).
  final List<int> lKey = [], lIdx = [], rKey = [], rIdx = [], ops = [];
  final Map<int, int> index = {};

  _Node(this.size);

  int get length => nums.length;
}

const int maxCard = 13;
const int _numCap = 10000000;
const int _denCap = 10000;

int _valueKey(int n, int d) => (n + _numCap) * (_denCap + 1) + d;

/// Multisets of cards are keyed by their counts in base 10 (card c is digit c-1).
final List<int> _place = List.generate(maxCard + 1, (i) => math.pow(10, i).toInt());

int handKey(Iterable<int> cards) {
  var k = 0;
  for (final c in cards) {
    k += _place[c - 1];
  }
  return k;
}

List<int> _counts(int key) {
  final c = List<int>.filled(maxCard + 1, 0);
  for (var v = 1; v <= maxCard; ++v) {
    c[v] = (key ~/ _place[v - 1]) % 10;
  }
  return c;
}

/// Every sub-multiset key of [key], excluding empty.
List<int> subKeys(int key) {
  final counts = _counts(key);
  var keys = <int>[0];
  for (var v = 1; v <= maxCard; ++v) {
    if (counts[v] == 0) continue;
    final next = <int>[];
    for (final k in keys) {
      for (var m = 0; m <= counts[v]; ++m) {
        next.add(k + m * _place[v - 1]);
      }
    }
    keys = next;
  }
  keys.remove(0);
  return keys;
}

int _keySize(int key) {
  var s = 0;
  while (key > 0) {
    s += key % 10;
    key ~/= 10;
  }
  return s;
}

class Solver {
  /// Target for scoring; null builds a target-agnostic solver (for reachability).
  final Frac? target;
  final bool useAll;

  /// Max values kept per intermediate sub-multiset (keeps large hands tractable).
  final int pruneK;

  /// When not [useAll], only solutions using at most this many cards are considered.
  final int maxRootSize;

  late final double _ref;
  final Map<int, _Node> _memo = {};

  Solver(this.target, {this.useAll = true, this.pruneK = 1 << 30, this.maxRootSize = 1 << 30}) {
    _ref = math.max(target == null ? 0.0 : target!.value.abs(), maxCard.toDouble());
  }

  double _stepCost(int op, int rn, int rd, bool pair, bool root) {
    var c = Weights.op[op];
    if (rd != 1) c += Weights.fraction + Weights.logDenominator * math.log(rd);
    if (rn < 0) c += Weights.negative;
    if (rn == 0) c += Weights.zero;
    if (pair) c += Weights.pair;
    if (root) {
      c += Weights.finalOp[op];
    } else if (_isFactor(rn, rd)) {
      c += Weights.factor;
    }
    final mag = rn.abs() / rd;
    if (mag > _ref) c += Weights.big * math.log(mag / _ref);
    return c;
  }

  bool _isFactor(int rn, int rd) {
    final t = target;
    if (t == null || rn == 0 || rn.abs() <= rd) return false;
    if (rn == t.n && rd == t.d) return false;
    // t / r = (t.n * rd) / (t.d * rn) is an integer
    return (t.n * rd) % (t.d * rn) == 0;
  }

  _Node _node(int key, {bool prune = true}) {
    final cached = _memo[key];
    if (cached != null) return cached;
    final size = _keySize(key);
    final node = _Node(size);
    if (size == 1) {
      var v = 1;
      while (_place[v - 1] != key) {
        ++v;
      }
      _add(node, v, 1, 1, 1, 0, -1, -1, -1, -1, 0);
    } else {
      for (final a in subKeys(key)) {
        final b = key - a;
        if (b == 0 || a > b) continue;
        _combine(node, a, b);
      }
      if (prune && size >= 3 && node.length > pruneK) _prune(node);
    }
    _memo[key] = node;
    return node;
  }

  void _add(_Node node, int n, int d, double z, double cnt, double cost, int lk, int li, int rk, int ri, int op) {
    if (n.abs() > _numCap || d > _denCap) return;
    final k = _valueKey(n, d);
    final i = node.index[k];
    if (i == null) {
      node.index[k] = node.length;
      node.nums.add(n);
      node.dens.add(d);
      node.z.add(z);
      node.cnt.add(cnt);
      node.best.add(cost);
      node.lKey.add(lk);
      node.lIdx.add(li);
      node.rKey.add(rk);
      node.rIdx.add(ri);
      node.ops.add(op);
    } else {
      node.z[i] += z;
      node.cnt[i] += cnt;
      if (cost < node.best[i]) {
        node.best[i] = cost;
        node.lKey[i] = lk;
        node.lIdx[i] = li;
        node.rKey[i] = rk;
        node.rIdx[i] = ri;
        node.ops[i] = op;
      }
    }
  }

  void _combine(_Node node, int ka, int kb) {
    final na = _node(ka), nb = _node(kb);
    final same = ka == kb;
    final pair = na.size > 1 && nb.size > 1;
    for (var i = 0; i < na.length; ++i) {
      final xn = na.nums[i], xd = na.dens[i];
      final xz = na.z[i], xc = na.cnt[i], xb = na.best[i];
      for (var j = 0; j < nb.length; ++j) {
        final yn = nb.nums[j], yd = nb.dens[j];
        final zz = xz * nb.z[j], cc = xc * nb.cnt[j], bb = xb + nb.best[j];

        void emit(int op, int n, int d, bool swap) {
          if (d != 1) {
            if (d < 0) {
              n = -n;
              d = -d;
            }
            final g = n.gcd(d);
            if (g > 1) {
              n ~/= g;
              d ~/= g;
            }
          }
          if (n.abs() > _numCap || d > _denCap) return;
          final c = _stepCost(op, n, d, pair, false);
          if (swap) {
            _add(node, n, d, zz * math.exp(-c), cc, bb + c, kb, j, ka, i, op);
          } else {
            _add(node, n, d, zz * math.exp(-c), cc, bb + c, ka, i, kb, j, op);
          }
        }

        final sameDen = xd == 1 && yd == 1;
        if (!same || j >= i) {
          emit(0, sameDen ? xn + yn : xn * yd + yn * xd, sameDen ? 1 : xd * yd, false);
          emit(2, xn * yn, xd * yd, false);
        }
        emit(1, sameDen ? xn - yn : xn * yd - yn * xd, sameDen ? 1 : xd * yd, false);
        if (yn != 0) emit(3, xn * yd, xd * yn, false);
        if (!same) {
          emit(1, sameDen ? yn - xn : yn * xd - xn * yd, sameDen ? 1 : xd * yd, true);
          if (xn != 0) emit(3, yn * xd, yd * xn, true);
        }
      }
    }
  }

  void _prune(_Node node) {
    final order = List<int>.generate(node.length, (i) => i)..sort((a, b) => node.z[b].compareTo(node.z[a]));
    order.length = pruneK;
    List<T> pick<T>(List<T> src) => [for (final i in order) src[i]];
    final nums = pick(node.nums), dens = pick(node.dens), z = pick(node.z), cnt = pick(node.cnt);
    final best = pick(node.best), lKey = pick(node.lKey), lIdx = pick(node.lIdx);
    final rKey = pick(node.rKey), rIdx = pick(node.rIdx), ops = pick(node.ops);
    node.nums..clear()..addAll(nums);
    node.dens..clear()..addAll(dens);
    node.z..clear()..addAll(z);
    node.cnt..clear()..addAll(cnt);
    node.best..clear()..addAll(best);
    node.lKey..clear()..addAll(lKey);
    node.lIdx..clear()..addAll(lIdx);
    node.rKey..clear()..addAll(rKey);
    node.rIdx..clear()..addAll(rIdx);
    node.ops..clear()..addAll(ops);
    node.index.clear();
    for (var i = 0; i < nums.length; ++i) {
      node.index[_valueKey(nums[i], dens[i])] = i;
    }
  }

  /// Scores [hand] for [target]; null if the target can't be made.
  /// Lower scores are easier.
  Analysis? analyze(List<int> hand) {
    final t = target!;
    final key = handKey(hand);
    final roots = useAll ? [key] : subKeys(key).where((k) => _keySize(k) >= 2 && _keySize(k) <= maxRootSize).toList();
    var z = 0.0, cnt = 0.0, bestCost = double.infinity;
    List<int>? bestBp;
    for (final root in roots) {
      for (final a in subKeys(root)) {
        final b = root - a;
        if (b == 0 || a > b) continue;
        final na = _node(a), nb = _node(b);
        final same = a == b, pair = na.size > 1 && nb.size > 1;

        void hit(int op, int la, int li, int ra, int ri, _Node ln, _Node rn) {
          final c = _stepCost(op, t.n, t.d, pair, true);
          z += ln.z[li] * rn.z[ri] * math.exp(-c);
          cnt += ln.cnt[li] * rn.cnt[ri];
          final cost = ln.best[li] + rn.best[ri] + c;
          if (cost < bestCost) {
            bestCost = cost;
            bestBp = [la, li, ra, ri, op];
          }
        }

        for (var i = 0; i < na.length; ++i) {
          final x = Frac(na.nums[i], na.dens[i]);
          if (t.isZero) {
            // Rare: brute-force every pairing.
            for (var j = 0; j < nb.length; ++j) {
              final y = Frac(nb.nums[j], nb.dens[j]);
              if (!same || j >= i) {
                if ((x + y).isZero) hit(0, a, i, b, j, na, nb);
                if ((x * y).isZero) hit(2, a, i, b, j, na, nb);
              }
              if ((x - y).isZero) hit(1, a, i, b, j, na, nb);
              if (!y.isZero && x.isZero) hit(3, a, i, b, j, na, nb);
              if (!same) {
                if ((y - x).isZero) hit(1, b, j, a, i, nb, na);
                if (!x.isZero && y.isZero) hit(3, b, j, a, i, nb, na);
              }
            }
            continue;
          }
          int? find(Frac y) => y.d > _denCap || y.n.abs() > _numCap ? null : nb.index[_valueKey(y.n, y.d)];
          int? j;
          // x + y = t
          j = find(t - x);
          if (j != null && (!same || j >= i)) hit(0, a, i, b, j, na, nb);
          // x × y = t
          if (!x.isZero) {
            j = find(t / x);
            if (j != null && (!same || j >= i)) hit(2, a, i, b, j, na, nb);
          }
          // x − y = t
          j = find(x - t);
          if (j != null) hit(1, a, i, b, j, na, nb);
          // x ÷ y = t
          if (!x.isZero) {
            j = find(x / t);
            if (j != null) hit(3, a, i, b, j, na, nb);
          }
          if (!same) {
            // y − x = t
            j = find(x + t);
            if (j != null) hit(1, b, j, a, i, nb, na);
            // y ÷ x = t
            if (!x.isZero) {
              j = find(t * x);
              if (j != null) hit(3, b, j, a, i, nb, na);
            }
          }
        }
      }
    }
    if (z <= 0 || bestBp == null) return null;
    final bp = bestBp!;
    final steps = [..._steps(bp[0], bp[1]), ..._steps(bp[2], bp[3])];
    steps.add(Step(_value(bp[0], bp[1]), Op.values[bp[4]], _value(bp[2], bp[3]), t));

    final logMean = hand.map((c) => math.log(c)).reduce((a, b) => a + b) / hand.length;
    final score = -math.log(z) +
        Weights.meanLogCard * logMean +
        Weights.distinctCards * hand.toSet().length +
        Weights.ones * hand.where((c) => c == 1).length +
        Weights.logCount * math.log(cnt);
    return Analysis(score, steps);
  }

  Frac _value(int key, int idx) {
    final n = _memo[key]!;
    return Frac(n.nums[idx], n.dens[idx]);
  }

  List<Step> _steps(int key, int idx) {
    final n = _memo[key]!;
    if (n.size == 1) return [];
    return [
      ..._steps(n.lKey[idx], n.lIdx[idx]),
      ..._steps(n.rKey[idx], n.rIdx[idx]),
      Step(_value(n.lKey[idx], n.lIdx[idx]), Op.values[n.ops[idx]], _value(n.rKey[idx], n.rIdx[idx]),
          Frac(n.nums[idx], n.dens[idx])),
    ];
  }

  /// Every value makeable from [hand] (all cards if [useAll], else any 2+ cards).
  Set<Frac> reachable(List<int> hand) {
    final key = handKey(hand);
    final out = <Frac>{};
    if (useAll) {
      final root = _node(key, prune: false);
      for (var i = 0; i < root.length; ++i) {
        out.add(Frac(root.nums[i], root.dens[i]));
      }
    } else {
      for (final k in subKeys(key)) {
        if (_keySize(k) < 2 || _keySize(k) > maxRootSize) continue;
        final n = _node(k, prune: k != key);
        for (var i = 0; i < n.length; ++i) {
          out.add(Frac(n.nums[i], n.dens[i]));
        }
      }
    }
    return out;
  }
}
