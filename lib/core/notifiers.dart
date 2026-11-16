import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

/// Bumped whenever data or settings change; screens refresh themselves.
final ValueNotifier<int> dbUpdateNotifier = ValueNotifier(0);

/// Index of the currently visible bottom-navigation tab.
final ValueNotifier<int> tabIndexNotifier = ValueNotifier(0);

/// Current streak shown in the app bar.
final ValueNotifier<int> streakNotifier = ValueNotifier(0);

/// True while the PIN lock screen is covering the app.
final ValueNotifier<bool> appLockedNotifier = ValueNotifier(false);
