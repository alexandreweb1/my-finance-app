import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../providers/transactions_provider.dart';
import '../widgets/transaction_list_tile.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final balance = ref.watch(balanceProvider);
    final income = ref.watch(totalIncomeProvider);
    final expense = ref.watch(totalExpenseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extrato'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          _SummaryCard(balance: balance, income: income, expense: expense),
          Expanded(
            child: transactionsAsync.when(
              data: (transactions) => transactions.isEmpty
                  ? const Center(
                      child: Text('Nenhuma transação encontrada.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: transactions.length,
                      itemBuilder: (ctx, i) =>
                          TransactionListTile(transaction: transactions[i]),
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double balance;
  final double income;
  final double expense;

  const _SummaryCard({
    required this.balance,
    required this.income,
    required this.expense,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = balance >= 0;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Saldo Atual', style: Theme.of(context).textTheme.titleMedium),
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
              CurrencyFormatter.formatBRL(value),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}
