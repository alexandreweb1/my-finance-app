import 'package:flutter_test/flutter_test.dart';

import 'package:my_finance_app/core/utils/cents.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The money engine behind the Holding "cada centavo" promise.
//
// These tests are the contract: a split must never lose or invent a centavo,
// and must stay exact for negative amounts (estornos) and for the very large
// intermediate products that patrimony math produces.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('toCents / toReais', () {
    test('rounds at the boundary instead of truncating', () {
      // The naive `(v * 100).floor()` returns 886 and 28 here, because
      // 8.87 * 100 == 886.9999999999999 in IEEE-754.
      expect(toCents(8.87), 887);
      expect(toCents(0.29), 29);
      expect(toCents(0.07), 7);
      expect(toCents(0.1 + 0.2), 30); // 0.30000000000000004
    });

    test('round-trips every value in the everyday range', () {
      for (var c = 0; c <= 200000; c++) {
        expect(toCents(toReais(c)), c, reason: 'lost precision at $c centavos');
      }
    });

    test('handles negatives and zero', () {
      expect(toCents(-12.34), -1234);
      expect(toCents(0), 0);
      expect(toReais(-1234), -12.34);
    });

    test('rejects NaN, Infinity and out-of-range amounts', () {
      expect(() => toCents(double.nan), throwsArgumentError);
      expect(() => toCents(double.infinity), throwsArgumentError);
      expect(() => toCents(-double.infinity), throwsArgumentError);
      expect(() => toCents(1e12), throwsArgumentError);
    });

    test('toCentsOr degrades to the fallback instead of throwing', () {
      expect(toCentsOr(null), 0);
      expect(toCentsOr(double.nan), 0);
      expect(toCentsOr(1e12), 0);
      expect(toCentsOr(null, fallback: -1), -1);
      expect(toCentsOr(8.87), 887);
    });
  });

  group('splitEqually', () {
    test('R\$ 0,21 three ways is 7/7/7, not 6/6/9', () {
      expect(splitEqually(21, 3), [7, 7, 7]);
    });

    test('distributes the remainder to the first entries', () {
      expect(splitEqually(10000, 3), [3334, 3333, 3333]);
      expect(splitEqually(100, 3), [34, 33, 33]);
      expect(splitEqually(1, 3), [1, 0, 0]);
    });

    test('splits evenly when it divides', () {
      expect(splitEqually(9000, 3), [3000, 3000, 3000]);
      expect(splitEqually(0, 4), [0, 0, 0, 0]);
    });

    test('n == 1 returns the whole amount', () {
      expect(splitEqually(12345, 1), [12345]);
    });

    test('negative totals (estorno) push the extra centavo the same way', () {
      // Euclidean % would produce [-3333, -3333, -3334] here, silently
      // reversing which participant absorbs the odd centavo on a refund.
      expect(splitEqually(-10000, 3), [-3334, -3333, -3333]);
      expect(splitEqually(-21, 3), [-7, -7, -7]);
      expect(splitEqually(-1, 3), [-1, 0, 0]);
    });

    test('an estorno exactly undoes the original split', () {
      for (var total = -500; total <= 500; total++) {
        for (var n = 1; n <= 7; n++) {
          final forward = splitEqually(total, n);
          final back = splitEqually(-total, n);
          for (var i = 0; i < n; i++) {
            expect(forward[i] + back[i], 0,
                reason: 'total=$total n=$n index=$i does not cancel');
          }
        }
      }
    });

    test('PROPERTY: sums exactly and spreads by at most one centavo', () {
      for (var total = -5000; total <= 5000; total++) {
        for (var n = 1; n <= 9; n++) {
          final parts = splitEqually(total, n);
          expect(parts.length, n);
          expect(parts.fold<int>(0, (a, b) => a + b), total,
              reason: 'total=$total n=$n does not sum back');
          final lo = parts.reduce((a, b) => a < b ? a : b);
          final hi = parts.reduce((a, b) => a > b ? a : b);
          expect(hi - lo, lessThanOrEqualTo(1),
              reason: 'total=$total n=$n spread too wide');
        }
      }
    });

    test('rejects a non-positive participant count', () {
      expect(() => splitEqually(100, 0), throwsArgumentError);
      expect(() => splitEqually(100, -1), throwsArgumentError);
    });
  });

  group('allocateProportional', () {
    test('splits by weight and still sums exactly', () {
      // R$ 3.000,00 across contributions of 120k / 80k / 40k.
      final out = allocateProportional(300000, [120000, 80000, 40000]);
      expect(out, [150000, 100000, 50000]);
      expect(out.fold<int>(0, (a, b) => a + b), 300000);
    });

    test('largest-remainder assigns the odd centavo deterministically', () {
      final out = allocateProportional(100, [1, 1, 1]);
      expect(out.fold<int>(0, (a, b) => a + b), 100);
      expect(out, [34, 33, 33]);
    });

    test('a zero-weight participant receives nothing', () {
      final out = allocateProportional(1000, [1, 0, 1]);
      expect(out[1], 0);
      expect(out.fold<int>(0, (a, b) => a + b), 1000);
    });

    test('negative amounts (a loss) distribute proportionally too', () {
      final out = allocateProportional(-300000, [120000, 80000, 40000]);
      expect(out, [-150000, -100000, -50000]);
      expect(out.fold<int>(0, (a, b) => a + b), -300000);
    });

    test('BIGINT GUARD: extreme weights stay exact', () {
      // amountCents * weight here is ~1e22, which overflows a signed 64-bit
      // int and exceeds the 2^53 exact range of dart2js (this app ships a web
      // build). Do not delete this as unrealistic — it is the overflow canary.
      final out = allocateProportional(99999999999, [99999999999, 1]);
      expect(out, [99999999998, 1]);
      expect(out.fold<int>(0, (a, b) => a + b), 99999999999);
    });

    test('PROPERTY: always sums back to the input amount', () {
      const weightSets = [
        [1, 1, 1],
        [2, 1],
        [7, 11, 13],
        [1, 0, 0, 5],
        [100000, 1],
      ];
      for (final weights in weightSets) {
        for (var amount = -777; amount <= 777; amount += 7) {
          final out = allocateProportional(amount, weights);
          expect(out.fold<int>(0, (a, b) => a + b), amount,
              reason: 'weights=$weights amount=$amount');
        }
      }
    });

    test('rejects empty, negative or all-zero weights', () {
      expect(() => allocateProportional(100, const []), throwsArgumentError);
      expect(
          () => allocateProportional(100, const [1, -1]), throwsArgumentError);
      expect(
          () => allocateProportional(100, const [0, 0]), throwsArgumentError);
    });
  });
}
