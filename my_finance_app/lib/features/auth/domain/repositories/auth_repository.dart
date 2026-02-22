import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/user_entity.dart';

abstract class AuthRepository {
  Future<Either<Failure, UserEntity>> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<Either<Failure, UserEntity>> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  });

  Future<Either<Failure, void>> signOut();

  Stream<UserEntity?> get authStateChanges;

  Future<Either<Failure, UserEntity?>> getCurrentUser();
}
