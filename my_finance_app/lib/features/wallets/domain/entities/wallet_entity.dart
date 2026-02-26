import 'package:equatable/equatable.dart';

class WalletEntity extends Equatable {
  final String id;
  final String userId;
  final String name;
  final int iconCodePoint;
  final int colorValue;
  final bool isDefault;

  const WalletEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.iconCodePoint,
    required this.colorValue,
    this.isDefault = false,
  });

  @override
  List<Object?> get props =>
      [id, userId, name, iconCodePoint, colorValue, isDefault];
}
