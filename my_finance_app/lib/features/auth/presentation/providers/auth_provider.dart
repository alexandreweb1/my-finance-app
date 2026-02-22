import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/sign_in_usecase.dart';
import '../../domain/usecases/sign_out_usecase.dart';
import '../../domain/usecases/sign_up_usecase.dart';
import '../../../../core/usecases/usecase.dart';

// --- Infrastructure Providers ---

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (ref) => AuthRemoteDataSourceImpl(ref.watch(firebaseAuthProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider)),
);

// --- Use Case Providers ---

final signInUseCaseProvider = Provider(
  (ref) => SignInUseCase(ref.watch(authRepositoryProvider)),
);

final signUpUseCaseProvider = Provider(
  (ref) => SignUpUseCase(ref.watch(authRepositoryProvider)),
);

final signOutUseCaseProvider = Provider(
  (ref) => SignOutUseCase(ref.watch(authRepositoryProvider)),
);

// --- State Providers ---

final authStateProvider = StreamProvider<UserEntity?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges,
);

// --- Auth Notifier ---

class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final UserEntity? user;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.user,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    UserEntity? user,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final SignInUseCase _signIn;
  final SignUpUseCase _signUp;
  final SignOutUseCase _signOut;

  AuthNotifier(this._signIn, this._signUp, this._signOut)
      : super(const AuthState());

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _signIn(SignInParams(email: email, password: password));
    result.fold(
      (failure) => state = AuthState(errorMessage: failure.message),
      (user) => state = AuthState(user: user),
    );
  }

  Future<void> signUp(String email, String password, String? name) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _signUp(
      SignUpParams(email: email, password: password, displayName: name),
    );
    result.fold(
      (failure) => state = AuthState(errorMessage: failure.message),
      (user) => state = AuthState(user: user),
    );
  }

  Future<void> signOut() async {
    await _signOut(const NoParams());
    state = const AuthState();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.watch(signInUseCaseProvider),
    ref.watch(signUpUseCaseProvider),
    ref.watch(signOutUseCaseProvider),
  ),
);
