import '../../../../features/transactions/domain/entities/transaction_entity.dart';

class NotificationBacklogItemEntity {
  final String id;
  final String userId;
  final double amount;

  /// null means the type could not be determined from the notification text.
  final TransactionType? type;

  /// Full raw text from the bank notification.
  final String rawText;

  /// Android package name of the source app (e.g. "com.nu.production").
  final String sourceApp;

  final DateTime receivedAt;

  /// True once the user has tapped "Importar" for this item.
  final bool imported;

  const NotificationBacklogItemEntity({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.rawText,
    required this.sourceApp,
    required this.receivedAt,
    required this.imported,
  });
}
