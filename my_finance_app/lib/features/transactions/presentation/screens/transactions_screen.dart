import 'dart:math' as math;

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

// Pie-chart slice colours (8 distinct)
const _kPieColors = [
  Color(0xFF2196F3),
  Color(0xFFF44336),
  Color(0xFF4CAF50),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFF00BCD4),
  Color(0xFFFFEB3B),
  Color(0xFF795548),
];

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fmt = ref.watch(currencyFormatterProvider);
    final dateLoc = ref.watch(dateLocaleProvider);
    final selectedMonth = ref.watch(transactionsSelectedMonthProvider);
    final isAnnual = ref.watch(statementIsAnnualProvider);

    final income = isAnnual
        ? ref.watch(statementAnnualIncomeProvider)
        : ref.watch(statementMonthIncomeProvider);
    final expense = isAnnual
        ? ref.watch(statementAnnualExpenseProvider)
        : ref.watch(statementMonthExpenseProvider);
    final balance = income - expense;
    final txs = isAnnual
        ? ref.watch(statementAnnualTransactionsProvider)
        : ref.watch(statementMonthTransactionsProvider);

    // Label: full year in annual mode, month+year in monthly mode
    final periodLabel = isAnnual
        ? selectedMonth.year.toString()
        : DateFormat('MMMM yyyy', dateLoc).format(selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navStatement),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: isAnnual ? l10n.monthlyView : l10n.annualView,
            icon: Icon(isAnnual
                ? Icons.calendar_view_day_outlined
                : Icons.calendar_month_outlined),
            onPressed: () {
              // Tentando ativar a visão anual — recurso Pro
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
              ref.read(statementIsAnnualProvider.notifier).state = !isAnnual;
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Month / Year selector ─────────────────────────────────────────
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

          // ── Summary card ──────────────────────────────────────────────────
          _SummaryCard(
            balance: balance,
            income: income,
            expense: expense,
            fmt: fmt,
          ),

          // ── Transaction list + pie chart ──────────────────────────────────
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
                    itemCount: txs.length + 1, // +1 for pie chart footer
                    itemBuilder: (ctx, i) {
                      if (i < txs.length) {
                        return TransactionListTile(transaction: txs[i]);
                      }
                      // Pie chart footer
                      final expenses = txs
                          .where((t) => t.type == TransactionType.expense)
                          .toList();
                      if (expenses.isEmpty) return const SizedBox.shrink();
                      return _ExpensePieChart(
                          transactions: expenses, fmt: fmt);
                    },
                  ),
          ),
        ],
      ),
    );
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
class _SummaryCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isPositive = balance >= 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: l10n.expenses,
                    value: fmt(expense),
                    color: Colors.red.shade700,
                    icon: Icons.arrow_downward,
                  ),
                ),
              ],
            ),
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

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Expense Pie Chart ────────────────────────────────────────────────────────

class _ExpensePieChart extends StatelessWidget {
  final List<TransactionEntity> transactions;
  final String Function(double) fmt;

  const _ExpensePieChart({
    required this.transactions,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Aggregate by category
    final Map<String, double> byCategory = {};
    for (final t in transactions) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }

    // Sort descending so largest slice is first
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    if (total == 0) return const SizedBox.shrink();

    // Assign colours (cycle if more than 8 categories)
    final slices = entries.asMap().entries.map((entry) {
      final idx = entry.key;
      final e = entry.value;
      return _PieSlice(
        category: e.key,
        amount: e.value,
        percentage: e.value / total,
        color: _kPieColors[idx % _kPieColors.length],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          Text(
            l10n.expenseByCategory,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 16),
          // Pie
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: _PieChartPainter(slices: slices),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: slices.map((s) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${s.category} · ${(s.percentage * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PieSlice {
  final String category;
  final double amount;
  final double percentage;
  final Color color;

  const _PieSlice({
    required this.category,
    required this.amount,
    required this.percentage,
    required this.color,
  });
}

class _PieChartPainter extends CustomPainter {
  final List<_PieSlice> slices;

  const _PieChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const gapAngle = 0.025; // radians gap between slices

    double startAngle = -math.pi / 2; // start at top

    for (final slice in slices) {
      final sweepAngle = slice.percentage * 2 * math.pi - gapAngle;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.fill;

      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += slice.percentage * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter oldDelegate) =>
      oldDelegate.slices != slices;
}
