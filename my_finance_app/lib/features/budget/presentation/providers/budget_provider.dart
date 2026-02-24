import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/transactions/presentation/providers/transactions_provider.dart';
import '../../data/datasources/budget_remote_datasource.dart';
import '../../data/repositories/budget_repository_impl.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../../domain/usecases/delete_budget_usecase.dart';
import '../../domain/usecases/get_budgets_usecase.dart';
import '../../domain/usecases/set_budget_usecase.dart';

// --- Infrastructure ---

final budgetDataSourceProvider = Provider<BudgetRemoteDataSource>(
  (ref) => BudgetRemoteDataSourceImpl(ref.watch(firestoreProvider)),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepositoryImpl(ref.watch(budgetDataSourceProvider)),
);

// --- Use Cases ---

final getBudgetsUseCaseProvider = Provider(
  (ref) => GetBudgetsUseCase(ref.watch(budgetRepositoryProvider)),
);

final setBudgetUseCaseProvider = Provider(
  (ref) => SetBudgetUseCase(ref.watch(budgetRepositoryProvider)),
);

final deleteBudgetUseCaseProvider = Provider(
  (ref) => DeleteBudgetUseCase(ref.watch(budgetRepositoryProvider)),
);

// --- Selected Month ---

final selectedMonthProvider = StateProvider<DateTime>(
  (ref) => DateTime(DateTime.now().year, DateTime.now().month, 1),
);

// --- Stream Providers ---

final budgetsStreamProvider = StreamProvider<List<BudgetEntity>>((ref) {
  final authState = ref.watch(authStateProvider);
  final month = ref.watch(selectedMonthProvider);
  return authState.when(
    data: (user) {
      if (user == null) return const Stream.empty();
      return ref
          .watch(getBudgetsUseCaseProvider)
          .call(GetBudgetsParams(userId: user.id, month: month))
          .map((either) => either.getOrElse(() => []));
    },
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});

/// Budgets from the month immediately before [selectedMonthProvider].
final previousMonthBudgetsProvider = StreamProvider<List<BudgetEntity>>((ref) {
  final authState = ref.watch(authStateProvider);
  final month = ref.watch(selectedMonthProvider);
  final prevMonth = DateTime(month.year, month.month - 1, 1);
  return authState.when(
    data: (user) {
      if (user == null) return const Stream.empty();
      return ref
          .watch(getBudgetsUseCaseProvider)
          .call(GetBudgetsParams(userId: user.id, month: prevMonth))
          .map((either) => either.getOrElse(() => []));
    },
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});

// --- Budget Summary Provider (joins budgets + transactions) ---

final budgetSummaryProvider = Provider<List<BudgetSummary>>((ref) {
  final budgets = ref.watch(budgetsStreamProvider).value ?? [];
  final transactions = ref.watch(transactionsStreamProvider).value ?? [];
  final month = ref.watch(selectedMonthProvider);

  return budgets.map((budget) {
    final spent = transactions
        .where((t) =>
            t.isExpense &&
            t.category == budget.categoryName &&
            t.date.year == month.year &&
            t.date.month == month.month)
        .fold(0.0, (sum, t) => sum + t.amount);
    return BudgetSummary(budget: budget, spentAmount: spent);
  }).toList();
});

// --- Notifier ---

class BudgetNotifier extends StateNotifier<AsyncValue<void>> {
  final SetBudgetUseCase _setBudget;
  final DeleteBudgetUseCase _deleteBudget;
  final String _userId;

  BudgetNotifier(this._setBudget, this._deleteBudget, this._userId)
      : super(const AsyncValue.data(null));

  Future<bool> set({
    required String categoryId,
    required String categoryName,
    required double limitAmount,
    required DateTime month,
  }) async {
    state = const AsyncValue.loading();
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final id =
        '${_userId}_${categoryId}_${firstOfMonth.year}-${firstOfMonth.month.toString().padLeft(2, '0')}';
    final budget = BudgetEntity(
      id: id,
      userId: _userId,
      categoryId: categoryId,
      categoryName: categoryName,
      limitAmount: limitAmount,
      month: firstOfMonth,
    );
    final result = await _setBudget(SetBudgetParams(budget: budget));
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

  Future<bool> copyFromPreviousMonth({
    required List<BudgetEntity> previousBudgets,
    required DateTime targetMonth,
  }) async {
    if (previousBudgets.isEmpty) return false;
    state = const AsyncValue.loading();
    final firstOfMonth = DateTime(targetMonth.year, targetMonth.month, 1);
    for (final budget in previousBudgets) {
      final id =
          '${_userId}_${budget.categoryId}_${firstOfMonth.year}-${firstOfMonth.month.toString().padLeft(2, '0')}';
      final newBudget = BudgetEntity(
        id: id,
        userId: _userId,
        categoryId: budget.categoryId,
        categoryName: budget.categoryName,
        limitAmount: budget.limitAmount,
        month: firstOfMonth,
      );
      final result = await _setBudget(SetBudgetParams(budget: newBudget));
      final failed = result.fold((_) => true, (_) => false);
      if (failed) {
        state = AsyncValue.error(
            'Erro ao copiar orçamentos.', StackTrace.current);
        return false;
      }
    }
    state = const AsyncValue.data(null);
    return true;
  }

  Future<bool> delete(String budgetId) async {
    state = const AsyncValue.loading();
    final result =
        await _deleteBudget(DeleteBudgetParams(budgetId: budgetId));
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

final budgetNotifierProvider =
    StateNotifierProvider<BudgetNotifier, AsyncValue<void>>((ref) {
  final user = ref.watch(authStateProvider).value;
  return BudgetNotifier(
    ref.watch(setBudgetUseCaseProvider),
    ref.watch(deleteBudgetUseCaseProvider),
    user?.id ?? '',
  );
});
