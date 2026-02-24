import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../budget/domain/entities/budget_entity.dart';
import '../../../budget/presentation/providers/budget_provider.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../../transactions/presentation/widgets/transaction_list_tile.dart';

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

    final greeting = _greeting();
    final name = user?.displayName?.split(' ').first ?? 'você';
    final monthLabel =
        DateFormat('MMMM yyyy', 'pt_BR').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Finance App'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () =>
                ref.read(authNotifierProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          // Greeting
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$greeting, $name! 👋',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(monthLabel,
                    style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),

          // Balance card
          _BalanceCard(balance: balance, income: income, expense: expense),

          // Budget overview
          if (budgetSummaries.isNotEmpty) ...[
            _SectionTitle(
                title: 'Orçamentos',
                subtitle: DateFormat('MMM yyyy', 'pt_BR')
                    .format(DateTime.now())),
            ...budgetSummaries
                .take(3)
                .map((s) => _BudgetMiniCard(summary: s)),
          ],

          // Recent transactions
          _SectionTitle(
              title: 'Últimas transações',
              subtitle: transactionsAsync.value != null
                  ? '${transactionsAsync.value!.length} no total'
                  : ''),
          transactionsAsync.when(
            data: (txs) => txs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('Nenhuma transação registrada.')),
                  )
                : Column(
                    children: txs
                        .take(5)
                        .map((t) => TransactionListTile(transaction: t))
                        .toList(),
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erro: $e')),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;
  final double income;
  final double expense;

  const _BalanceCard(
      {required this.balance,
      required this.income,
      required this.expense});

  @override
  Widget build(BuildContext context) {
    final isPositive = balance >= 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Saldo Atual',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              CurrencyFormatter.formatBRL(balance),
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
                    label: 'Receitas',
                    value: income,
                    color: Colors.green.shade700,
                    icon: Icons.arrow_upward,
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: 'Despesas',
                    value: expense,
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
  final double value;
  final Color color;
  final IconData icon;

  const _SummaryItem(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

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
            Text(CurrencyFormatter.formatBRL(value),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _BudgetMiniCard extends StatelessWidget {
  final BudgetSummary summary;

  const _BudgetMiniCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final progressColor = summary.isOverBudget
        ? Colors.red.shade600
        : summary.progress > 0.8
            ? Colors.orange.shade600
            : Colors.green.shade600;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(summary.budget.categoryName,
                  style: const TextStyle(fontSize: 13)),
              Text(
                '${CurrencyFormatter.formatBRL(summary.spentAmount)} / '
                '${CurrencyFormatter.formatBRL(summary.budget.limitAmount)}',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: summary.progress,
            backgroundColor: Colors.grey.shade200,
            color: progressColor,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
