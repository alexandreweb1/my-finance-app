/// Exact integer-cent money primitives.
///
/// NO imports — not Flutter, not Firestore, not even `dart:math` — so this can
/// be unit-tested in isolation and reused anywhere.
///
/// WHY THIS EXISTS. The app stores money as `double` (see
/// `TransactionEntity.amount`), which cannot represent R$ 0,07 exactly. Any
/// arithmetic that divides money between people MUST convert to integer
/// centavos first, or it silently loses centavos. The app's own installment
/// splitter shows the failure mode:
///
///     final perAmount = ((total / n) * 100).floor() / 100.0;   // WRONG
///
/// For R$ 0,21 split 3 ways, `0.21 / 3` is `0.06999999999999999`, so `.floor()`
/// yields 6 and the split becomes 0,06 / 0,06 / 0,09 instead of 0,07 each. The
/// total still adds up, so the bug is invisible on a receipt and shows up only
/// as one person systematically overpaying.
///
/// THE RULE: every value this engine touches is an `int` of centavos.
/// Doubles exist only at the two boundaries below, and `.round()` is the only
/// rounding operator used there. `.floor()`, `.truncate()` and
/// `toStringAsFixed` are banned inside the engine.
library;

/// Money as an exact integer number of centavos. Positive = entrada.
typedef Cents = int;

/// R$ 999.999.999,99 — the cap `MoneyInputFormatter` already enforces on input,
/// plus slack. Amounts beyond this are treated as corrupt rather than clamped.
const int kMaxCents = 100000000000;

/// Converts reais (`double`) to [Cents]. This is the ONLY place a double
/// becomes money.
///
/// Throws on NaN/Infinity and on out-of-range values so garbage never silently
/// becomes R$ 0,00. `(v * 100).round()` is exact across the supported range;
/// `.floor()` would be wrong, because `8.87 * 100` is `886.9999999999999`.
Cents toCents(double reais) {
  if (!reais.isFinite) {
    throw ArgumentError.value(reais, 'reais', 'not a finite amount');
  }
  final scaled = reais * 100;
  if (scaled.abs() > kMaxCents) {
    throw ArgumentError.value(reais, 'reais', 'amount out of supported range');
  }
  return scaled.round();
}

/// Non-throwing [toCents], for stream/UI paths that must survive one corrupt
/// document instead of taking the whole list down.
Cents toCentsOr(double? reais, {Cents fallback = 0}) {
  if (reais == null || !reais.isFinite) return fallback;
  final scaled = reais * 100;
  if (scaled.abs() > kMaxCents) return fallback;
  return scaled.round();
}

/// Converts [Cents] back to reais for display. Exact for every value in range.
double toReais(Cents cents) => cents / 100.0;

/// Splits [totalCents] into exactly [n] parts that sum to [totalCents] and
/// differ from one another by at most one centavo.
///
/// Remainder rule: the leftover centavos go to the FIRST entries of the
/// returned list, in the caller's order. Callers that need fairness across many
/// expenses rotate the participant order per expense rather than randomizing
/// here — see `buildEqualSplit`.
///
/// Uses `~/` and `.remainder()` (both truncate toward zero) rather than `%`, so
/// a NEGATIVE total — an estorno, a refund — distributes the extra centavo in
/// the same direction as the amount. Euclidean `%` is always non-negative and
/// would push it the wrong way.
List<Cents> splitEqually(Cents totalCents, int n) {
  if (n <= 0) {
    throw ArgumentError.value(n, 'n', 'must be >= 1');
  }
  final base = totalCents ~/ n;
  final rem = totalCents.remainder(n);
  final step = rem.isNegative ? -1 : 1;
  final extras = rem.abs();
  return List<Cents>.generate(n, (i) => i < extras ? base + step : base);
}

/// Distributes [amountCents] across [weights] proportionally, exactly, using
/// the largest-remainder method. The result always sums to [amountCents].
///
/// Ties on the fractional remainder are broken by the earlier index, so the
/// output is deterministic for a given input order.
///
/// Intermediates are [BigInt] on purpose. The product
/// `amountCents * weight` reaches ~1e22 for realistic patrimony math, which
/// overflows a signed 64-bit int on mobile AND exceeds the 2^53 exact-integer
/// range of `dart2js` — and this app ships a web build. Do not "optimize" this
/// back to plain int arithmetic.
List<Cents> allocateProportional(Cents amountCents, List<int> weights) {
  if (weights.isEmpty) {
    throw ArgumentError.value(weights, 'weights', 'must not be empty');
  }
  var totalW = 0;
  for (final w in weights) {
    if (w < 0) {
      throw ArgumentError.value(weights, 'weights', 'must be >= 0');
    }
    totalW += w;
  }
  if (totalW == 0) {
    throw ArgumentError.value(weights, 'weights', 'total weight must be > 0');
  }

  final neg = amountCents.isNegative;
  final magnitude = neg ? -amountCents : amountCents;
  final abs = BigInt.from(magnitude);
  final den = BigInt.from(totalW);

  final base = List<int>.filled(weights.length, 0);
  final rems = List<BigInt>.filled(weights.length, BigInt.zero);
  var distributed = 0;
  for (var i = 0; i < weights.length; i++) {
    final numerator = abs * BigInt.from(weights[i]);
    final q = numerator ~/ den;
    base[i] = q.toInt();
    rems[i] = numerator - q * den;
    distributed += base[i];
  }

  final left = magnitude - distributed;
  final order = List<int>.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final c = rems[b].compareTo(rems[a]); // larger remainder first
      return c != 0 ? c : a.compareTo(b); // tie → earlier index first
    });
  for (var k = 0; k < left; k++) {
    base[order[k % weights.length]] += 1;
  }

  if (!neg) return base;
  return base.map((c) => -c).toList();
}
