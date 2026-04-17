import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/notification_suggestion.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/notification_backlog_datasource.dart';
import '../../data/models/notification_backlog_item_model.dart';
import '../../domain/entities/notification_backlog_item_entity.dart';

// ── Infrastructure ───────────────────────────────────────────────────────────

final backlogDatasourceProvider = Provider<NotificationBacklogDatasource>(
  (ref) =>
      NotificationBacklogFirestoreDatasource(ref.watch(firestoreProvider)),
);

// ── Stream ───────────────────────────────────────────────────────────────────

/// Streams all backlog items for the current user, newest first.
/// Uses the real authenticated UID (not effectiveUserId) because notification
/// backlog is per-device/per-user and must not use the master's UID when the
/// caller is a collaborator — that would cause Firestore permission-denied.
final backlogItemsStreamProvider =
    StreamProvider<List<NotificationBacklogItemEntity>>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return const Stream.empty();
      return ref.watch(backlogDatasourceProvider).watchItems(user.id);
    },
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
  );
});

/// Count of items not yet imported (used for the badge in settings).
final unimportedBacklogCountProvider = Provider<int>((ref) {
  return ref.watch(backlogItemsStreamProvider).when(
        data: (items) => items.where((i) => !i.imported).length,
        loading: () => 0,
        error: (_, __) => 0,
      );
});

// ── Notifier ─────────────────────────────────────────────────────────────────

class BacklogNotifier extends StateNotifier<AsyncValue<void>> {
  final NotificationBacklogDatasource _ds;
  final String _userId;

  BacklogNotifier(this._ds, this._userId)
      : super(const AsyncValue.data(null));

  /// Called from main_screen when a bank notification is received.
  /// Runs silently — failures are swallowed so they never break the
  /// existing notification → transaction flow.
  Future<void> addFromSuggestion(NotificationSuggestion suggestion) async {
    if (_userId.isEmpty) return;
    try {
      final item = NotificationBacklogItemModel(
        id: '', // Firestore assigns the real ID on add()
        userId: _userId,
        amount: suggestion.amount,
        type: suggestion.type,
        rawText: suggestion.rawText,
        sourceApp: suggestion.sourceApp,
        receivedAt: DateTime.now(),
        imported: false,
      );
      await _ds.addItem(item);
    } catch (_) {
      // Intentionally silent: backlog is best-effort.
    }
  }

  /// Marks one item as imported without removing it from the list.
  Future<void> markImported(String itemId) async {
    try {
      await _ds.markImported(itemId);
    } catch (_) {}
  }

  /// Permanently removes one item from the backlog.
  Future<void> dismiss(String itemId) async {
    try {
      await _ds.deleteItem(itemId);
    } catch (_) {}
  }

  /// Removes all pending (non-imported) items for this user.
  Future<void> dismissAllPending() async {
    if (_userId.isEmpty) return;
    state = const AsyncValue.loading();
    try {
      await _ds.deleteAllPending(_userId);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

final backlogNotifierProvider =
    StateNotifierProvider<BacklogNotifier, AsyncValue<void>>((ref) {
  // Also use the real UID here, not effectiveUserId, for the same reason.
  final userId = ref.watch(authStateProvider).value?.id ?? '';
  return BacklogNotifier(ref.watch(backlogDatasourceProvider), userId);
});
