import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/budget_entity.dart';

abstract class BudgetRepository {
  Stream<Either<Failure, List<BudgetEntity>>> watchBudgets(
      String userId, DateTime month);
  Future<Either<Failure, BudgetEntity>> setBudget(BudgetEntity budget);
  Future<Either<Failure, void>> deleteBudget(String budgetId);
}
