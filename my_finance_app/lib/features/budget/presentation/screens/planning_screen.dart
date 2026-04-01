import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/selected_month_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/providers/categories_provider.dart';
import '../../../../core/utils/money_input_formatter.dart';
import '../../../goals/presentation/screens/goals_screen.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../domain/entities/budget_entity.dart';
import '../providers/budget_provider.dart';

class PlanningScreen extends ConsumerWidget {
  const PlanningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final summaries = ref.watch(budgetSummaryProvider);
    final budgetsAsync = ref.watch(budgetsStreamProvider);

    final sortedSummaries = [...summaries]
      ..sort((a, b) =>
          a.budget.categoryName.compareTo(b.budget.categoryName));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.planning),
          centerTitle: false,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Orçamentos'),
              Tab(text: 'Metas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ── Orçamentos tab ─────────────────────────────────────
            Column(
              children: [
                _MonthSelector(month: selectedMonth),
                Expanded(
                  child: budgetsAsync.when(
                    data: (_) => sortedSummaries.isEmpty
                        ? _EmptyBudgets(month: selectedMonth)
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: sortedSummaries.length + 2,
                            itemBuilder: (ctx, i) {
                              if (i == 0) {
                                return _BudgetSummaryCard(
                                    summaries: sortedSummaries);
                              }
                              if (i == sortedSummaries.length + 1) {
                                return _AddBudgetButton(month: selectedMonth);
                              }
                              return _BudgetCard(
                                  summary: sortedSummaries[i - 1]);
                            },
                          ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Erro: $e')),
                  ),
                ),
              ],
            ),
            // ── Metas tab ──────────────────────────────────────────
            const GoalsScreen(),
          ],
        ),
      ),
    );
  }
}

class _MonthSelector extends ConsumerWidget {
  final DateTime month;

