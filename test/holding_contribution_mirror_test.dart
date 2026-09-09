import 'package:flutter_test/flutter_test.dart';

import 'package:my_finance_app/features/holding/presentation/providers/holding_provider.dart';
import 'package:my_finance_app/features/transactions/data/models/transaction_model.dart';
import 'package:my_finance_app/features/transactions/domain/entities/transaction_entity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Auditoria 2026-09-08 #4: the Extrato half of a Holding aporte could be
// swiped away or edited on its own, leaving the cap table describing money the
// ledger no longer had. The lock is decided by isContributionMirror(); these
// tests pin down exactly which transactions it locks.
// ─────────────────────────────────────────────────────────────────────────────

TransactionEntity _tx(String id, {String? contributionId}) => TransactionEntity(
      id: id,
      userId: 'owner',
      title: 'Aporte — Maria',
      amount: 1000,
      type: TransactionType.transfer,
      category: 'Aporte',
      date: DateTime(2026, 9, 1),
      workspaceId: 'ws_h',
      holdingContributionId: contributionId,
    );

void main() {
  group('isContributionMirror', () {
    test('a back-reference on the transaction locks it', () {
      expect(isContributionMirror(_tx('t1', contributionId: 'hc1'), const {}),
          isTrue);
    });

    test('a mirror written before the field existed is recognised through '
        'the contribution\'s linkedTransactionId', () {
      expect(isContributionMirror(_tx('t1'), const {'t1'}), isTrue);
    });

    test('an ordinary transaction is not locked', () {
      expect(isContributionMirror(_tx('t2'), const {'t1'}), isFalse);
    });

    test('an empty back-reference counts as absent', () {
      expect(
          isContributionMirror(_tx('t2', contributionId: ''), const {}), isFalse);
    });
  });

  group('holdingContributionId', () {
    test('survives TransactionModel.fromEntity', () {
      final m = TransactionModel.fromEntity(_tx('t1', contributionId: 'hc1'));
      expect(m.holdingContributionId, 'hc1');
    });

    test('is part of entity equality', () {
      expect(_tx('t1', contributionId: 'hc1'), isNot(equals(_tx('t1'))));
      expect(_tx('t1', contributionId: 'hc1'),
          equals(_tx('t1', contributionId: 'hc1')));
    });
  });
}
