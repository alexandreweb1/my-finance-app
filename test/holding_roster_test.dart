import 'package:flutter_test/flutter_test.dart';

import 'package:my_finance_app/features/holding/domain/holding_entities.dart';
import 'package:my_finance_app/features/holding/domain/holding_math.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The roster is what makes a rateio honest: who was participating on the day an
// expense happened is a pure function of that date, so a sócio joining or
// leaving later can never rewrite money that was already divided.
// ─────────────────────────────────────────────────────────────────────────────

HoldingMemberEntity _m(
  String id, {
  required DateTime joinedAt,
  DateTime? leftAt,
  String? memberUid,
  int quotaBps = 0,
}) =>
    HoldingMemberEntity(
      id: id,
      userId: 'owner1',
      workspaceId: 'ws_holding',
      name: id,
      memberUid: memberUid,
      quotaBps: quotaBps,
      joinedAt: joinedAt,
      leftAt: leftAt,
      createdAt: DateTime(2024, 1, 1),
    );

final _jan = DateTime(2025, 1, 1);
final _jun = DateTime(2025, 6, 1);
final _dez = DateTime(2025, 12, 1);

void main() {
  group('participatesOn', () {
    test('excludes expenses dated before the sócio joined', () {
      final m = _m('a', joinedAt: _jun);
      expect(m.participatesOn(_jan), isFalse);
      expect(m.participatesOn(_jun), isTrue);
      expect(m.participatesOn(_dez), isTrue);
    });

    test('the join date itself counts as participating', () {
      final m = _m('a', joinedAt: _jun);
      expect(m.participatesOn(_jun), isTrue);
    });

    test('excludes expenses from the day the sócio left onward', () {
      final m = _m('a', joinedAt: _jan, leftAt: _jun);
      expect(m.participatesOn(_jan), isTrue);
      expect(m.participatesOn(_jun), isFalse);
      expect(m.participatesOn(_dez), isFalse);
    });

    test('a sócio with no leave date participates indefinitely', () {
      final m = _m('a', joinedAt: _jan);
      expect(m.isActive, isTrue);
      expect(m.participatesOn(DateTime(2099)), isTrue);
    });
  });

  group('rosterAsOf', () {
    test('returns only who was in on that date, sorted deterministically', () {
      final members = [
        _m('c', joinedAt: _jan),
        _m('a', joinedAt: _jan),
        _m('b', joinedAt: _dez), // joined later
      ];
      expect(rosterAsOf(members, _jun).map((m) => m.id).toList(), ['a', 'c']);
      expect(
          rosterAsOf(members, _dez).map((m) => m.id).toList(), ['a', 'b', 'c']);
    });

    test('a Holding with nobody yet returns an empty roster, not a crash', () {
      expect(rosterAsOf(const [], _jun), isEmpty);
    });

    test('order of the input list does not change the result', () {
      final a = [_m('x', joinedAt: _jan), _m('y', joinedAt: _jan)];
      final b = [_m('y', joinedAt: _jan), _m('x', joinedAt: _jan)];
      expect(rosterAsOf(a, _jun).map((m) => m.id).toList(),
          rosterAsOf(b, _jun).map((m) => m.id).toList());
    });
  });

  group('freezing: the past never changes', () {
    test('adding a sócio today does not touch an expense from before', () {
      final founders = [
        _m('alex', joinedAt: _jan),
        _m('marina', joinedAt: _jan)
      ];

      // An expense in June, split between the two founders.
      final juneRoster = rosterAsOf(founders, _jun);
      final juneSplit = buildEqualSplit(
        totalCents: 10000,
        participantIds: juneRoster.map((m) => m.id).toList(),
        seed: 'tx_june',
      );
      expect(juneSplit.shareOf('alex'), 5000);
      expect(juneSplit.shareOf('marina'), 5000);

      // Roberto joins in December.
      final withRoberto = [...founders, _m('roberto', joinedAt: _dez)];

      // Recomputing the SAME June expense still excludes him.
      final recomputed = rosterAsOf(withRoberto, _jun);
      expect(recomputed.map((m) => m.id).toList(), ['alex', 'marina']);
      final again = buildEqualSplit(
        totalCents: 10000,
        participantIds: recomputed.map((m) => m.id).toList(),
        seed: 'tx_june',
      );
      expect(again.shareOf('roberto'), 0);
      expect(again.shareOf('alex'), juneSplit.shareOf('alex'));
      expect(again.shareOf('marina'), juneSplit.shareOf('marina'));

      // A December expense DOES include him.
      final dezSplit = buildEqualSplit(
        totalCents: 9000,
        participantIds: rosterAsOf(withRoberto, _dez).map((m) => m.id).toList(),
        seed: 'tx_dez',
      );
      expect(dezSplit.shareOf('roberto'), 3000);
    });

    test('a sócio who leaves keeps their old shares but takes no new ones', () {
      final members = [
        _m('alex', joinedAt: _jan),
        _m('marina', joinedAt: _jan),
        _m('roberto', joinedAt: _jan, leftAt: _jun),
      ];

      final before = buildEqualSplit(
        totalCents: 9000,
        participantIds: rosterAsOf(members, _jan).map((m) => m.id).toList(),
        seed: 'old',
      );
      expect(before.shareOf('roberto'), 3000);

      final after = buildEqualSplit(
        totalCents: 9000,
        participantIds: rosterAsOf(members, _dez).map((m) => m.id).toList(),
        seed: 'new',
      );
      expect(after.shareOf('roberto'), 0);
      expect(after.shareOf('alex'), 4500);

      // The departed sócio's history still folds into everyone's balance.
      final balances = rateioBalances(
        ids: const ['alex', 'marina', 'roberto'],
        contributions: const {},
        splits: [before, after],
      );
      expect(balances['roberto']!.owed, 3000);
      expect(balances['alex']!.owed, 7500);
    });
  });

  group('contribution entity', () {
    test('a negative amount reads as a retirada', () {
      final c = HoldingContributionEntity(
        id: 'c1',
        userId: 'owner1',
        workspaceId: 'ws_holding',
        memberId: 'alex',
        amountCents: -50000,
        date: _jun,
        createdBy: 'owner1',
        createdAt: _jun,
      );
      expect(c.isWithdrawal, isTrue);
      expect(c.amountReais, -500.0);
    });

    test('an aporte converts back to reais exactly', () {
      final c = HoldingContributionEntity(
        id: 'c2',
        userId: 'owner1',
        workspaceId: 'ws_holding',
        memberId: 'alex',
        amountCents: 12000007,
        date: _jun,
        createdBy: 'owner1',
        createdAt: _jun,
      );
      expect(c.isWithdrawal, isFalse);
      expect(c.amountReais, 120000.07);
    });
  });

  group('member kinds', () {
    test('a sócio linked to an app user is marked as such', () {
      expect(_m('a', joinedAt: _jan, memberUid: 'uid_123').isLinked, isTrue);
    });

    test('a typed-in participant with no account is not linked', () {
      expect(_m('a', joinedAt: _jan).isLinked, isFalse);
      expect(_m('a', joinedAt: _jan, memberUid: '').isLinked, isFalse);
    });

    test('copyWith can clear the leave date to reinstate a sócio', () {
      final left = _m('a', joinedAt: _jan, leftAt: _jun);
      expect(left.copyWith(clearLeftAt: true).isActive, isTrue);
      expect(left.copyWith(quotaBps: 5000).quotaBps, 5000);
      expect(left.copyWith(quotaBps: 5000).leftAt, _jun);
    });
  });
}
