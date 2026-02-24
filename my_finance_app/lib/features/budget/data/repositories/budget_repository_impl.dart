import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../datasources/budget_remote_datasource.dart';
import '../models/budget_model.dart';

class BudgetRepositoryImpl implements BudgetRepository {
  final BudgetRemoteDataSource remoteDataSource;

  BudgetRepositoryImpl(this.remoteDataSource);

  @override
  Stream<Either<Failure, List<BudgetEntity>>> watchBudgets(
      String userId, DateTime month) {
    return remoteDataSource
        .watchBudgets(userId, month)
        .map<Either<Failure, List<BudgetEntity>>>(
          (models) => Right(models),
        )
        .handleError(
          (e) => Left(ServerFailure(e.toString())),
        );
  }

  @override
  Future<Either<Failure, BudgetEntity>> setBudget(BudgetEntity budget) async {
    try {
      final model = BudgetModel.fromEntity(budget);
      final result = await remoteDataSource.setBudget(model);
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, void>> deleteBudget(String budgetId) async {
    try {
      await remoteDataSource.deleteBudget(budgetId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
