import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/category_remote_datasource.dart';
import '../../data/repositories/category_repository_impl.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/usecases/add_category_usecase.dart';
import '../../domain/usecases/delete_category_usecase.dart';
import '../../domain/usecases/get_categories_usecase.dart';

// --- Infrastructure ---

final categoryDataSourceProvider = Provider<CategoryRemoteDataSource>(
  (ref) => CategoryRemoteDataSourceImpl(ref.watch(firestoreProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) =>
      CategoryRepositoryImpl(ref.watch(categoryDataSourceProvider)),
);

// --- Use Cases ---

final getCategoriesUseCaseProvider = Provider(
  (ref) => GetCategoriesUseCase(ref.watch(categoryRepositoryProvider)),
);

final addCategoryUseCaseProvider = Provider(
  (ref) => AddCategoryUseCase(ref.watch(categoryRepositoryProvider)),
);

final deleteCategoryUseCaseProvider = Provider(
  (ref) => DeleteCategoryUseCase(ref.watch(categoryRepositoryProvider)),
);

// --- Stream Provider ---

final categoriesStreamProvider =
    StreamProvider<List<CategoryEntity>>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return const Stream.empty();
      return ref
          .watch(getCategoriesUseCaseProvider)
          .call(GetCategoriesParams(userId: user.id))
          .map((either) => either.getOrElse(() => []));
    },
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});

// --- Filtered Providers ---

final incomeCategoriesProvider = Provider<List<CategoryEntity>>((ref) {
  return ref.watch(categoriesStreamProvider).value?.where((c) => c.isIncome).toList() ?? [];
});

final expenseCategoriesProvider = Provider<List<CategoryEntity>>((ref) {
  return ref.watch(categoriesStreamProvider).value?.where((c) => c.isExpense).toList() ?? [];
});

// --- Seed initializer (activate in MainScreen) ---

final categoriesSeedProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<List<CategoryEntity>>>(
    categoriesStreamProvider,
    (_, next) {
      next.whenData((categories) {
        if (categories.isEmpty) {
          final user = ref.read(authStateProvider).value;
          if (user != null) {
            ref.read(categoriesNotifierProvider.notifier).seedDefaults(user.id);
          }
        }
      });
    },
  );
});

// --- Notifier ---

class CategoriesNotifier extends StateNotifier<AsyncValue<void>> {
  final AddCategoryUseCase _addCategory;
  final DeleteCategoryUseCase _deleteCategory;
  final CategoryRepository _repository;

  CategoriesNotifier(
    this._addCategory,
    this._deleteCategory,
    this._repository,
  ) : super(const AsyncValue.data(null));

  Future<bool> add({
    required String userId,
    required String name,
    required CategoryType type,
    required int iconCodePoint,
    required int colorValue,
  }) async {
    state = const AsyncValue.loading();
    final category = CategoryEntity(
      id: const Uuid().v4(),
      userId: userId,
      name: name,
      type: type,
      iconCodePoint: iconCodePoint,
      colorValue: colorValue,
    );
    final result = await _addCategory(AddCategoryParams(category: category));
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

  Future<bool> delete(String categoryId) async {
    state = const AsyncValue.loading();
    final result =
        await _deleteCategory(DeleteCategoryParams(categoryId: categoryId));
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

  Future<void> seedDefaults(String userId) async {
    final result = await _repository.seedDefaults(userId);
    result.fold(
      (failure) =>
          state = AsyncValue.error(failure.message, StackTrace.current),
      (_) => state = const AsyncValue.data(null),
    );
  }
}

final categoriesNotifierProvider =
    StateNotifierProvider<CategoriesNotifier, AsyncValue<void>>((ref) {
  return CategoriesNotifier(
    ref.watch(addCategoryUseCaseProvider),
    ref.watch(deleteCategoryUseCaseProvider),
    ref.watch(categoryRepositoryProvider),
  );
});
