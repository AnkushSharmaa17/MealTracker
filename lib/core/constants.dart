import 'package:flutter/material.dart';

const Color tomatoRed = Color(0xFFFF6347);
const Color tomatoDeep = Color(0xFFE8452C);
const Color sageGreen = Color(0xFF8A9A5B);
const Color offWhite = Color(0xFFFCFBF7);
const Color nightIndigo = Color(0xFF5C6BC0);
const Color streakAmber = Color(0xFFFFA000);
const Color canteenTeal = Color(0xFF0E9F94);
const Color canteenTealDeep = Color(0xFF0A6F68);

class MealMeta {
  final String type;
  final IconData icon;
  final Color color;
  const MealMeta(this.type, this.icon, this.color);
}

const List<MealMeta> mealMetas = [
  MealMeta('Morning', Icons.wb_twilight_rounded, tomatoRed),
  MealMeta('Afternoon', Icons.wb_sunny_rounded, sageGreen),
  MealMeta('Night', Icons.nightlight_round, nightIndigo),
];

/// Returns metadata for a meal type; unknown types (old "General" extras)
/// get a neutral food icon.
MealMeta mealMetaOf(String type) {
  for (final m in mealMetas) {
    if (m.type == type) return m;
  }
  return const MealMeta('General', Icons.fastfood_rounded, tomatoRed);
}

const List<String> kSkipReasons = [
  'Not Hungry',
  'Out of Campus',
  'Sick',
  'Guests/Party',
  'Other',
];
