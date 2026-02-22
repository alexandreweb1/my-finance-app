import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/transaction_entity.dart';
import '../providers/transactions_provider.dart';

class TransactionListTile extends ConsumerWidget {
  final TransactionEntity transaction;

  const TransactionListTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = transaction.isIncome;
    final color = isIncome ? Colors.green.shade700 : Colors.red.shade700;
    final sign = isIncome ? '+' : '-';

    return Dismissible(
      key: Key(transaction.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade100,
        child: Icon(Icons.delete, color: Colors.red.shade700),
      ),
      onDismissed: (_) {
        ref
            .read(transactionsNotifierProvider.notifier)
            .delete(transaction.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isIncome ? Colors.green.shade50 : Colors.red.shade50,
          child: Icon(
            isIncome ? Icons.arrow_upward : Icons.arrow_downward,
            color: color,
            size: 20,
          ),
        ),
        title: Text(transaction.title,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${transaction.category} · ${CurrencyFormatter.formatDate(transaction.date)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          '$sign${CurrencyFormatter.formatBRL(transaction.amount)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
