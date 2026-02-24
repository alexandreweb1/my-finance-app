import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasources/category_remote_datasource.dart';
import '../models/category_model.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  final CategoryRemoteDataSource remoteDataSource;

  CategoryRepositoryImpl(this.remoteDataSource);

  @override
  Stream<Either<Failure, List<CategoryEntity>>> watchCategories(
      String userId) {
    return remoteDataSource.watchCategories(userId).map<Either<Failure, List<CategoryEntity>>>(
      (models) => Right(models),
    ).handleError(
      (e) => Left(ServerFailure(e.toString())),
    );
  }

  @override
  Future<Either<Failure, CategoryEntity>> addCategory(
      CategoryEntity category) async {
    try {
      final model = CategoryModel.fromEntity(category);
      final result = await remoteDataSource.addCategory(model);
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, void>> deleteCategory(String categoryId) async {
    try {
      await remoteDataSource.deleteCategory(categoryId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }

  @override
  Future<Either<Failure, void>> seedDefaults(String userId) async {
    try {
      await remoteDataSource.seedDefaults(userId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    }
  }
}
