import 'package:flutter/material.dart';

/// Maps Firestore-stored iconCodePoints to const [IconData] from [Icons].
/// Using a lookup instead of constructing [IconData] at runtime so that
/// Flutter's icon tree-shaking works in release builds.
const Map<int, IconData> kCategoryIconMap = {
  // ── Work & Business ──────────────────────────────────────────────────────
  0xe8f8: Icons.work,
  0xe30a: Icons.computer,
  0xe0af: Icons.business,
  0xe8e5: Icons.trending_up,
  0xe26b: Icons.bar_chart,
  // ── Finance ──────────────────────────────────────────────────────────────
  0xe4c9: Icons.account_balance_wallet,
  0xe84f: Icons.account_balance,
  0xe227: Icons.attach_money,
  0xe870: Icons.credit_card,
  // ── Food & Drink ─────────────────────────────────────────────────────────
  0xeb6e: Icons.restaurant,
  0xe541: Icons.local_cafe,
  0xe547: Icons.local_grocery_store,
  // ── Home & Living ────────────────────────────────────────────────────────
  0xe88a: Icons.home,
  0xe325: Icons.phone,
  0xe8d1: Icons.wifi,
  0xe1cb: Icons.electric_bolt,
  // ── Transport ────────────────────────────────────────────────────────────
  0xe52f: Icons.directions_car,
  0xe539: Icons.flight,
  0xe546: Icons.local_gas_station,
  // ── Health ───────────────────────────────────────────────────────────────
  0xe548: Icons.local_hospital,
  0xeb43: Icons.fitness_center,
  // ── Education & Culture ──────────────────────────────────────────────────
  0xe80c: Icons.school,
  // ── Entertainment ────────────────────────────────────────────────────────
  0xe021: Icons.games,
  0xe02c: Icons.movie,
  0xe405: Icons.music_note,
  0xea35: Icons.sports_soccer,
  // ── Shopping & Others ────────────────────────────────────────────────────
  0xf19e: Icons.checkroom,
  0xe8cc: Icons.shopping_cart,
  0xe91d: Icons.pets,
  0xe574: Icons.category,
};

/// Returns the [IconData] for [codePoint], falling back to [Icons.category].
IconData categoryIcon(int codePoint) =>
    kCategoryIconMap[codePoint] ?? Icons.category;
