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

  double get progress =>
      budget.limitAmount > 0
          ? (spentAmount / budget.limitAmount).clamp(0.0, 1.0)
          : 0.0;

  double get percentage => progress * 100;

  bool get isOverBudget => spentAmount > budget.limitAmount;
}
