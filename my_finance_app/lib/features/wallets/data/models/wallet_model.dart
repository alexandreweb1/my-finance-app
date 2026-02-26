import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/wallet_entity.dart';

class WalletModel extends WalletEntity {
  const WalletModel({
    required super.id,
    required super.userId,
    required super.name,
    required super.iconCodePoint,
    required super.colorValue,
    super.isDefault,
  });

  factory WalletModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WalletModel(
      id: doc.id,
      userId: data['userId'] as String,
      name: data['name'] as String,
      iconCodePoint: (data['iconCodePoint'] as num).toInt(),
      colorValue: (data['colorValue'] as num).toInt(),
      isDefault: data['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'name': name,
        'iconCodePoint': iconCodePoint,
        'colorValue': colorValue,
        'isDefault': isDefault,
      };

  factory WalletModel.fromEntity(WalletEntity entity) => WalletModel(
        id: entity.id,
        userId: entity.userId,
        name: entity.name,
        iconCodePoint: entity.iconCodePoint,
        colorValue: entity.colorValue,
        isDefault: entity.isDefault,
      );
}
