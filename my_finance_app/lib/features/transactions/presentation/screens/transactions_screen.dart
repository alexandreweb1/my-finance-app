import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';
import '../../../subscription/presentation/widgets/pro_gate_widget.dart';
import '../../domain/entities/transaction_entity.dart';
import '../providers/transactions_provider.dart';
import '../widgets/transaction_list_tile.dart';

// Number of months to show in the quick picker
const _kPickerMonths = 24;

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fmt = ref.watch(currencyFormatterProvider);
    final dateLoc = ref.watch(dateLocaleProvider);
    final selectedMonth = ref.watch(transactionsSelectedMonthProvider);
    final isAnnual = ref.watch(statementIsAnnualProvider);
    final dateRange = ref.watch(statementDateRangeProvider);

    final income = ref.watch(statementDisplayIncomeProvider);
    final expense = ref.watch(statementDisplayExpenseProvider);
    final balance = income - expense;
    final txs = ref.watch(statementDisplayTransactionsProvider);

    // Label: full year in annual mode, month+year in monthly mode
    final periodLabel = isAnnual
        ? selectedMonth.year.toString()
        : DateFormat('MMMM yyyy', dateLoc).format(selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navStatement),
        centerTitle: false,
        actions: [
          // ── Date range picker (PRO) ─────────────────────────────────────
          IconButton(
            tooltip: l10n.customPeriod,
            icon: Icon(
              Icons.date_range_rounded,
              color: dateRange != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => _showDateRangePicker(context, ref),
          ),
          // ── Annual / monthly toggle ─────────────────────────────────────
          IconButton(
            tooltip: isAnnual ? l10n.monthlyView : l10n.annualView,
            icon: Icon(isAnnual
                ? Icons.calendar_view_day_outlined
                : Icons.calendar_month_outlined),
            // Disabled when a custom date range is active
            onPressed: dateRange != null
                ? null
                : () {
                    if (!isAnnual && !ref.read(isProProvider)) {
                      showProGateBottomSheet(
                        context,
                        featureName: 'Visão Anual',
                        featureDescription:
                            'Analise todas as suas transações do ano de uma vez.',
                        featureIcon: Icons.calendar_month_rounded,
                      );
                      return;
                    }
                    ref.read(statementIsAnnualProvider.notifier).state =
                        !isAnnual;
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Period selector OR active date-range chip ───────────────────
          if (dateRange != null)
            _DateRangeBar(dateRange: dateRange, dateLoc: dateLoc)
          else
            _PeriodSelector(
              label: periodLabel,
              isAnnual: isAnnual,
              month: selectedMonth,
              dateLoc: dateLoc,
              onPrev: () => ref
                  .read(transactionsSelectedMonthProvider.notifier)
                  .state = DateTime(
                      selectedMonth.year, selectedMonth.month - 1, 1),
              onNext: () => ref
                  .read(transactionsSelectedMonthProvider.notifier)
                  .state = DateTime(
                      selectedMonth.year, selectedMonth.month + 1, 1),
              onPickMonth: () => _showMonthPicker(context, ref, dateLoc),
            ),

          // ── Summary card (income/expense tappable to filter) ───────────
          _SummaryCard(
            balance: balance,
            income: income,
            expense: expense,
            fmt: fmt,
          ),

          // ── Transaction list ───────────────────────────────────────────
          Expanded(
            child: txs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noTransactions,
                          style:
                              TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: txs.length,
                    itemBuilder: (ctx, i) =>
                        TransactionListTile(transaction: txs[i]),
                  ),
          ),
        ],
      ),
    );
  }

  void _showDateRangePicker(BuildContext context, WidgetRef ref) {
    if (!ref.read(isProProvider)) {
      showProGateBottomSheet(
        context,
        featureName: 'Período Personalizado',
        featureDescription:
            'Filtre suas transações por qualquer intervalo de datas.',
        featureIcon: Icons.date_range_rounded,
      );
      return;
    }

    final current = ref.read(statementDateRangeProvider);
    showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: current != null
          ? DateTimeRange(start: current.$1, end: current.$2)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context),
        child: child!,
      ),
    ).then((picked) {
      if (picked != null) {
        ref.read(statementDateRangeProvider.notifier).state =
            (picked.start, picked.end);
      }
    });
  }

  void _showMonthPicker(
      BuildContext context, WidgetRef ref, String dateLoc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MonthPickerSheet(dateLoc: dateLoc),
    );
  }
}

// ─── Active Date Range Bar ─────────────────────────────────────────────────────
class _DateRangeBar extends ConsumerWidget {
  final (DateTime, DateTime) dateRange;
  final String dateLoc;

