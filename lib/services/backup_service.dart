import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/backup.dart';
import '../core/notifiers.dart';
import '../data/database_helper.dart';
import 'notification_service.dart';

/// Local-only backup: produces plain JSON text (copied to the clipboard by the
/// caller) and restores from it. No network, no files, no accounts.
class BackupService {
  static Future<String> createBackup() async {
    final tables = await DatabaseHelper.instance.exportTables();
    final prefs = await SharedPreferences.getInstance();

    final saved = <String, Object>{};
    for (final key in kBackupPrefKeys) {
      final v = prefs.get(key);
      if (v == null) continue;
      if (v is List) {
        saved[key] = v.map((e) => e.toString()).toList();
      } else {
        saved[key] = v;
      }
    }

    return encodeBackup(
      meals: tables['meals'] ?? <Map<String, Object?>>[],
      extras: tables['extra_meals'] ?? <Map<String, Object?>>[],
      canteen: tables['canteen_entries'] ?? <Map<String, Object?>>[],
      prefs: saved,
      now: DateTime.now(),
    );
  }

  /// Replaces all data with the backup. The database part is one transaction.
  static Future<void> restore(BackupData data) async {
    await DatabaseHelper.instance.replaceAllData(
      meals: data.meals,
      extras: data.extras,
      canteen: data.canteen,
    );

    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.prefs.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    }

    themeNotifier.value =
        (prefs.getBool('isDarkMode') ?? false) ? ThemeMode.dark : ThemeMode.light;
    dbUpdateNotifier.value++;
    unawaited(NotificationService.instance.syncReminders());
  }

  /// Deletes every record and preference (used by "forgot PIN").
  static Future<void> eraseEverything() async {
    await DatabaseHelper.instance.wipeAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('perm_prompted', true);
    themeNotifier.value = ThemeMode.light;
    dbUpdateNotifier.value++;
    unawaited(NotificationService.instance.syncReminders());
  }
}
