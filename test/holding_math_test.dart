import 'package:flutter_test/flutter_test.dart';

import 'package:my_finance_app/features/holding/domain/holding_math.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The equity math behind a Holding Carteira.
//
// The scenario used throughout mirrors the one the user described: three
// sócios, unequal aportes, expenses split equally, and everyone needing to
// know exactly what they put in and what they own.
// ─────────────────────────────────────────────────────────────────────────────

const _alex = 'p_alex';
const _marina = 'p_marina';
const _roberto = 'p_roberto';
const _trio = [_alex, _marina, _roberto];

void main() {
  group('buildEqualSplit', () {
    test('splits to the centavo and always sums back', () {
      final s = buildEqualSplit(
        totalCents: 10000,
        participantIds: _trio,
        seed: 'tx1',
      );
      expect(s.totalCents, 10000);
      expect(s.shares.length, 3);
      expect(s.shares.fold<int>(0, (a, x) => a + x.cents), 10000);
      expect(s.isConsistent, isTrue);
      final values = s.shares.map((x) => x.cents).toList()..sort();
      expect(values, [3333, 3333, 3334]);
    });

    test(
        'rotates the odd centavo across expenses instead of always taxing '
        'the same sócio', () {
      // Over many expenses, the sócio absorbing the extra centavo must vary,
      // otherwise whoever sorts first systematically overpays.
      final absorbers = <String>{};
      for (var i = 0; i < 60; i++) {
        final s = buildEqualSplit(
          totalCents: 10000,
          participantIds: _trio,
          seed: 'tx$i',
        );
        final top = s.shares.reduce((a, b) => a.cents >= b.cents ? a : b);
        absorbers.add(top.participantId);
      }
      expect(absorbers.length, greaterThan(1),
          reason: 'the extra centavo never rotated');
    });

    test('is deterministic for the same seed', () {
      final a = buildEqualSplit(
          totalCents: 777, participantIds: _trio, seed: 'tx-abc');
      final b = buildEqualSplit(
          totalCents: 777, participantIds: _trio, seed: 'tx-abc');
      expect(a.shareOf(_alex), b.shareOf(_alex));
      expect(a.shareOf(_marina), b.shareOf(_marina));
      expect(a.shareOf(_roberto), b.shareOf(_roberto));
    });

    test('participant order does not change the result', () {
      final a =
          buildEqualSplit(totalCents: 1000, participantIds: _trio, seed: 's');
      final b = buildEqualSplit(
          totalCents: 1000,
          participantIds: const [_roberto, _alex, _marina],
          seed: 's');
      expect(a.shareOf(_alex), b.shareOf(_alex));
      expect(a.shareOf(_marina), b.shareOf(_marina));
    });

    test('a Holding with no sócios produces an empty split, not a crash', () {
      final s = buildEqualSplit(
          totalCents: 5000, participantIds: const [], seed: 'tx');
      expect(s.shares, isEmpty);
      expect(s.shareOf(_alex), 0);
    });

    test('a single sócio owes the whole expense', () {
      final s = buildEqualSplit(
          totalCents: 5000, participantIds: const [_alex], seed: 'tx');
      expect(s.shareOf(_alex), 5000);
    });

    test('reversed() exactly undoes a split (estorno)', () {
      final s =
          buildEqualSplit(totalCents: 10001, participantIds: _trio, seed: 'x');
      final r = s.reversed();
      expect(r.totalCents, -10001);
      for (final id in _trio) {
        expect(s.shareOf(id) + r.shareOf(id), 0);
      }
    });

    test('isConsistent catches a split gone stale after an amount edit', () {
      const stale = SplitSnapshot(
        totalCents: 9000, // amount was edited up, shares were not recomputed
        shares: [
          SplitShare(_alex, 3334),
          SplitShare(_marina, 3333),
          SplitShare(_roberto, 3333),
        ],
      );
      expect(stale.isConsistent, isFalse);
    });
  });

  group('proportionalQuotas', () {
    test('quota follows what each sócio put in', () {
      final t = proportionalQuotas(_trio, const {
        _alex: 12000000, // R$ 120.000
        _marina: 8000000,
        _roberto: 4000000,
      });
      expect(t.isUsable, isTrue);
      expect(t.quotaOf(_alex).percent, closeTo(50, 0.001));
      expect(t.quotaOf(_marina).percent, closeTo(33.333, 0.01));
      expect(t.quotaOf(_roberto).percent, closeTo(16.667, 0.01));
    });

    test('with no aportes the quotas are UNDEFINED, never zero', () {
      final t = proportionalQuotas(_trio, const {});
      expect(t.status, QuotaStatus.noContributions);
      expect(t.isUsable, isFalse);
      expect(t.quotaOf(_alex).isUndefined, isTrue);
      expect(t.quotaOf(_alex).percent, isNull);
    });

    test('a negative contribution total is flagged as corrupt', () {
      final t = proportionalQuotas(_trio, const {_alex: -100});
      expect(t.status, QuotaStatus.negativeContribution);
      expect(t.isUsable, isFalse);
    });
  });

  group('fixedQuotas', () {
    test('accepts percentages that total exactly 100%', () {
      final t = fixedQuotas(
          _trio, const {_alex: 5000, _marina: 3000, _roberto: 2000});
      expect(t.isUsable, isTrue);
      expect(t.quotaOf(_marina).percent, closeTo(30, 0.001));
    });

    test('rejects percentages that do not total 100%', () {
      final t = fixedQuotas(
          _trio, const {_alex: 5000, _marina: 3000, _roberto: 1000});
      expect(t.status, QuotaStatus.invalidFixed);
      expect(t.isUsable, isFalse);
    });

    test('accepts thirds that no double could validate', () {
      // 100/3 as a double sums to 99.99999999999999 — basis points do not.
      final t = fixedQuotas(
          _trio, const {_alex: 3334, _marina: 3333, _roberto: 3333});
      expect(t.isUsable, isTrue);
    });

    test('validateFixedQuotas reports how far from 100% the user is', () {
      final v = validateFixedQuotas(const {_alex: 5000, _marina: 3000});
      expect(v.isValid, isFalse);
      expect(v.deltaBps, -2000); // 20 percentage points short
      expect(validateFixedQuotas(const {_alex: 12000}).hasOutOfRange, isTrue);
      expect(validateFixedQuotas(const {_alex: -1}).hasOutOfRange, isTrue);
    });
  });

  group('patrimonyByParticipant', () {
    test('divides the Holding net worth by quota, exactly', () {
      final t = proportionalQuotas(_trio, const {
        _alex: 12000000,
        _marina: 8000000,
        _roberto: 4000000,
      });
      final p = patrimonyByParticipant(_trio, t, 30000000)!;
      expect(p[_alex], 15000000); // R$ 150.000
      expect(p[_marina], 10000000);
      expect(p[_roberto], 5000000);
      expect(p.values.fold<int>(0, (a, b) => a + b), 30000000);
    });

    test('never loses a centavo on an indivisible net worth', () {
      final t =
          proportionalQuotas(_trio, const {_alex: 1, _marina: 1, _roberto: 1});
      final p = patrimonyByParticipant(_trio, t, 100)!;
      expect(p.values.fold<int>(0, (a, b) => a + b), 100);
    });

    test('a NEGATIVE net worth gives each sócio their share of the hole', () {
      final t =
          proportionalQuotas(_trio, const {_alex: 2, _marina: 1, _roberto: 1});
      final p = patrimonyByParticipant(_trio, t, -100000)!;
      expect(p[_alex], -50000);
      expect(p.values.fold<int>(0, (a, b) => a + b), -100000);
    });

    test(
        'returns null when quotas are undefined, so the UI can say '
        '"indisponível" instead of showing zero', () {
      final t = proportionalQuotas(_trio, const {});
      expect(patrimonyByParticipant(_trio, t, 500000), isNull);
    });
  });

  group('contributionGaps (fixed mode)', () {
    test('reports who is behind and who is ahead of their quota', () {
      final gaps = contributionGaps(
        ids: _trio,
        bpsById: const {_alex: 5000, _marina: 3000, _roberto: 2000},
        contributions: const {
          _alex: 12000000,
          _marina: 8000000,
          _roberto: 4000000,
        },
      );
      // Total contributed = 240.000; quotas want 120.000 / 72.000 / 48.000.
      expect(gaps[_alex]!.expected, 12000000);
      expect(gaps[_alex]!.delta, 0);
      expect(gaps[_marina]!.expected, 7200000);
      expect(gaps[_marina]!.delta, 800000); // R$ 8.000 ahead
      expect(gaps[_roberto]!.expected, 4800000);
      expect(gaps[_roberto]!.delta, -800000); // R$ 8.000 behind
    });

    test('the gaps always net to zero', () {
      final gaps = contributionGaps(
        ids: _trio,
        bpsById: const {_alex: 3334, _marina: 3333, _roberto: 3333},
        contributions: const {_alex: 100, _marina: 33, _roberto: 1},
      );
      expect(gaps.values.fold<int>(0, (a, g) => a + g.delta), 0);
    });
  });

  group('rateioBalances', () {
    test('accumulates expense shares and aportes into a saldo', () {
      final s1 = buildEqualSplit(
        totalCents: 30000, // R$ 300, Alexandre paid
        participantIds: _trio,
        seed: 'tx1',
        paidByParticipantId: _alex,
      );
      final b = rateioBalances(
        ids: _trio,
        contributions: const {_alex: 100000},
        splits: [s1],
      );
      // Alexandre: put in 1000 + fronted 300 - owes 100 = 1200 credit.
      expect(b[_alex]!.contributed, 100000);
      expect(b[_alex]!.paidOnBehalf, 30000);
      expect(b[_alex]!.owed, 10000);
      expect(b[_alex]!.saldo, 120000);
      // The other two owe their share.
      expect(b[_marina]!.saldo, -10000);
      expect(b[_roberto]!.saldo, -10000);
    });

    test('the whole Holding always nets to the money put in', () {
      final splits = [
        buildEqualSplit(
            totalCents: 10001,
            participantIds: _trio,
            seed: 'a',
            paidByParticipantId: _marina),
        buildEqualSplit(
            totalCents: 777,
            participantIds: _trio,
            seed: 'b',
            paidByParticipantId: _roberto),
      ];
      const contributions = {_alex: 5000, _marina: 2500, _roberto: 100};
      final b = rateioBalances(
          ids: _trio, contributions: contributions, splits: splits);
      final totalSaldo = b.values.fold<int>(0, (a, x) => a + x.saldo);
      final totalIn = contributions.values.fold<int>(0, (a, x) => a + x);
      expect(totalSaldo, totalIn);
    });

    test('a sócio added LATER does not inherit older expenses', () {
      // Expense split between two, before Roberto joined.
      final old = buildEqualSplit(
        totalCents: 10000,
        participantIds: const [_alex, _marina],
        seed: 'old',
      );
      final b = rateioBalances(
        ids: _trio,
        contributions: const {},
        splits: [old],
      );
      expect(b[_roberto]!.owed, 0);
      expect(b[_alex]!.owed, 5000);
      expect(b[_marina]!.owed, 5000);
    });

    test('a sócio who LEFT does not erase history for the others', () {
      final old =
          buildEqualSplit(totalCents: 9000, participantIds: _trio, seed: 'old');
      final b = rateioBalances(
        ids: const [_alex, _marina], // Roberto removed from the roster
        contributions: const {},
        splits: [old],
      );
      expect(b[_alex]!.owed, 3000);
      expect(b[_marina]!.owed, 3000);
      expect(b.containsKey(_roberto), isFalse);
    });
  });

  group('settle', () {
    test('resolves the classic case in a single transfer', () {
      final t = settle(const {_alex: 4000000, _marina: 0, _roberto: -4000000});
      expect(t.length, 1);
      expect(t.first.fromId, _roberto);
      expect(t.first.toId, _alex);
      expect(t.first.cents, 4000000);
    });

    test('never needs more than n-1 transfers and clears every debt', () {
      const saldos = {
        'a': -3000,
        'b': -1500,
        'c': 2500,
        'd': 2000,
      };
      final t = settle(saldos);
      expect(t.length, lessThanOrEqualTo(saldos.length - 1));
      final net = <String, int>{for (final k in saldos.keys) k: saldos[k]!};
      for (final x in t) {
        net[x.fromId] = net[x.fromId]! + x.cents;
        net[x.toId] = net[x.toId]! - x.cents;
      }
      expect(net.values.every((v) => v == 0), isTrue,
          reason: 'settlement left a residue: $net');
    });

    test('an already-even group needs no transfers', () {
      expect(settle(const {_alex: 0, _marina: 0}), isEmpty);
    });
  });
}
