/// Exact rational number with a positive denominator, always in lowest terms.
class Frac implements Comparable<Frac> {
  final int n;
  final int d;

  const Frac._(this.n, this.d);

  factory Frac(int n, [int d = 1]) {
    if (d == 0) throw ArgumentError('zero denominator');
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = n.gcd(d);
    return g > 1 ? Frac._(n ~/ g, d ~/ g) : Frac._(n, d);
  }

  static const zero = Frac._(0, 1);
  static const one = Frac._(1, 1);

  bool get isInteger => d == 1;
  bool get isZero => n == 0;
  bool get isNegative => n < 0;
  double get value => n / d;

  Frac operator +(Frac o) => Frac(n * o.d + o.n * d, d * o.d);
  Frac operator -(Frac o) => Frac(n * o.d - o.n * d, d * o.d);
  Frac operator *(Frac o) => Frac(n * o.n, d * o.d);
  Frac operator /(Frac o) => Frac(n * o.d, d * o.n);
  Frac operator -() => Frac._(-n, d);

  @override
  bool operator ==(Object other) => other is Frac && other.n == n && other.d == d;

  @override
  int get hashCode => Object.hash(n, d);

  @override
  int compareTo(Frac o) => (n * o.d).compareTo(o.n * d);

  @override
  String toString() => d == 1 ? '$n' : '$n/$d';

  /// Parses "24", "-3", "7/3", "2.5" or "1 1/2". Returns null if invalid.
  static Frac? tryParse(String s) {
    s = s.trim().replaceAll('−', '-').replaceAll('÷', '/');
    if (s.isEmpty) return null;
    final mixed = RegExp(r'^(-?)(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(s);
    if (mixed != null) {
      final sign = mixed.group(1) == '-' ? -1 : 1;
      final whole = int.parse(mixed.group(2)!);
      final num = int.parse(mixed.group(3)!);
      final den = int.parse(mixed.group(4)!);
      if (den == 0) return null;
      return Frac(sign * (whole * den + num), den);
    }
    final frac = RegExp(r'^(-?\d+)\s*/\s*(-?\d+)$').firstMatch(s);
    if (frac != null) {
      final den = int.parse(frac.group(2)!);
      if (den == 0) return null;
      return Frac(int.parse(frac.group(1)!), den);
    }
    final dec = RegExp(r'^(-?)(\d*)\.(\d+)$').firstMatch(s);
    if (dec != null) {
      final digits = dec.group(3)!;
      if (digits.length > 6) return null;
      final den = _pow10(digits.length);
      final whole = dec.group(2)!.isEmpty ? 0 : int.parse(dec.group(2)!);
      final v = whole * den + int.parse(digits);
      return Frac(dec.group(1) == '-' ? -v : v, den);
    }
    final i = int.tryParse(s);
    return i == null ? null : Frac(i);
  }

  static int _pow10(int k) {
    var r = 1;
    for (var i = 0; i < k; ++i) {
      r *= 10;
    }
    return r;
  }
}
