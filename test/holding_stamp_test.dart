import 'package:flutter_test/flutter_test.dart';

import 'package:my_finance_app/features/holding/domain/holding_entities.dart';
import 'package:my_finance_app/features/holding/domain/holding_stamp.dart';
import 'package:my_finance_app/features/transactions/domain/entities/transaction_entity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The write-path guard. Every transaction created inside a Holding must carry a
// frozen rateio — and, just as important, nothing created OUTSIDE one may.
// ─────────────────────────────────────────────────────────────────────────────

const _holding = 'ws_holding';
const _pf = 'ws_pf';

final _jan = DateTime(2026, 1, 1);
final _jun = DateTime(2026, 6, 10);

HoldingMemberEntity _member(
  String id, {
  String workspaceId = _holding,
  DateTime? joinedAt,
  DateTime? leftAt,
}) =>
    HoldingMemberEntity(
      id: id,
      userId: 'owner',
      workspaceId: workspaceId,
      name: id,
      joinedAt: joinedAt ?? _jan,
      leftAt: leftAt,
      createdAt: _jan,
    );

HoldingStamp _stampOf(List<HoldingMemberEntity> members) =>
    HoldingStamp(workspaceId: _holding, members: members);

final _trio = _stampOf([_member('p_a'), _member('p_b'), _member('p_c')]);

void main() {
  group('HoldingStamp.splitFor', () {
    test('splits an expense of the stamped Carteira, to the centavo', () {
      final split = _trio.splitFor(
        targetWorkspaceId: _holding,
        type: TransactionType.expense,
        amount: 100.00,
        date: _jun,
        seed: 'tx1',
      )!;
      expect(split.keys.toSet(), {'p_a', 'p_b', 'p_c'});
      expect(split.values.fold<int>(0, (a, b) => a + b), 10000);
    });

    test('R\$ 0,07 three ways loses nothing', () {
      final split = _trio.splitFor(
        targetWorkspaceId: _holding,
        type: TransactionType.expense,
        amount: 0.07,
        date: _jun,
        seed: 'tx1',
      )!;
      expect(split.values.fold<int>(0, (a, b) => a + b), 7);
      expect(split.values.toList()..sort(), [2, 2, 3]);
    });

    // THE guard: addAndReturnId takes a workspaceIdOverride and the bank
    // notification capture passes the DEFAULT Carteira, not the active one.
    test('refuses to split a doc landing in another Carteira', () {
      expect(
        _trio.splitFor(
          targetWorkspaceId: _pf,
          type: TransactionType.expense,
          amount: 100.00,
          date: _jun,
          seed: 'tx1',
        ),
        isNull,
      );
      expect(
        _trio.splitFor(
          targetWorkspaceId: null, // legacy doc, no workspaceId at all
          type: TransactionType.expense,
          amount: 100.00,
          date: _jun,
          seed: 'tx1',
        ),
        isNull,
      );
    });

    test('never splits income (an aporte) or a transfer', () {
      for (final t in [TransactionType.income, TransactionType.transfer]) {
        expect(
          _trio.splitFor(
            targetWorkspaceId: _holding,
            type: t,
            amount: 100.00,
            date: _jun,
            seed: 'tx1',
          ),
          isNull,
          reason: '$t must not be rateado',
        );
      }
    });

    test('no roster on that date → no split', () {
      final future =
          _stampOf([_member('p_a', joinedAt: DateTime(2026, 12, 1))]);
      expect(
        future.splitFor(
          targetWorkspaceId: _holding,
          type: TransactionType.expense,
          amount: 100.00,
          date: _jun,
          seed: 'tx1',
        ),
        isNull,
      );
      expect(
        _stampOf(const []).splitFor(
          targetWorkspaceId: _holding,
          type: TransactionType.expense,
          amount: 100.00,
          date: _jun,
          seed: 'tx1',
        ),
        isNull,
      );
    });

    test('the roster is the expense DATE, not today', () {
      final stamp = _stampOf([
        _member('p_a'),
        _member('p_b', leftAt: DateTime(2026, 3, 1)),
        _member('p_c', joinedAt: DateTime(2026, 5, 1)),
      ]);
      final feb = stamp.splitFor(
        targetWorkspaceId: _holding,
        type: TransactionType.expense,
        amount: 100.00,
        date: DateTime(2026, 2, 10),
        seed: 'tx1',
      )!;
      expect(feb.keys.toSet(), {'p_a', 'p_b'});
      final jun = stamp.splitFor(
        targetWorkspaceId: _holding,
        type: TransactionType.expense,
        amount: 100.00,
        date: _jun,
        seed: 'tx1',
      )!;
      expect(jun.keys.toSet(), {'p_a', 'p_c'});
    });

    test('a zero or corrupt amount stamps nothing instead of throwing', () {
      for (final amount in [0.0, double.nan, double.infinity]) {
        expect(
          _trio.splitFor(
            targetWorkspaceId: _holding,
            type: TransactionType.expense,
            amount: amount,
            date: _jun,
            seed: 'tx1',
          ),
          isNull,
          reason: 'amount $amount',
        );
      }
    });

    test('the same expense always splits the same way', () {
      Map<String, int> run() => _trio.splitFor(
            targetWorkspaceId: _holding,
            type: TransactionType.expense,
            amount: 10.00,
            date: _jun,
            seed: 'rec_abc_20260610',
          )!;
      expect(run(), run());
    });
  });

  group('resplitStored', () {
    final stored = {'p_a': 3334, 'p_b': 3333, 'p_c': 3333};

    test('keeps the STORED participants, never today\'s roster', () {
      final out =
          resplitStored(storedSplit: stored, amount: 60.00, seed: 'tx1')!;
      expect(out.keys.toSet(), {'p_a', 'p_b', 'p_c'});
      expect(out.values.fold<int>(0, (a, b) => a + b), 6000);
      expect(out.values.every((c) => c == 2000), isTrue);
    });

    test('no stored split → nothing to redo', () {
      expect(resplitStored(storedSplit: null, amount: 60.0, seed: 't'), isNull);
      expect(resplitStored(storedSplit: const {}, amount: 60.0, seed: 't'),
          isNull);
    });

    test('unchanged total → untouched (a title typo must not move money)', () {
      expect(
        resplitStored(storedSplit: stored, amount: 100.00, seed: 'tx1'),
        isNull,
      );
    });

    test('repairs a split that no longer adds up to the amount', () {
      final stale = {'p_a': 5000, 'p_b': 5000};
      final out =
          resplitStored(storedSplit: stale, amount: 30.00, seed: 'tx1')!;
      expect(out.values.fold<int>(0, (a, b) => a + b), 3000);
    });
  });
}
