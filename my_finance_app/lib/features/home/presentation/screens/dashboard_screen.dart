import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../budget/domain/entities/budget_entity.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../../transactions/presentation/widgets/transaction_list_tile.dart';
import '../providers/dashboard_provider.dart';

// ─── Color palette ────────────────────────────────────────────────────────────
const _kNavy = Color(0xFF1A2B4A);
const _kGreen = Color(0xFF00D887);
const _kLightBg = Color(0xFFF4F6FA);

// ─── Number of months shown in the chart ─────────────────────────────────────
const _kChartMonths = 24;
const _kMonthColWidth = 56.0;

// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final balance = ref.watch(balanceProvider);
    final income = ref.watch(dashboardMonthIncomeProvider);
    final expense = ref.watch(dashboardMonthExpenseProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final visibleTxs = ref.watch(visibleTransactionsProvider);
    final budgetSummaries = ref.watch(dashboardBudgetSummaryProvider);
    final selectedMonth = ref.watch(dashboardSelectedMonthProvider);

    final l10n = AppLocalizations.of(context);
    final dateLoc = ref.watch(dateLocaleProvider);
    final name = user?.displayName?.split(' ').first ?? l10n.hello;
    final greeting = _greeting(l10n);
    final initials = _initials(user?.displayName);

    // Transactions filtered to the selected month (visible wallets only)
    final monthTxs = visibleTxs
        .where((t) =>
            t.date.year == selectedMonth.year &&
            t.date.month == selectedMonth.month)
        .toList();

    final monthLabel =
        DateFormat('MMM yyyy', dateLoc).format(selectedMonth);

    // Use theme-aware surface color so dark mode works correctly.
    // _kLightBg is kept for the light-mode tinted background via
    // a surfaceTint-aware overlay instead of a hardcoded constant.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? null : _kLightBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _DarkHeader(
            name: name,
            greeting: greeting,
            balance: balance,
            transactions: visibleTxs,
            userInitials: initials,
            userPhotoUrl: user?.photoUrl,
            onSettingsTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),

          const SizedBox(height: 20),

          _IncomeExpenseRow(income: income, expense: expense),

          const SizedBox(height: 24),

          if (budgetSummaries.isNotEmpty) ...[
            _SectionHeader(
              title: l10n.budgets,
              subtitle: monthLabel,
            ),
            const SizedBox(height: 8),
            ...budgetSummaries.take(3).map((s) => _BudgetCard(summary: s)),
            const SizedBox(height: 24),
          ],

          _SectionHeader(
            title: l10n.recentTransactions,
            subtitle: monthLabel,
          ),
          const SizedBox(height: 8),
          transactionsAsync.when(
            data: (_) => monthTxs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        l10n.noTransactions,
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  )
                : Column(
                    children: monthTxs
                        .take(5)
                        .map((t) => TransactionListTile(transaction: t))
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  l10n.errorGeneric,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour < 12) return l10n.goodMorning;
    if (hour < 18) return l10n.goodAfternoon;
    return l10n.goodEvening;
  }

  static String _initials(String? displayName) {
    if (displayName == null || displayName.trim().isEmpty) return '?';
    final parts = displayName.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

// ─── Dark Header ──────────────────────────────────────────────────────────────
class _DarkHeader extends ConsumerWidget {
  final String name;
  final String greeting;
  final double balance;
  final List<TransactionEntity> transactions;
  final String userInitials;
  final String? userPhotoUrl;
  final VoidCallback onSettingsTap;

  const _DarkHeader({
    required this.name,
    required this.greeting,
    required this.balance,
    required this.transactions,
    required this.userInitials,
    this.userPhotoUrl,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(currencyFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final topPad = MediaQuery.of(context).padding.top;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 340;

    return Container(
      decoration: const BoxDecoration(
        color: _kNavy,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: topPad + 8),

          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$greeting, $name!',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: compact ? 12 : 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSettingsTap,
                  child: UserAvatar(
                    photoUrl: userPhotoUrl,
                    initials: userInitials,
                    radius: 18,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Text(
            'Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: compact ? 10 : 16),

          // Balance
          Text(
            l10n.totalBalance,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                fmt(balance),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 28 : 38,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          SizedBox(height: compact ? 12 : 20),

          // Chart — hidden on very narrow screens
          if (screenW >= 300) _SparklineChart(transactions: transactions),

          SizedBox(height: compact ? 12 : 20),
        ],
      ),
    );
  }
}

// ─── Sparkline Chart (scrollable, 12 months, selectable) ─────────────────────
class _SparklineChart extends ConsumerStatefulWidget {
  final List<TransactionEntity> transactions;

  const _SparklineChart({required this.transactions});

  @override
  ConsumerState<_SparklineChart> createState() => _SparklineChartState();
}

class _SparklineChartState extends ConsumerState<_SparklineChart> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll to the rightmost (most-recent) month after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Returns the list of months shown in the chart (oldest → newest).
  List<DateTime> _months() {
    final now = DateTime.now();
    return List.generate(_kChartMonths, (i) {
      return DateTime(now.year, now.month - (_kChartMonths - 1 - i));
    });
  }

  List<double> _monthlyIncome(List<DateTime> months) {
    return months.map((month) {
      double total = 0;
      for (final t in widget.transactions) {
        if (t.date.year == month.year &&
            t.date.month == month.month &&
            t.isIncome) {
          total += t.amount;
        }
      }
      return total;
    }).toList();
  }

  List<double> _monthlyExpenses(List<DateTime> months) {
    return months.map((month) {
      double total = 0;
      for (final t in widget.transactions) {
        if (t.date.year == month.year &&
            t.date.month == month.month &&
            !t.isIncome) {
          total += t.amount;
        }
      }
      return total;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dateLoc = ref.watch(dateLocaleProvider);
    final selectedMonth = ref.watch(dashboardSelectedMonthProvider);
    final months = _months();
    final rawIncome = _monthlyIncome(months);
    final rawExpenses = _monthlyExpenses(months);
    final allZero =
        rawIncome.every((v) => v == 0) && rawExpenses.every((v) => v == 0);
    final incomeData = allZero
        ? [40.0, 80.0, 60.0, 120.0, 100.0, 200.0, 180.0, 250.0, 220.0,
           300.0, 350.0, 400.0]
        : rawIncome;
    final expenseData = allZero
        ? [20.0, 40.0, 90.0, 50.0, 140.0, 80.0, 220.0, 100.0, 180.0,
           150.0, 200.0, 250.0]
        : rawExpenses;

    // Index of the selected month within our months list (-1 if not found).
    final selectedIdx = months.indexWhere((m) =>
        m.year == selectedMonth.year && m.month == selectedMonth.month);

    const totalWidth = _kChartMonths * _kMonthColWidth;

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0.0, 0.08, 0.92, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Chart area
                SizedBox(
                  height: 80,
                  width: totalWidth,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      incomeData: incomeData,
                      expenseData: expenseData,
                      selectedIndex: selectedIdx,
                    ),
                    size: const Size(totalWidth, 80),
                  ),
                ),
                const SizedBox(height: 6),
                // Month labels row — each tappable
                Row(
                  children: List.generate(months.length, (i) {
                    final month = months[i];
                    final isSelected = i == selectedIdx;
                    final label = DateFormat('MMM', dateLoc).format(month);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ref
                            .read(dashboardSelectedMonthProvider.notifier)
                            .state = month;
                      },
                      child: SizedBox(
                        width: _kMonthColWidth,
                        height: 44,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _kGreen
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> incomeData;
  final List<double> expenseData;
  final int selectedIndex;

  static const _kRed = Color(0xFFE05252);

  const _SparklinePainter({
    required this.incomeData,
    required this.expenseData,
    required this.selectedIndex,
  });

  List<Offset> _toPoints(List<double> data, double minV, double maxV, Size size) {
    final range = (maxV - minV).abs();
    final effectiveRange = range < 1 ? 1.0 : range;
    return List.generate(data.length, (i) {
      final x = i / (data.length - 1) * size.width;
      final norm = range < 1 ? 0.5 : (data[i] - minV) / effectiveRange;
      final y = size.height - (norm * size.height * 0.75) - size.height * 0.1;
      return Offset(x, y);
    });
  }

  void _drawSeries(Canvas canvas, Size size, List<Offset> points, Color color) {
    // Area fill
    final fill = Path()..moveTo(0, size.height);
    fill.lineTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final cx = (points[i - 1].dx + points[i].dx) / 2;
      fill.cubicTo(cx, points[i - 1].dy, cx, points[i].dy, points[i].dx, points[i].dy);
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final cx = (points[i - 1].dx + points[i].dx) / 2;
      line.cubicTo(cx, points[i - 1].dy, cx, points[i].dy, points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (incomeData.length < 2 || expenseData.length < 2) return;

    // Shared scale across both series so lines are comparable
    final allValues = [...incomeData, ...expenseData];
    final minV = allValues.reduce(math.min);
    final maxV = allValues.reduce(math.max);

    final incomePoints = _toPoints(incomeData, minV, maxV, size);
    final expensePoints = _toPoints(expenseData, minV, maxV, size);

    // Selected month highlight column
    if (selectedIndex >= 0 && selectedIndex < incomeData.length) {
      final colW = size.width / incomeData.length;
      final colX = selectedIndex * colW;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(colX, 0, colW, size.height),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.08),
      );
    }

    // Draw expense (red) first so income (green) renders on top
    _drawSeries(canvas, size, expensePoints, _kRed);
    _drawSeries(canvas, size, incomePoints, _kGreen);

    // Dots on selected month (or last point)
    final dotIdx = selectedIndex >= 0 && selectedIndex < incomePoints.length
        ? selectedIndex
        : incomePoints.length - 1;

    // Expense dot
    canvas.drawCircle(expensePoints[dotIdx], 4, Paint()..color = _kRed);
    canvas.drawCircle(expensePoints[dotIdx], 2.5, Paint()..color = Colors.white);

    // Income dot
    canvas.drawCircle(incomePoints[dotIdx], 5, Paint()..color = _kGreen);
    canvas.drawCircle(incomePoints[dotIdx], 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.incomeData != incomeData ||
      old.expenseData != expenseData ||
      old.selectedIndex != selectedIndex;
}

// ─── Income / Expense Row ─────────────────────────────────────────────────────
class _IncomeExpenseRow extends ConsumerWidget {
  final double income;
  final double expense;

  const _IncomeExpenseRow({required this.income, required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fmt = ref.watch(currencyFormatterProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _MiniStatCard(
              label: l10n.income,
              value: fmt(income),
              icon: Icons.arrow_downward_rounded,
              iconColor: _kGreen,
              valueColor: _kGreen,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _MiniStatCard(
              label: l10n.expenses,
              value: fmt(expense),
              icon: Icons.arrow_upward_rounded,
              iconColor: const Color(0xFFE05252),
              valueColor: const Color(0xFFE05252),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color valueColor;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: valueColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              )),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─── Budget Card ──────────────────────────────────────────────────────────────
class _BudgetCard extends ConsumerWidget {
  final BudgetSummary summary;

  const _BudgetCard({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(currencyFormatterProvider);
    final progressColor = summary.isOverBudget
        ? const Color(0xFFE05252)
        : summary.progress > 0.8
            ? Colors.orange.shade600
            : _kGreen;

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  summary.budget.categoryName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${fmt(summary.spentAmount)} / '
                '${fmt(summary.budget.limitAmount)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: summary.progress,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            color: progressColor,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}
