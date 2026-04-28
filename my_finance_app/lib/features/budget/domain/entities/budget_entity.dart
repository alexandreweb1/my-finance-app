import 'package:equatable/equatable.dart';

class BudgetEntity extends Equatable {
  final String id;
  final String userId;
  final String categoryId;
  final String categoryName;
  final double limitAmount;
  /// First day of the budget month (e.g. 2025-01-01 00:00:00).
  final DateTime month;

  const BudgetEntity({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.categoryName,
    required this.limitAmount,
    required this.month,
  });

  @override
  List<Object?> get props =>
      [id, userId, categoryId, categoryName, limitAmount, month];
}

/// View-model combining a budget with its computed spent amount.
class BudgetSummary {
  final BudgetEntity budget;
  final double spentAmount;

  const BudgetSummary({required this.budget, required this.spentAmount});

  /// Visual progress for the bar — capped at 1.0 so the indicator
  /// doesn't overflow.
  double get progress =>
      budget.limitAmount > 0
          ? (spentAmount / budget.limitAmount).clamp(0.0, 1.0)
          : 0.0;

  /// Real percentage of the budget consumed — can exceed 100% when
  /// the user has spent more than the limit.
  double get percentage =>
      budget.limitAmount > 0 ? (spentAmount / budget.limitAmount) * 100 : 0.0;

  bool get isOverBudget => spentAmount > budget.limitAmount;

  double get remaining => budget.limitAmount - spentAmount;
}
