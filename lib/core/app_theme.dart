import 'package:flutter/material.dart';

import 'constants.dart';

/// Central colour palette so screens never repeat `isDark ? a : b` everywhere.
class AppColors {
  final bool isDark;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color skeleton;

  const AppColors._({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.skeleton,
  });

  static const AppColors light = AppColors._(
    isDark: false,
    bg: offWhite,
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6F5F0),
    border: Color(0xFFEBE9E2),
    text: Color(0xFF1A1A1A),
    textMuted: Color(0xFF6B6B6B),
    textFaint: Color(0xFF9A9A9A),
    skeleton: Color(0xFFEAE8E1),
  );

  static const AppColors dark = AppColors._(
    isDark: true,
    bg: Color(0xFF0E0E10),
    surface: Color(0xFF16161A),
    surfaceAlt: Color(0xFF1E1E22),
    border: Color(0xFF2A2A30),
    text: Color(0xFFF2F2F2),
    textMuted: Color(0xFF9A9AA2),
    textFaint: Color(0xFF6C6C74),
    skeleton: Color(0xFF26262C),
  );

  static AppColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: tomatoRed,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: c.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