  const _DateRangeBar({required this.dateRange, required this.dateLoc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (start, end) = dateRange;
    final fmt = DateFormat('d MMM yy', dateLoc);
    final label = '${fmt.format(start)} – ${fmt.format(end)}';
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.date_range_rounded,
              size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () =>
                ref.read(statementDateRangeProvider.notifier).state = null,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Limpar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─── Period Selector Bar ──────────────────────────────────────────────────────
class _PeriodSelector extends ConsumerWidget {
  final String label;
  final bool isAnnual;
  final DateTime month;
  final String dateLoc;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickMonth;

  const _PeriodSelector({
    required this.label,
    required this.isAnnual,
    required this.month,
    required this.dateLoc,
    required this.onPrev,
    required this.onNext,
    required this.onPickMonth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isAnnual) {
      // Annual mode: single row with year navigation
      final isCurrentYear = month.year == DateTime.now().year;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => ref
                  .read(transactionsSelectedMonthProvider.notifier)
                  .state = DateTime(month.year - 1, month.month, 1),
            ),
            SizedBox(
              width: 72,
              child: Center(
                child: Text(
                  month.year.toString(),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: isCurrentYear ? null : () => ref
                  .read(transactionsSelectedMonthProvider.notifier)
                  .state = DateTime(month.year + 1, month.month, 1),
            ),
          ],
        ),
      );
    }

    // Monthly mode: prev / tap-to-pick / next
    final isCurrentMonth = month.year == DateTime.now().year &&
        month.month == DateTime.now().month;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          InkWell(
            onTap: onPickMonth,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth ? null : onNext,
          ),
        ],
      ),
    );
  }
}

// ─── Month Picker Bottom Sheet ────────────────────────────────────────────────
class _MonthPickerSheet extends ConsumerWidget {
  final String dateLoc;

  const _MonthPickerSheet({required this.dateLoc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedMonth = ref.watch(transactionsSelectedMonthProvider);
    final now = DateTime.now();

    // Build list of months newest → oldest
    final months = List.generate(_kPickerMonths, (i) {
      return DateTime(now.year, now.month - i, 1);
    });

    // Group by year
    final Map<int, List<DateTime>> byYear = {};
    for (final m in months) {
      byYear.putIfAbsent(m.year, () => []).add(m);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  l10n.selectMonth,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Month grid scrollable
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: years.map((year) {
                final yearMonths = byYear[year]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        year.toString(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.6,
                      children: yearMonths.map((month) {
                        final isSelected =
                            month.year == selectedMonth.year &&
                                month.month == selectedMonth.month;
                        final isFuture = month.isAfter(DateTime(
                            now.year, now.month, now.day));
                        final label =
                            DateFormat('MMM', dateLoc).format(month);

                        return _MonthChip(
                          label: label,
                          isSelected: isSelected,
                          isFuture: isFuture,
                          onTap: isFuture
                              ? null
                              : () {
                                  ref
                                      .read(
                                          transactionsSelectedMonthProvider
                                              .notifier)
                                      .state = month;
                                  Navigator.of(context).pop();
                                },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 4),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isFuture;
  final VoidCallback? onTap;

  const _MonthChip({
    required this.label,
    required this.isSelected,
    required this.isFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primary
          : isFuture
              ? colorScheme.surfaceContainer
              : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? colorScheme.onPrimary
                  : isFuture
                      ? Colors.grey.shade400
                      : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────
class _SummaryCard extends ConsumerWidget {
  final double balance;
  final double income;
  final double expense;
  final String Function(double) fmt;

  const _SummaryCard({
    required this.balance,
    required this.income,
    required this.expense,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isPositive = balance >= 0;
    final typeFilter = ref.watch(statementTypeFilterProvider);

    void toggleFilter(TransactionType type) {
      ref.read(statementTypeFilterProvider.notifier).state =
          typeFilter == type ? null : type;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(l10n.totalBalance,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              fmt(balance),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isPositive
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: l10n.income,
                    value: fmt(income),
                    color: Colors.green.shade700,
                    icon: Icons.arrow_upward,
                    isActive: typeFilter == TransactionType.income,
                    onTap: () => toggleFilter(TransactionType.income),
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: l10n.expenses,
                    value: fmt(expense),
                    color: Colors.red.shade700,
                    icon: Icons.arrow_downward,
                    isActive: typeFilter == TransactionType.expense,
                    onTap: () => toggleFilter(TransactionType.expense),
                  ),
                ),
              ],
            ),
            // Active filter hint
            if (typeFilter != null) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.filter_list_rounded,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    typeFilter == TransactionType.income
                        ? 'Mostrando apenas receitas · toque para limpar'
                        : 'Mostrando apenas despesas · toque para limpar',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isActive;
  final VoidCallback? onTap;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: isActive
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: color.withValues(alpha: 0.1),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              )
            : const BoxDecoration(),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600)),
                Text(
                  value,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
