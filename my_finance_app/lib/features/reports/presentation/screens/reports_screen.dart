import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';

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

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fmt = ref.watch(currencyFormatterProvider);
    final dateLoc = ref.watch(dateLocaleProvider);
    final selectedMonth = ref.watch(transactionsSelectedMonthProvider);
    final txs = ref.watch(statementMonthTransactionsProvider);

    final periodLabel = DateFormat('MMMM yyyy', dateLoc).format(selectedMonth);
    final expenses =
        txs.where((t) => t.type == TransactionType.expense).toList();

    final isCurrentMonth = selectedMonth.year == DateTime.now().year &&
        selectedMonth.month == DateTime.now().month;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navReports),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // ── Period selector ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => ref
                      .read(transactionsSelectedMonthProvider.notifier)
                      .state = DateTime(
                      selectedMonth.year, selectedMonth.month - 1, 1),
                ),
                Text(
                  periodLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isCurrentMonth
                      ? null
                      : () => ref
                          .read(transactionsSelectedMonthProvider.notifier)
                          .state = DateTime(
                          selectedMonth.year, selectedMonth.month + 1, 1),
                ),
              ],
            ),
          ),

          // ── Chart area ────────────────────────────────────────────────────
          Expanded(
            child: expenses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pie_chart_outline,
                          size: 56,
                          color:
                              Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noTransactions,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: _ExpensePieChart(
                        transactions: expenses, fmt: fmt),
                  ),
          ),
        ],
      ),
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

    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    if (total == 0) return const SizedBox.shrink();

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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.expenseByCategory,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 16),
          // Pie chart
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: CustomPaint(
                painter: _PieChartPainter(slices: slices),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Legend with amounts
          ...slices.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.category,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    '${(s.percentage * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    fmt(s.amount),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
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
    const gapAngle = 0.025;

    double startAngle = -math.pi / 2;
    for (final slice in slices) {
      final sweepAngle = slice.percentage * 2 * math.pi - gapAngle;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.fill,
      );
      startAngle += slice.percentage * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter oldDelegate) =>
      oldDelegate.slices != slices;
}
