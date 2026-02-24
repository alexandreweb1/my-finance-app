import 'package:flutter/material.dart';

/// Maps Firestore-stored iconCodePoints to const [IconData] from [Icons].
/// Using a lookup instead of constructing [IconData] at runtime so that
/// Flutter's icon tree-shaking works in release builds.
const Map<int, IconData> kCategoryIconMap = {
  0xe8f8: Icons.work,
  0xe30a: Icons.computer,
  0xe8e5: Icons.trending_up,
  0xe574: Icons.category,
  0xeb6e: Icons.restaurant,
  0xe88a: Icons.home,
  0xe52f: Icons.directions_car,
  0xe548: Icons.local_hospital,
  0xe80c: Icons.school,
  0xe021: Icons.games,
  0xf19e: Icons.checkroom,
};

/// Returns the [IconData] for [codePoint], falling back to [Icons.category].
IconData categoryIcon(int codePoint) =>
    kCategoryIconMap[codePoint] ?? Icons.category;