  const _MonthSelector({required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLoc = ref.watch(dateLocaleProvider);
    final label = DateFormat('MMMM yyyy', dateLoc).format(month).capitalizeMonth();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                DateTime(month.year, month.month - 1, 1),
          ),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                DateTime(month.year, month.month + 1, 1),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Budget Summary Card (totals header)
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetSummaryCard extends ConsumerWidget {
  final List<BudgetSummary> summaries;

  const _BudgetSummaryCard({required this.summaries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(currencyFormatterProvider);
    final l10n = AppLocalizations.of(context);

    final totalPlanned =
        summaries.fold(0.0, (sum, s) => sum + s.budget.limitAmount);
    final totalSpent = summaries.fold(0.0, (sum, s) => sum + s.spentAmount);
    final remaining = totalPlanned - totalSpent;
    final isOver = totalSpent > totalPlanned;

    final progress =
        totalPlanned > 0 ? (totalSpent / totalPlanned).clamp(0.0, 1.0) : 0.0;
    final progressColor =
        isOver ? Colors.red.shade600 : Colors.green.shade600;

    final cs = Theme.of(context).colorScheme;
    final pct = (progress * 100).toStringAsFixed(0);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primaryContainer.withValues(alpha: 0.35),
              cs.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          children: [
            // ── Título centralizado ──
            Text(
              l10n.budgetSummaryTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: cs.onSurface,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 14),
            // ── Barra de progresso + % ──
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: progressColor,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: progressColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Três colunas com divisores ──
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryColumn(
                      icon: Icons.account_balance_wallet_outlined,
                      label: l10n.budgetPlanned,
                      value: fmt(totalPlanned),
                    ),
                  ),
                  VerticalDivider(
                      color: cs.outlineVariant, width: 1, thickness: 1),
                  Expanded(
                    child: _SummaryColumn(
                      icon: Icons.shopping_cart_outlined,
                      label: l10n.spent,
                      value: fmt(totalSpent),
                      valueColor: progressColor,
                    ),
                  ),
                  VerticalDivider(
                      color: cs.outlineVariant, width: 1, thickness: 1),
                  Expanded(
                    child: _SummaryColumn(
                      icon: isOver
                          ? Icons.warning_amber_rounded
                          : Icons.savings_outlined,
                      label: isOver
                          ? l10n.budgetExceeded
                          : l10n.budgetRemaining,
                      value: fmt(remaining.abs()),
                      valueColor: isOver ? Colors.red.shade600 : Colors.green.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryColumn({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: valueColor ?? cs.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Budget Card (individual row)
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetCard extends ConsumerWidget {
  final BudgetSummary summary;

  const _BudgetCard({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fmt = ref.watch(currencyFormatterProvider);
    final budget = summary.budget;
    final colorScheme = Theme.of(context).colorScheme;
    final progressColor = summary.isOverBudget
        ? Colors.red.shade600
        : Colors.green.shade600;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.categoryName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 17),
                  ),
                ),
                Text(
                  '${summary.percentage.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: progressColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      color: colorScheme.primary, size: 20),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _AddBudgetDialog(
                      month: budget.month,
                      budget: budget,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: colorScheme.error, size: 20),
                  onPressed: () =>
                      ref.read(budgetNotifierProvider.notifier).delete(budget.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: summary.progress,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              color: progressColor,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${l10n.spent}: ${fmt(summary.spentAmount)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  '${l10n.budgetRemaining}: ${fmt(summary.remaining.abs())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: summary.isOverBudget
                        ? Colors.red.shade600
                        : Colors.green.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${l10n.limitLabel}: ${fmt(budget.limitAmount)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBudgets extends ConsumerWidget {
  final DateTime month;

  const _EmptyBudgets({required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final dateLoc = ref.watch(dateLocaleProvider);
    final isLoading = ref.watch(budgetNotifierProvider).isLoading;
    final currentMonthLabel = DateFormat('MMMM yyyy', dateLoc).format(month).capitalizeMonth();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            '${l10n.noBudgetsForMonth}\n$currentMonthLabel',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.post_add_outlined, size: 18),
            label: Text(l10n.createBudgets),
            onPressed: isLoading
                ? null
                : () => _showCopyOptionsDialog(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showCopyOptionsDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final dateLoc = ref.read(dateLocaleProvider);
    final currentMonthLabel = DateFormat('MMMM yyyy', dateLoc).format(month).capitalizeMonth();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l10n.createBudgetsFor} $currentMonthLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BudgetOptionTile(
              icon: Icons.copy_outlined,
              title: l10n.copyPrevLimits,
              subtitle: l10n.copyPrevLimitsDesc,
              onTap: () => Navigator.of(ctx).pop('copy'),
            ),
            const SizedBox(height: 8),
            _BudgetOptionTile(
              icon: Icons.insights_outlined,
              title: l10n.baseOnSpending,
              subtitle: l10n.baseOnSpendingDesc,
              onTap: () => Navigator.of(ctx).pop('spending'),
            ),
            const SizedBox(height: 8),
            _BudgetOptionTile(
              icon: Icons.add_circle_outline,
              title: l10n.createManually,
              subtitle: l10n.createManuallyDesc,
              onTap: () => Navigator.of(ctx).pop('manual'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    if (choice == null || !context.mounted) return;

    if (choice == 'manual') {
      await showDialog(
        context: context,
        builder: (_) => _AddBudgetDialog(month: month),
      );
      return;
    }

    // Ask the user which month to use as reference
    final sourceMonth = await _pickSourceMonth(context, ref);
    if (sourceMonth == null || !context.mounted) return;

    if (choice == 'copy') {
      // Fetch budgets for the chosen source month
      final budgets =
          await ref.read(budgetsForMonthProvider(sourceMonth).future);
      if (!context.mounted) return;
      if (budgets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorReplicating)),
        );
        return;
      }
      final success = await ref
          .read(budgetNotifierProvider.notifier)
          .copyFromPreviousMonth(
            previousBudgets: budgets,
            targetMonth: month,
          );
      if (!context.mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorReplicating)),
        );
      }
    } else {
      // Build budgets from expense categories with spending in the chosen month
      final allTransactions = ref.read(visibleTransactionsProvider);
      final expenseCategories = ref.read(expenseCategoriesProvider);
      final spending = <String, double>{};
      for (final t in allTransactions) {
        if (t.isExpense &&
            t.date.year == sourceMonth.year &&
            t.date.month == sourceMonth.month) {
          spending[t.category] = (spending[t.category] ?? 0.0) + t.amount;
        }
      }
      final categoryByName = {for (final c in expenseCategories) c.name: c};
      final spendingBudgets = spending.entries
          .map((entry) {
            final category = categoryByName[entry.key];
            if (category == null) return null;
            return BudgetEntity(
              id: '',
              userId: '',
              categoryId: category.id,
              categoryName: category.name,
              limitAmount: entry.value,
              month: month,
            );
          })
          .whereType<BudgetEntity>()
          .toList();
      if (spendingBudgets.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorReplicating)),
          );
        }
        return;
      }
      final success = await ref
          .read(budgetNotifierProvider.notifier)
          .copyFromPreviousMonth(
            previousBudgets: spendingBudgets,
            targetMonth: month,
          );
      if (!context.mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorReplicating)),
        );
      }
    }
  }

  Future<DateTime?> _pickSourceMonth(
      BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final dateLoc = ref.read(dateLocaleProvider);

    // Default: previous month relative to target
    final prevMonth = DateTime(month.year, month.month - 1, 1);
    int selectedMonth = prevMonth.month;
    int selectedYear = prevMonth.year;

    // Year range: 5 years back from current target month year
    final years =
        List.generate(6, (i) => month.year - i);
    final monthNames = List.generate(
      12,
      (i) => DateFormat('MMMM', dateLoc).format(DateTime(2000, i + 1)).capitalizeMonth(),
    );

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.selectSourceMonth),
          content: Row(
            children: [
              // Month dropdown
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  initialValue: selectedMonth,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(monthNames[i]),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) setState(() => selectedMonth = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Year dropdown
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: selectedYear,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: years
                      .map((y) => DropdownMenuItem(
                            value: y,
                            child: Text(y.toString()),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => selectedYear = v);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx)
                  .pop(DateTime(selectedYear, selectedMonth, 1)),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit Budget Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddBudgetDialog extends ConsumerStatefulWidget {
  final DateTime month;

  /// When provided the dialog opens in edit mode pre-filled with this budget.
  final BudgetEntity? budget;

  const _AddBudgetDialog({required this.month, this.budget});

  @override
  ConsumerState<_AddBudgetDialog> createState() => _AddBudgetDialogState();
}

class _AddBudgetDialogState extends ConsumerState<_AddBudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  CategoryEntity? _selectedCategory;

  bool get _isEditing => widget.budget != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _amountController.text = doubleToMoneyText(widget.budget!.limitAmount);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l10n.deleteBudget),
          content: Text(l10n.deleteBudgetConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final success =
        await ref.read(budgetNotifierProvider.notifier).delete(widget.budget!.id);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.selectCategory)),
      );
      return;
    }
    final amount = moneyTextToDouble(_amountController.text);
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.invalidAmount)),
      );
      return;
    }

    final notifier = ref.read(budgetNotifierProvider.notifier);
    bool success;

    if (_isEditing &&
        _selectedCategory!.id != widget.budget!.categoryId) {
      // Category changed — delete old budget then create new one.
      await notifier.delete(widget.budget!.id);
      success = await notifier.set(
        categoryId: _selectedCategory!.id,
        categoryName: _selectedCategory!.name,
        limitAmount: amount,
        month: widget.month,
      );
    } else {
      // Create or update (upsert by categoryId+month key).
      success = await notifier.set(
        categoryId: _selectedCategory!.id,
        categoryName: _selectedCategory!.name,
        limitAmount: amount,
        month: widget.month,
      );
    }

    if (!mounted) return;
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateLoc = ref.watch(dateLocaleProvider);
    final expenseCategories = ref.watch(expenseCategoriesProvider);
    final isLoading = ref.watch(budgetNotifierProvider).isLoading;

    // Pre-select the matching category when editing.
    if (_isEditing && _selectedCategory == null && expenseCategories.isNotEmpty) {
      _selectedCategory = expenseCategories.firstWhere(
        (c) => c.id == widget.budget!.categoryId,
        orElse: () => expenseCategories.first,
      );
    }

    final title = _isEditing
        ? l10n.editBudget
        : '${l10n.newBudget}${DateFormat('MMM yyyy', dateLoc).format(widget.month).capitalizeMonth()}';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<CategoryEntity>(
                key: ValueKey(_selectedCategory?.id),
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: l10n.categoryField,
                  border: const OutlineInputBorder(),
                ),
                items: expenseCategories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                validator: (v) =>
                    v == null ? l10n.selectCategory : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
                decoration: InputDecoration(
                  labelText: l10n.limit,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.enterAmount;
                  if (moneyTextToDouble(v) <= 0) return l10n.invalidAmount;
                  return null;
                },
              ),
              if (_isEditing) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                        color: Theme.of(context).colorScheme.error),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(AppLocalizations.of(context).deleteBudget),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Option tile used inside the copy/spending choice dialog
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BudgetOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 26, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-budget button rendered at the bottom of the budget list
// ─────────────────────────────────────────────────────────────────────────────

class _AddBudgetButton extends StatelessWidget {
  final DateTime month;

  const _AddBudgetButton({required this.month});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: OutlinedButton.icon(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _AddBudgetDialog(month: month),
        ),
        icon: const Icon(Icons.add),
        label: Text(l10n.budget),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }
}
