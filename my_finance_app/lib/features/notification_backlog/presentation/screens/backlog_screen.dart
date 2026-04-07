import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/notification_providers.dart';
import '../../../../core/utils/animated_dialog.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/widgets/add_transaction_dialog.dart';
import '../../domain/entities/notification_backlog_item_entity.dart';
import '../providers/backlog_provider.dart';

class BacklogScreen extends ConsumerWidget {
  const BacklogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(backlogItemsStreamProvider);
    final pendingCount = ref.watch(unimportedBacklogCountProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações Bancárias'),
        centerTitle: false,
        actions: [
          if (pendingCount > 0)
            TextButton(
              onPressed: () => _confirmDismissAll(context, ref),
              child: const Text('Limpar pendentes'),
            ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyState();
          }

          // Non-imported first, then imported; within each group, newest first.
          final pending = items.where((i) => !i.imported).toList();
          final imported = items.where((i) => i.imported).toList();
          final sorted = [...pending, ...imported];

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: sorted.length + (imported.isNotEmpty ? 1 : 0),
            itemBuilder: (ctx, index) {
              // Section header between pending and imported
              if (pending.isNotEmpty &&
                  imported.isNotEmpty &&
                  index == pending.length) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(
                    'Já importados',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                );
              }

              final itemIndex =
                  (pending.isNotEmpty && imported.isNotEmpty && index > pending.length)
                      ? index - 1
                      : index;

              final item = sorted[itemIndex];
              return _BacklogItemCard(item: item, key: ValueKey(item.id));
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDismissAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar pendentes'),
        content: const Text(
          'Remove todas as notificações não importadas. '
          'Itens já importados não serão afetados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(backlogNotifierProvider.notifier).dismissAllPending();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual item card
// ─────────────────────────────────────────────────────────────────────────────

class _BacklogItemCard extends ConsumerWidget {
  final NotificationBacklogItemEntity item;

  const _BacklogItemCard({required this.item, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final fmt = ref.watch(currencyFormatterProvider);

    final isExpense = item.type == TransactionType.expense;
    final isIncome = item.type == TransactionType.income;
    final amountColor = isExpense
        ? const Color(0xFFE05252)
        : isIncome
            ? const Color(0xFF00D887)
            : cs.onSurface;

    final bankName = _bankDisplayName(item.sourceApp);
    final preview = item.rawText.trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: item.imported
              ? cs.outlineVariant.withValues(alpha: 0.3)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      color: item.imported ? cs.surfaceContainerLow : cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: bank chip + type badge + timestamp ──
            Row(
              children: [
                _Chip(
                  label: bankName,
                  color: cs.primaryContainer,
                  textColor: cs.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                if (item.type != null)
                  _Chip(
                    label: isIncome ? '↓ Receita' : '↑ Despesa',
                    color: isIncome
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.12),
                    textColor: isIncome
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                const Spacer(),
                Text(
                  _timeAgo(item.receivedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Row 2: amount ──
            Text(
              fmt(item.amount),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),

            // ── Row 3: raw text preview ──
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Row 4: actions ──
            if (!item.imported)
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(backlogNotifierProvider.notifier).dismiss(item.id),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Ignorar'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _import(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Importar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Importado',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        ref.read(backlogNotifierProvider.notifier).dismiss(item.id),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                    child: const Text('Remover'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    // Mark as imported immediately so the UI updates; user can still cancel the dialog.
    await ref.read(backlogNotifierProvider.notifier).markImported(item.id);
    if (!context.mounted) return;
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => AddTransactionDialog(
        initialAmount: item.amount,
        initialType: item.type,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma notificação bancária',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'As notificações dos bancos monitorados\naparecerão aqui para você revisar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Utilities ─────────────────────────────────────────────────────────────────

/// Returns the user-friendly display name for a bank package name.
String _bankDisplayName(String packageName) {
  for (final bank in kKnownBanks) {
    if (packageName.startsWith(bank.packageName)) return bank.displayName;
  }
  // Fallback: prettify the package name.
  final parts = packageName.split('.');
  return parts.isNotEmpty ? parts.last : packageName;
}

/// Returns a compact human-readable relative timestamp.
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays == 1) return 'ontem';
  if (diff.inDays < 7) return 'há ${diff.inDays} dias';
  final d = dt;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
