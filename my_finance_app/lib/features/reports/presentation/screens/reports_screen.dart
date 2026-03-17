import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../../wallets/presentation/providers/wallets_provider.dart';

// ─── Colour palette ────────────────────────────────────────────────────────────
const _kChartColors = [
  Color(0xFF6366F1),
  Color(0xFFEC4899),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF3B82F6),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFFF97316),
];

const _kIncomeColor = Color(0xFF10B981);
const _kExpenseColor = Color(0xFFEF4444);
const _kLineColor = Color(0xFF00BCD4);

// ─── Screen ────────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _mainTab = 0; // 0=pie  1=line  2=bar
  int _pieSubTab = 0; // 0=expense/cat  1=expense/wallet  2=income/cat
  int _lineSubTab = 1; // 0=semana  1=mês  2=ano
  int _barSubTab = 0; // 0=balanço mensal  1=fluxo anual  2=dia semana

  // Bar "Balanço mensal" window end (shows 3 months ending here)
  late DateTime _barPeriodEnd;
  // Line "week" view window start
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _barPeriodEnd = DateTime(now.year, now.month, 1);
    _weekStart = _computeWeekStart(now);
  }

  static DateTime _computeWeekStart(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fmt = ref.watch(currencyFormatterProvider);
    final dateLoc = ref.watch(dateLocaleProvider);
    final allTxs = ref.watch(visibleTransactionsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── AppBar ──────────────────────────────────────────────────────
          SliverAppBar(
            title: Text(l10n.navReports),
            centerTitle: false,
            pinned: true,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: colorScheme.surfaceTint,
          ),

          // ── Top icon tab bar ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _IconTab(
                      icon: Icons.donut_large_rounded,
                      label: 'Categorias',
                      isSelected: _mainTab == 0,
                      onTap: () => setState(() => _mainTab = 0),
                    ),
                    _IconTab(
                      icon: Icons.show_chart_rounded,
                      label: 'Evolução',
                      isSelected: _mainTab == 1,
                      onTap: () => setState(() => _mainTab = 1),
                    ),
                    _IconTab(
                      icon: Icons.bar_chart_rounded,
                      label: 'Comparar',
                      isSelected: _mainTab == 2,
                      onTap: () => setState(() => _mainTab = 2),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Tab content ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _buildTabContent(context, allTxs, fmt, dateLoc, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    List<TransactionEntity> allTxs,
    String Function(double) fmt,
    String dateLoc,
    ColorScheme cs,
  ) {
    switch (_mainTab) {
      case 0:
        return _buildPieTab(context, allTxs, fmt, dateLoc, cs);
      case 1:
        return _buildLineTab(context, allTxs, fmt, dateLoc, cs);
      case 2:
        return _buildBarTab(context, allTxs, fmt, dateLoc, cs);
      default:
        return const SizedBox.shrink();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PIE TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPieTab(
    BuildContext context,
    List<TransactionEntity> allTxs,
    String Function(double) fmt,
    String dateLoc,
    ColorScheme cs,
  ) {
    final selectedMonth = ref.watch(transactionsSelectedMonthProvider);
    final isCurrentMonth = selectedMonth.year == DateTime.now().year &&
        selectedMonth.month == DateTime.now().month;
    final monthTxs = allTxs
        .where((t) =>
            t.date.year == selectedMonth.year &&
            t.date.month == selectedMonth.month)
        .toList();
    final periodLabel =
        DateFormat('MMMM yyyy', dateLoc).format(selectedMonth).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubTabsRow(
          ['Despesas por categoria', 'Despesas por conta', 'Receitas por categoria'],
          _pieSubTab,
          (i) => setState(() => _pieSubTab = i),
        ),
        _buildPeriodNav(
          label: periodLabel,
          onPrev: () => ref
              .read(transactionsSelectedMonthProvider.notifier)
              .state = DateTime(selectedMonth.year, selectedMonth.month - 1, 1),
          onNext: isCurrentMonth
              ? null
              : () => ref
                  .read(transactionsSelectedMonthProvider.notifier)
                  .state =
                  DateTime(selectedMonth.year, selectedMonth.month + 1, 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          child: _buildPieChartContent(context, monthTxs, fmt),
        ),
      ],
    );
  }

  Widget _buildPieChartContent(
    BuildContext context,
    List<TransactionEntity> monthTxs,
    String Function(double) fmt,
  ) {
    final Map<String, double> byGroup = {};

    if (_pieSubTab == 0) {
      for (final t in monthTxs.where((t) => t.isExpense)) {
        byGroup[t.category] = (byGroup[t.category] ?? 0) + t.amount;
      }
    } else if (_pieSubTab == 1) {
      final wallets = ref.watch(walletsStreamProvider).value ?? [];
      final walletMap = {for (final w in wallets) w.id: w.name};
      for (final t in monthTxs.where((t) => t.isExpense)) {
        final name =
            t.walletId.isEmpty ? 'Geral' : (walletMap[t.walletId] ?? 'Geral');
        byGroup[name] = (byGroup[name] ?? 0) + t.amount;
      }
    } else {
      for (final t in monthTxs.where((t) => t.isIncome)) {
        byGroup[t.category] = (byGroup[t.category] ?? 0) + t.amount;
      }
    }

    final entries = byGroup.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);

    if (total == 0) {
      return _emptyState(context, Icons.pie_chart_outline);
    }

    final slices = entries.asMap().entries
        .map((e) => _PieSlice(
              category: e.value.key,
              amount: e.value.value,
              percentage: e.value.value / total,
              color: _kChartColors[e.key % _kChartColors.length],
            ))
        .toList();

    return _CategoryChart(slices: slices, fmt: fmt, total: total);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LINE TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildLineTab(
    BuildContext context,
    List<TransactionEntity> allTxs,
    String Function(double) fmt,
    String dateLoc,
    ColorScheme cs,
  ) {
    final selectedMonth = ref.watch(transactionsSelectedMonthProvider);
    final isCurrentMonth = selectedMonth.year == DateTime.now().year &&
        selectedMonth.month == DateTime.now().month;

    final now = DateTime.now();
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final isCurrentWeek = weekEnd.isAfter(now) ||
        (weekEnd.year == now.year &&
            weekEnd.month == now.month &&
            weekEnd.day == now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubTabsRow(
          ['Despesas da semana', 'Despesas do mês', 'Despesas por ano'],
          _lineSubTab,
          (i) => setState(() => _lineSubTab = i),
        ),
        if (_lineSubTab == 0)
          _buildPeriodNav(
            label: _weekRangeLabel(_weekStart, dateLoc),
            onPrev: () => setState(() =>
                _weekStart = _weekStart.subtract(const Duration(days: 7))),
            onNext: isCurrentWeek
                ? null
                : () => setState(() =>
                    _weekStart = _weekStart.add(const Duration(days: 7))),
          )
        else if (_lineSubTab == 1)
          _buildPeriodNav(
            label: DateFormat('MMMM yyyy', dateLoc)
                .format(selectedMonth)
                .toUpperCase(),
            onPrev: () => ref
                .read(transactionsSelectedMonthProvider.notifier)
                .state =
                DateTime(selectedMonth.year, selectedMonth.month - 1, 1),
            onNext: isCurrentMonth
                ? null
                : () => ref
                    .read(transactionsSelectedMonthProvider.notifier)
                    .state =
                    DateTime(selectedMonth.year, selectedMonth.month + 1, 1),
          )
        else
          _buildPeriodNav(
            label: selectedMonth.year.toString(),
            onPrev: () => ref
                .read(transactionsSelectedMonthProvider.notifier)
                .state = DateTime(selectedMonth.year - 1, selectedMonth.month, 1),
            onNext: selectedMonth.year >= DateTime.now().year
                ? null
                : () => ref
                    .read(transactionsSelectedMonthProvider.notifier)
                    .state =
                    DateTime(selectedMonth.year + 1, selectedMonth.month, 1),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          child: _buildLineChartContent(
              context, allTxs, fmt, dateLoc, selectedMonth, cs),
        ),
      ],
    );
  }

  Widget _buildLineChartContent(
    BuildContext context,
    List<TransactionEntity> allTxs,
    String Function(double) fmt,
    String dateLoc,
    DateTime selectedMonth,
    ColorScheme cs,
  ) {
    late List<_ChartPoint> points;

    if (_lineSubTab == 0) {
      // Week: 7 days
      points = List.generate(7, (i) {
        final day = _weekStart.add(Duration(days: i));
        final sum = allTxs
            .where((t) =>
                t.isExpense &&
                t.date.year == day.year &&
                t.date.month == day.month &&
                t.date.day == day.day)
            .fold<double>(0, (s, t) => s + t.amount);
        final label = DateFormat('E', dateLoc).format(day).toUpperCase();
        return _ChartPoint(label: label, value: sum);
      });
    } else if (_lineSubTab == 1) {
      // Month: day by day
      final daysInMonth =
          DateUtils.getDaysInMonth(selectedMonth.year, selectedMonth.month);
      points = List.generate(daysInMonth, (i) {
        final day = i + 1;
        final sum = allTxs
            .where((t) =>
                t.isExpense &&
                t.date.year == selectedMonth.year &&
                t.date.month == selectedMonth.month &&
                t.date.day == day)
            .fold<double>(0, (s, t) => s + t.amount);
        final showLabel = (i % 5 == 0 || i == daysInMonth - 1);
        final label = showLabel
            ? '${day.toString().padLeft(2, '0')} '
                '${DateFormat('MMM', dateLoc).format(selectedMonth).toUpperCase()}.'
            : '';
        return _ChartPoint(label: label, value: sum);
      });
    } else {
      // Year: 12 months
      points = List.generate(12, (i) {
        final month = i + 1;
        final sum = allTxs
            .where((t) =>
                t.isExpense &&
                t.date.year == selectedMonth.year &&
                t.date.month == month)
            .fold<double>(0, (s, t) => s + t.amount);
        final label = DateFormat('MMM', dateLoc)
            .format(DateTime(selectedMonth.year, month))
            .toUpperCase()
            .substring(0, 3);
        return _ChartPoint(label: label, value: sum);
      });
    }

    final total = points.fold<double>(0, (s, p) => s + p.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          child: _AreaChart(points: points, color: _kLineColor, fmt: fmt),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Total  ',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              fmt(total),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BAR TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildBarTab(
    BuildContext context,
    List<TransactionEntity> allTxs,
    String Function(double) fmt,
    String dateLoc,
    ColorScheme cs,
  ) {
    final selectedMonth = ref.watch(transactionsSelectedMonthProvider);
    final isCurrentMonth = selectedMonth.year == DateTime.now().year &&
        selectedMonth.month == DateTime.now().month;
    final isCurrentYear = selectedMonth.year == DateTime.now().year;

    // Can we advance the bar period further?
    final now = DateTime.now();
    final barCanGoNext = _barPeriodEnd.year < now.year ||
        (_barPeriodEnd.year == now.year && _barPeriodEnd.month < now.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubTabsRow(
          ['Balanço mensal', 'Fluxo de caixa anual', 'Despesas x dia semana'],
          _barSubTab,
          (i) => setState(() => _barSubTab = i),
        ),
        if (_barSubTab == 0)
          _buildPeriodNav(
            label: _monthRangeLabel(_barPeriodEnd, dateLoc),
            onPrev: () => setState(() => _barPeriodEnd =
                DateTime(_barPeriodEnd.year, _barPeriodEnd.month - 3, 1)),
            onNext: barCanGoNext
                ? () => setState(() => _barPeriodEnd =
                    DateTime(_barPeriodEnd.year, _barPeriodEnd.month + 3, 1))
                : null,
          )
        else if (_barSubTab == 1)
          _buildPeriodNav(
            label: selectedMonth.year.toString(),
            onPrev: () => ref
                .read(transactionsSelectedMonthProvider.notifier)
                .state =
                DateTime(selectedMonth.year - 1, selectedMonth.month, 1),
            onNext: isCurrentYear
                ? null
                : () => ref
                    .read(transactionsSelectedMonthProvider.notifier)
                    .state =
                    DateTime(selectedMonth.year + 1, selectedMonth.month, 1),
          )
        else
          _buildPeriodNav(
            label: DateFormat('MMMM yyyy', dateLoc)
                .format(selectedMonth)
                .toUpperCase(),
            onPrev: () => ref
                .read(transactionsSelectedMonthProvider.notifier)
                .state =
                DateTime(selectedMonth.year, selectedMonth.month - 1, 1),
            onNext: isCurrentMonth
                ? null
                : () => ref
                    .read(transactionsSelectedMonthProvider.notifier)
                    .state =
                    DateTime(selectedMonth.year, selectedMonth.month + 1, 1),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          child: _buildBarChartContent(
              context, allTxs, fmt, dateLoc, selectedMonth, cs),
        ),
      ],
    );
  }

  Widget _buildBarChartContent(
    BuildContext context,
    List<TransactionEntity> allTxs,
    String Function(double) fmt,
    String dateLoc,
    DateTime selectedMonth,
    ColorScheme cs,
  ) {
    if (_barSubTab == 0) {
      // Monthly balance: 3 months
      final months = List.generate(
          3, (i) => DateTime(_barPeriodEnd.year, _barPeriodEnd.month - 2 + i, 1));
      final groups = months.map((m) {
        final label =
            DateFormat('MMM. yyyy', dateLoc).format(m).toUpperCase();
        final income = allTxs
            .where((t) =>
                t.isIncome &&
                t.date.year == m.year &&
                t.date.month == m.month)
            .fold<double>(0, (s, t) => s + t.amount);
        final expense = allTxs
            .where((t) =>
                t.isExpense &&
                t.date.year == m.year &&
                t.date.month == m.month)
            .fold<double>(0, (s, t) => s + t.amount);
        return _BarGroup(label: label, values: [income, expense]);
      }).toList();

      return _BarChartWidget(
        groups: groups,
        colors: const [_kIncomeColor, _kExpenseColor],
        legendLabels: const ['Receitas', 'Despesas'],
        fmt: fmt,
      );
    } else if (_barSubTab == 1) {
      // Annual cashflow: 12 months
      final groups = List.generate(12, (i) {
        final month = i + 1;
        final m = DateTime(selectedMonth.year, month, 1);
        final label = DateFormat('MMM', dateLoc)
            .format(m)
            .toUpperCase()
            .substring(0, 3);
        final income = allTxs
            .where((t) =>
                t.isIncome &&
                t.date.year == selectedMonth.year &&
                t.date.month == month)
            .fold<double>(0, (s, t) => s + t.amount);
        final expense = allTxs
            .where((t) =>
                t.isExpense &&
                t.date.year == selectedMonth.year &&
                t.date.month == month)
            .fold<double>(0, (s, t) => s + t.amount);
        return _BarGroup(label: label, values: [income, expense]);
      });

      return _BarChartWidget(
        groups: groups,
        colors: const [_kIncomeColor, _kExpenseColor],
        legendLabels: const ['Receitas', 'Despesas'],
        fmt: fmt,
      );
    } else {
      // Weekday expenses
      const weekdayNames = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
      final monthExpenses = allTxs
          .where((t) =>
              t.isExpense &&
              t.date.year == selectedMonth.year &&
              t.date.month == selectedMonth.month)
          .toList();
      final groups = List.generate(7, (i) {
        final weekday = i + 1; // 1=Mon … 7=Sun
        final sum = monthExpenses
            .where((t) => t.date.weekday == weekday)
            .fold<double>(0, (s, t) => s + t.amount);
        return _BarGroup(label: weekdayNames[i], values: [sum]);
      });

      return _BarChartWidget(
        groups: groups,
        colors: const [_kExpenseColor],
        legendLabels: const ['Despesas'],
        fmt: fmt,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Shared helpers
  // ══════════════════════════════════════════════════════════════════════════

  String _weekRangeLabel(DateTime start, String dateLoc) {
    final end = start.add(const Duration(days: 6));
    final df = DateFormat('d MMM', dateLoc);
    return '${df.format(start).toUpperCase()} - ${df.format(end).toUpperCase()}';
  }

  String _monthRangeLabel(DateTime end, String dateLoc) {
    final start = DateTime(end.year, end.month - 2, 1);
    final df = DateFormat('MMM. yyyy', dateLoc);
    return '${df.format(start).toUpperCase()} - ${df.format(end).toUpperCase()}';
  }

  Widget _buildSubTabsRow(
    List<String> labels,
    int selected,
    ValueChanged<int> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: labels.asMap().entries.map((e) {
            final isSelected = e.key == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary
                        : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: isSelected
                          ? cs.onPrimary
                          : cs.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPeriodNav({
    required String label,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onPrev,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: onNext == null ? cs.outlineVariant : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              'Sem transações',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Icon Tab Button ──────────────────────────────────────────────────────────

class _IconTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _IconTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Category Chart (Donut) ───────────────────────────────────────────────────

class _CategoryChart extends StatelessWidget {
  final List<_PieSlice> slices;
  final String Function(double) fmt;
  final double total;

  const _CategoryChart({
    required this.slices,
    required this.fmt,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Donut chart
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(220, 220),
                  painter: _DonutPainter(slices: slices),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fmt(total),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Category rows
        ...slices.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.category,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '${(s.percentage * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      fmt(s.amount),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: s.percentage,
                    backgroundColor: s.color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(s.color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Area / Line Chart ────────────────────────────────────────────────────────

class _ChartPoint {
  final String label;
  final double value;
  const _ChartPoint({required this.label, required this.value});
}

class _AreaChart extends StatelessWidget {
  final List<_ChartPoint> points;
  final Color color;
  final String Function(double) fmt;

  const _AreaChart({
    required this.points,
    required this.color,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: CustomPaint(
            painter: _AreaPainter(points: points, color: color, fmt: fmt),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _AreaPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final Color color;
  final String Function(double) fmt;

  const _AreaPainter({
    required this.points,
    required this.color,
    required this.fmt,
  });

  static const double _leftPad = 68;
  static const double _rightPad = 12;
  static const double _topPad = 12;
  static const double _bottomPad = 32;
  static const int _yDivisions = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartW = size.width - _leftPad - _rightPad;
    final chartH = size.height - _topPad - _bottomPad;

    if (chartW <= 0 || chartH <= 0) return;

    final maxVal = points.map((p) => p.value).fold<double>(0, math.max);
    final effectiveMax = maxVal == 0 ? 1.0 : _niceMax(maxVal);

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.12)
      ..strokeWidth = 0.8;

    final labelStyle = TextStyle(fontSize: 9, color: Colors.grey.shade500);

    // ── Y grid lines + labels ──────────────────────────────────────────
    for (int i = 0; i <= _yDivisions; i++) {
      final frac = i / _yDivisions;
      final y = _topPad + chartH * (1 - frac);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(size.width - _rightPad, y),
        gridPaint,
      );
      final val = effectiveMax * frac;
      _drawText(
        canvas,
        _compactFmt(val),
        Offset(0, y - 6),
        _leftPad - 4,
        labelStyle,
        TextAlign.right,
      );
    }

    if (maxVal == 0) return;

    // ── Point helper ───────────────────────────────────────────────────
    final n = points.length;
    final dx = chartW / (n == 1 ? 1 : n - 1);

    Offset pt(int i) => Offset(
          _leftPad + (n == 1 ? chartW / 2 : i * dx),
          _topPad + chartH * (1 - points[i].value / effectiveMax),
        );

    // ── Smooth bezier path ─────────────────────────────────────────────
    final linePath = Path();
    final fillPath = Path();

    final baseY = _topPad + chartH;
    linePath.moveTo(pt(0).dx, pt(0).dy);
    fillPath.moveTo(pt(0).dx, baseY);
    fillPath.lineTo(pt(0).dx, pt(0).dy);

    for (int i = 1; i < n; i++) {
      final prev = pt(i - 1);
      final curr = pt(i);
      final cpX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
      fillPath.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
    }

    fillPath.lineTo(pt(n - 1).dx, baseY);
    fillPath.close();

    // Fill gradient
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.01),
          ],
        ).createShader(Rect.fromLTWH(_leftPad, _topPad, chartW, chartH)),
    );

    // Line stroke
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots at non-zero points (small, filled)
    final dotFill = Paint()..color = color..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < n; i++) {
      if (points[i].value <= 0) continue;
      final o = pt(i);
      // Only draw dots when there aren't too many points
      if (n <= 14) {
        canvas.drawCircle(o, 4.5, dotBorder);
        canvas.drawCircle(o, 3, dotFill);
      }
    }

    // ── X labels ──────────────────────────────────────────────────────
    for (int i = 0; i < n; i++) {
      if (points[i].label.isEmpty) continue;
      final x = pt(i).dx;
      final y = baseY + 5;
      _drawText(
        canvas,
        points[i].label,
        Offset(x - 26, y),
        52,
        labelStyle,
        TextAlign.center,
      );
    }
  }

  // Round up to a "nice" max value
  double _niceMax(double val) {
    final magnitude = math.pow(10, (math.log(val) / math.ln10).floor());
    final normalized = val / magnitude;
    double nice;
    if (normalized <= 1) {
      nice = 1;
    } else if (normalized <= 2) {
      nice = 2;
    } else if (normalized <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude * 1.0;
  }

  String _compactFmt(double val) {
    if (val >= 1000000) return 'R\$${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return 'R\$${(val / 1000).toStringAsFixed(0)}K';
    return 'R\$${val.toStringAsFixed(0)}';
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    TextStyle style,
    TextAlign align,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.points != points || old.color != color;
}

// ─── Grouped Bar Chart ────────────────────────────────────────────────────────

class _BarGroup {
  final String label;
  final List<double> values;
  const _BarGroup({required this.label, required this.values});
}

class _BarChartWidget extends StatelessWidget {
  final List<_BarGroup> groups;
  final List<Color> colors;
  final List<String> legendLabels;
  final String Function(double) fmt;

  const _BarChartWidget({
    required this.groups,
    required this.colors,
    required this.legendLabels,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          child: CustomPaint(
            painter: _BarPainter(groups: groups, colors: colors, fmt: fmt),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        Row(
          children: List.generate(colors.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[i],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    legendLabels[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<_BarGroup> groups;
  final List<Color> colors;
  final String Function(double) fmt;

  const _BarPainter({
    required this.groups,
    required this.colors,
    required this.fmt,
  });

  static const double _leftPad = 68;
  static const double _rightPad = 8;
  static const double _topPad = 8;
  static const double _bottomPad = 32;
  static const int _yDivisions = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (groups.isEmpty) return;

    final chartW = size.width - _leftPad - _rightPad;
    final chartH = size.height - _topPad - _bottomPad;

    double maxVal = 0;
    for (final g in groups) {
      for (final v in g.values) {
        if (v > maxVal) maxVal = v;
      }
    }
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal * 1.1;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    final labelStyle = TextStyle(
      fontSize: 9,
      color: Colors.grey.shade500,
    );

    // ── Y grid + labels ──────────────────────────────────────────────────
    for (int i = 0; i <= _yDivisions; i++) {
      final frac = i / _yDivisions;
      final y = _topPad + chartH * (1 - frac);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(size.width - _rightPad, y),
        gridPaint,
      );
      final val = effectiveMax * frac;
      _drawText(
        canvas,
        _compact(val),
        Offset(0, y - 6),
        _leftPad - 4,
        labelStyle,
        TextAlign.right,
      );
    }

    // ── Bars ─────────────────────────────────────────────────────────────
    final n = groups.length;
    final seriesCount = colors.length;
    const groupGap = 8.0;
    const barGap = 2.0;
    final groupW = (chartW - groupGap * (n - 1)) / n;
    final barW = seriesCount > 1
        ? (groupW - barGap * (seriesCount - 1)) / seriesCount
        : groupW * 0.7;

    for (int gi = 0; gi < n; gi++) {
      final gx = _leftPad + gi * (groupW + groupGap);

      for (int si = 0; si < seriesCount && si < groups[gi].values.length; si++) {
        final val = groups[gi].values[si];
        if (val <= 0) continue;

        final barH = (val / effectiveMax) * chartH;
        final bx = seriesCount > 1
            ? gx + si * (barW + barGap)
            : gx + (groupW - barW) / 2;
        final by = _topPad + chartH - barH;

        final rrect = RRect.fromRectAndCorners(
          Rect.fromLTWH(bx, by, barW, barH),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(
          rrect,
          Paint()..color = colors[si],
        );
      }

      // X label
      final labelX = gx + groupW / 2;
      _drawText(
        canvas,
        groups[gi].label,
        Offset(labelX - 28, _topPad + chartH + 6),
        56,
        labelStyle,
        TextAlign.center,
      );
    }
  }

  String _compact(double val) {
    if (val >= 1000000) return 'R\$${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return 'R\$${(val / 1000).toStringAsFixed(0)}K';
    return 'R\$${val.toStringAsFixed(0)}';
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    TextStyle style,
    TextAlign align,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.groups != groups || old.colors != colors;
}

// ─── Data classes ─────────────────────────────────────────────────────────────

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

// ─── Donut Painter ────────────────────────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  final List<_PieSlice> slices;

  const _DonutPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2;
    final innerRadius = outerRadius * 0.55;
    const gapAngle = 0.025;

    double startAngle = -math.pi / 2;

    for (final slice in slices) {
      final sweepAngle = slice.percentage * 2 * math.pi - gapAngle;

      final path = Path();
      final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
      final innerRect = Rect.fromCircle(center: center, radius: innerRadius);

      path.arcTo(outerRect, startAngle, sweepAngle, false);
      path.arcTo(innerRect, startAngle + sweepAngle, -sweepAngle, false);
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.fill,
      );

      startAngle += slice.percentage * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}
