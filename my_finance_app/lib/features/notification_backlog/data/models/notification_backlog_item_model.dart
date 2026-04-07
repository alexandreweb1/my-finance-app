import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../features/transactions/domain/entities/transaction_entity.dart';
import '../../domain/entities/notification_backlog_item_entity.dart';

class NotificationBacklogItemModel extends NotificationBacklogItemEntity {
  const NotificationBacklogItemModel({
    required super.id,
    required super.userId,
    required super.amount,
    required super.type,
    required super.rawText,
    required super.sourceApp,
    required super.receivedAt,
    required super.imported,
  });

  factory NotificationBacklogItemModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = data['type'] as String?;
    return NotificationBacklogItemModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      amount: (data['amount'] as num? ?? 0).toDouble(),
      type: typeStr == 'expense'
          ? TransactionType.expense
          : typeStr == 'income'
              ? TransactionType.income
              : null,
      rawText: data['rawText'] as String? ?? '',
      sourceApp: data['sourceApp'] as String? ?? '',
      receivedAt: data['receivedAt'] is Timestamp
          ? (data['receivedAt'] as Timestamp).toDate()
          : DateTime.now(),
      imported: data['imported'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'amount': amount,
        'type': type == TransactionType.expense
            ? 'expense'
            : type == TransactionType.income
                ? 'income'
                : null,
        'rawText': rawText,
        'sourceApp': sourceApp,
        'receivedAt': Timestamp.fromDate(receivedAt),
        'imported': imported,
      };
}
