import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../budget/presentation/providers/budget_provider.dart';
import '../../../goals/presentation/providers/goals_provider.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../data/financial_score_calculator.dart';
import '../../domain/financial_score.dart';

/// Composes existing providers and runs the calculator. The score
/// rebuilds whenever transactions, budgets or goals change.
final financialScoreProvider = Provider<FinancialScore>((ref) {
  final transactions = ref.watch(visibleTransactionsProvider);
  final budgetSummaries = ref.watch(budgetSummaryProvider);
  final goals = ref.watch(goalsStreamProvider).value ?? [];
  final balance = ref.watch(balanceProvider);

  final goalContribs = <String, double>{};
  for (final t in transactions) {
    final id = t.goalId;
    if (id == null || id.isEmpty) continue;
    goalContribs[id] = (goalContribs[id] ?? 0) + t.amount;
  }

  return FinancialScoreCalculator().calculate(
    transactions: transactions,
    currentMonthBudgets: budgetSummaries,
    goals: goals,
    goalContributedAmounts: goalContribs,
    totalBalance: balance,
  );
});
