import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../budget/domain/entities/budget_entity.dart';
import '../../../budget/presentation/providers/budget_provider.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../../transactions/presentation/widgets/transaction_list_tile.dart';

// ─── Color palette ────────────────────────────────────────────────────────────
const _kNavy = Color(0xFF1A2B4A);
const _kGreen = Color(0xFF00D887);
const _kLightBg = Color(0xFFF4F6FA);

// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final balance = ref.watch(balanceProvider);
    final income = ref.watch(totalIncomeProvider);
    final expense = ref.watch(totalExpenseProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final budgetSummaries = ref.watch(budgetSummaryProvider);

    final l10n = AppLocalizations.of(context);
    final dateLoc = ref.watch(dateLocaleProvider);
    final name = user?.displayName?.split(' ').first ?? l10n.hello;
    final greeting = _greeting(l10n);

    return Scaffold(
      backgroundColor: _kLightBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _DarkHeader(
            name: name,
            greeting: greeting,
            balance: balance,
            income: income,
            expense: expense,
            transactions: transactionsAsync.value ?? [],
          ),

          const SizedBox(height: 20),

          _IncomeExpenseRow(income: income, expense: expense),

          const SizedBox(height: 24),

          if (budgetSummaries.isNotEmpty) ...[
            _SectionHeader(
              title: l10n.budgets,
              subtitle: DateFormat('MMM yyyy', dateLoc).format(DateTime.now()),
            ),
            const SizedBox(height: 8),
            ...budgetSummaries.take(3).map((s) => _BudgetCard(summary: s)),
            const SizedBox(height: 24),
          ],

          _SectionHeader(
            title: l10n.recentTransactions,
            subtitle: transactionsAsync.value != null
                ? '${transactionsAsync.value!.length} ${l10n.thisMonth}'
                : '',
          ),
          const SizedBox(height: 8),
          transactionsAsync.when(
            data: (txs) => txs.isEmpty
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
                    children: txs
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
}

// ─── Dark Header ──────────────────────────────────────────────────────────────
class _DarkHeader extends ConsumerWidget {
  final String name;
  final String greeting;
  final double balance;
  final double income;
  final double expense;
  final List<TransactionEntity> transactions;

  const _DarkHeader({
    required this.name,
    required this.greeting,
    required this.balance,
    required this.income,
    required this.expense,
    required this.transactions,
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
                Flexible(
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
                IconButton(
                  icon: const Icon(Icons.logout_outlined,
                      color: Colors.white70, size: 20),
                  tooltip: 'Sair',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
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

          const SizedBox(height: 8),

          // Trend indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_upward, color: _kGreen, size: 13),
                const SizedBox(width: 4),
                Text(
                  '+ ${fmt(income)} ${l10n.income}',
                  style: const TextStyle(
                      color: _kGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          SizedBox(height: compact ? 12 : 20),

          // Chart — oculto em telas muito estreitas para evitar distorção
          if (screenW >= 300) _SparklineChart(transactions: transactions),

          SizedBox(height: compact ? 12 : 20),
        ],
      ),
    );
  }
}

// ─── Sparkline Chart ──────────────────────────────────────────────────────────
class _SparklineChart extends ConsumerWidget {
  final List<TransactionEntity> transactions;

  const _SparklineChart({required this.transactions});

  List<double> _monthlyBalances() {
    final now = DateTime.now();
    return List.generate(6, (i) {
      final month = DateTime(now.year, now.month - (5 - i));
      double bal = 0;
      for (final t in transactions) {
        if (t.date.year == month.year && t.date.month == month.month) {
          bal += t.isIncome ? t.amount : -t.amount;
        }
      }
      return bal;
    });
  }

  List<String> _monthLabels(String locale) {
    final now = DateTime.now();
    return List.generate(6, (i) {
      final month = DateTime(now.year, now.month - (5 - i));
      return DateFormat('MMM', locale).format(month);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLoc = ref.watch(dateLocaleProvider);
    final rawData = _monthlyBalances();
    final allZero = rawData.every((v) => v == 0);
    final data =
        allZero ? [0.0, 120.0, 80.0, 250.0, 200.0, 400.0] : rawData;
    final labels = _monthLabels(dateLoc);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SizedBox(
            height: 80,
            child: CustomPaint(
              painter: _SparklinePainter(data: data),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map((l) => Text(l,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;

  const _SparklinePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).abs();
    final effectiveRange = range < 1 ? 1.0 : range;

    final points = List.generate(data.length, (i) {
      final x = i / (data.length - 1) * size.width;
      final norm =
          range < 1 ? 0.5 : (data[i] - minV) / effectiveRange;
      final y = size.height - (norm * size.height * 0.75) - size.height * 0.1;
      return Offset(x, y);
    });

    // Area fill
    final fill = Path()..moveTo(0, size.height);
    fill.lineTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final cx = (points[i - 1].dx + points[i].dx) / 2;
      fill.cubicTo(
          cx, points[i - 1].dy, cx, points[i].dy, points[i].dx, points[i].dy);
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
            _kGreen.withValues(alpha: 0.45),
            _kGreen.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final cx = (points[i - 1].dx + points[i].dx) / 2;
      line.cubicTo(
          cx, points[i - 1].dy, cx, points[i].dy, points[i].dx, points[i].dy);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = _kGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);

    // Dot
    canvas.drawCircle(points.last, 5, Paint()..color = _kGreen);
    canvas.drawCircle(points.last, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.data != data;
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
              iconBg: const Color(0xFFE8FBF3),
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
              iconBg: const Color(0xFFFFEEEE),
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
  final Color iconBg;
  final Color iconColor;
  final Color valueColor;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
              color: iconBg,
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _kNavy,
              )),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kNavy),
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
            backgroundColor: Colors.grey.shade100,
            color: progressColor,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}
