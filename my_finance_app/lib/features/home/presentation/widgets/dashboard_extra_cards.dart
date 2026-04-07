import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_formatter.dart';
import '../../../recurring/domain/entities/recurring_transaction_entity.dart';
import '../../../recurring/presentation/providers/recurring_provider.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';

// ─── Recent Transactions Card ─────────────────────────────────────────────────

class DashboardRecentTransactions extends ConsumerWidget {
  const DashboardRecentTransactions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(currencyFormatterProvider);
    final dateLoc = ref.watch(dateLocaleProvider);
    final txs = ref.watch(visibleTransactionsProvider);
    final cs = Theme.of(context).colorScheme;

    // Last 5 transactions sorted by date desc
    final recent = [...txs]
      ..sort((a, b) => b.date.compareTo(a.date));
    final slice = recent.take(5).toList();

    if (slice.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (int i = 0; i < slice.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 52,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            _RecentTile(tx: slice[i], fmt: fmt, dateLoc: dateLoc),
          ],
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final dynamic tx;
  final String Function(double) fmt;
  final String dateLoc;

  const _RecentTile({
    required this.tx,
    required this.fmt,
    required this.dateLoc,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isIncome = tx.isIncome as bool;
    final color = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = isIncome ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isIncome
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.title as String,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  tx.category as String,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${fmt(tx.amount as double)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('dd/MM', dateLoc).format(tx.date as DateTime),
                style: TextStyle(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Upcoming Recurring Card ──────────────────────────────────────────────────

class DashboardUpcomingRecurring extends ConsumerWidget {
  const DashboardUpcomingRecurring({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = ref.watch(currencyFormatterProvider);
    final dateLoc = ref.watch(dateLocaleProvider);
    final recurrences = ref.watch(activeRecurrencesProvider);
    final cs = Theme.of(context).colorScheme;

    final now = DateTime.now();

    // Collect next occurrences for each active recurrence
    final upcoming = <({RecurringTransactionEntity r, DateTime date})>[];
    for (final r in recurrences) {
      final next = r.nextOccurrence(afterDate: now.subtract(const Duration(days: 1)));
      if (next != null) {
        upcoming.add((r: r, date: next));
      }
    }
    upcoming.sort((a, b) => a.date.compareTo(b.date));
    final slice = upcoming.take(5).toList();

    if (slice.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.event_available_outlined,
                  size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                'Nenhuma recorrência ativa',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
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
          children: [
            for (int i = 0; i < slice.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              _RecurringTile(
                item: slice[i],
                fmt: fmt,
                dateLoc: dateLoc,
                now: now,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  final ({RecurringTransactionEntity r, DateTime date}) item;
  final String Function(double) fmt;
  final String dateLoc;
  final DateTime now;

  const _RecurringTile({
    required this.item,
    required this.fmt,
    required this.dateLoc,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final r = item.r;
    final date = item.date;
    final cs = Theme.of(context).colorScheme;
    final isIncome = r.isIncome;
    final color = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    final daysUntil = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    final String dateLabel;
    if (daysUntil == 0) {
      dateLabel = 'Hoje';
    } else if (daysUntil == 1) {
      dateLabel = 'Amanhã';
    } else {
      dateLabel = 'Em $daysUntil dias';
    }

    final urgent = daysUntil <= 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.repeat_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 11,
                      color: urgent
                          ? const Color(0xFFF59E0B)
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$dateLabel · ${DateFormat('dd/MM', dateLoc).format(date)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: urgent
                            ? const Color(0xFFF59E0B)
                            : cs.onSurfaceVariant,
                        fontWeight: urgent ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'}${fmt(r.amount)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
