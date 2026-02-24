import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/datasources/transaction_remote_datasource.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/add_transaction_usecase.dart';
import '../../domain/usecases/delete_transaction_usecase.dart';
import '../../domain/usecases/get_transactions_usecase.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// --- Infrastructure ---

final transactionDataSourceProvider = Provider<TransactionRemoteDataSource>(
  (ref) => TransactionRemoteDataSourceImpl(ref.watch(firestoreProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(ref.watch(transactionDataSourceProvider)),
);

// --- Use Cases ---

final getTransactionsUseCaseProvider = Provider(
  (ref) => GetTransactionsUseCase(ref.watch(transactionRepositoryProvider)),
);

final addTransactionUseCaseProvider = Provider(
  (ref) => AddTransactionUseCase(ref.watch(transactionRepositoryProvider)),
);

final deleteTransactionUseCaseProvider = Provider(
  (ref) => DeleteTransactionUseCase(ref.watch(transactionRepositoryProvider)),
);

// --- Stream Providers ---

final transactionsStreamProvider =
    StreamProvider<List<TransactionEntity>>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return const Stream.empty();
      return ref
          .watch(getTransactionsUseCaseProvider)
          .call(GetTransactionsParams(userId: user.id))
          .map((either) => either.getOrElse(() => []));
    },
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});

// --- Summary Providers ---

final balanceProvider = Provider<double>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];
  return transactions.fold(0.0, (sum, t) {
    return t.isIncome ? sum + t.amount : sum - t.amount;
  });
});

final totalIncomeProvider = Provider<double>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];
  return transactions
      .where((t) => t.isIncome)
      .fold(0.0, (sum, t) => sum + t.amount);
});

final totalExpenseProvider = Provider<double>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];
  return transactions
      .where((t) => t.isExpense)
      .fold(0.0, (sum, t) => sum + t.amount);
});

// --- Notifier for mutations ---

class TransactionsNotifier extends StateNotifier<AsyncValue<void>> {
  final AddTransactionUseCase _addTransaction;
  final DeleteTransactionUseCase _deleteTransaction;
  final String _userId;

  TransactionsNotifier(
    this._addTransaction,
    this._deleteTransaction,
    this._userId,
  ) : super(const AsyncValue.data(null));

  Future<bool> add({
    required String title,
    required double amount,
    required TransactionType type,
    required String category,
    required DateTime date,
    String? description,
  }) async {
    state = const AsyncValue.loading();
    final transaction = TransactionEntity(
      id: const Uuid().v4(),
      userId: _userId,
      title: title,
      amount: amount,
      type: type,
      category: category,
      date: date,
      description: description,
    );
    final result = await _addTransaction(
        AddTransactionParams(transaction: transaction));
    return result.fold(
      (failure) {
        state = AsyncValue.error(failure.message, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue.data(null);
        return true;
      },
    );
  }

  Future<bool> delete(String transactionId) async {
    state = const AsyncValue.loading();
    final result = await _deleteTransaction(
        DeleteTransactionParams(transactionId: transactionId));
    return result.fold(
      (failure) {
        state = AsyncValue.error(failure.message, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue.data(null);
        return true;
      },
    );
  }
}

final transactionsNotifierProvider =
    StateNotifierProvider<TransactionsNotifier, AsyncValue<void>>((ref) {
  final user = ref.watch(authStateProvider).value;
  return TransactionsNotifier(
    ref.watch(addTransactionUseCaseProvider),
    ref.watch(deleteTransactionUseCaseProvider),
    user?.id ?? '',
  );
});
