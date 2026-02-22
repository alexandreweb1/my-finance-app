import 'package:equatable/equatable.dart';

enum TransactionType { income, expense }

class TransactionEntity extends Equatable {
  final String id;
  final String userId;
  final String title;
  final double amount;
  final TransactionType type;
  final String category;
  final DateTime date;
  final String? description;

  const TransactionEntity({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.description,
  });

  bool get isIncome => type == TransactionType.income;
  bool get isExpense => type == TransactionType.expense;

  @override
  List<Object?> get props =>
      [id, userId, title, amount, type, category, date, description];
}
