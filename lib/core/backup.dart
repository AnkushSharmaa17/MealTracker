// Backup file format (JSON text) + strict validation. Pure Dart.
//
// Nothing here talks to a server: the backup is plain text that the user
// copies and stores wherever they like.

import 'dart:convert';

import 'canteen.dart';
import 'models.dart';

const String kBackupApp = 'meal_streak';
const int kBackupVersion = 1;

/// Only these preference keys are backed up / restored. The app-lock PIN and
/// internal flags are deliberately NOT included.
const Set<String> kBackupPrefKeys = {
  'isDarkMode',
  'rate_type',
  'monthly_fee',
  'per_meal_same',
  'rate_same',
  'rate_morning',
  'rate_afternoon',
  'rate_night',
  'fixed_meals',
  'time_morning_h',
  'time_morning_m',
  'time_afternoon_h',
  'time_afternoon_m',
  'time_night_h',
  'time_night_m',
  'canteen_name',
  'canteen_upi',
  'canteen_budget',
};

class BackupData {
  final List<Map<String, Object?>> meals;
  final List<Map<String, Object?>> extras;
  final List<Map<String, Object?>> canteen;
  final Map<String, Object> prefs;
  final DateTime? created;

  /// Rows that were dropped because they were malformed.
  final int skipped;

  const BackupData({
    required this.meals,
    required this.extras,
    required this.canteen,
    required this.prefs,
    this.created,
    this.skipped = 0,
  });

  int get totalRows => meals.length + extras.length + canteen.length;
}

String encodeBackup({
  required List<Map<String, Object?>> meals,
  required List<Map<String, Object?>> extras,
  required List<Map<String, Object?>> canteen,
  required Map<String, Object> prefs,
  required DateTime now,
}) {
  return jsonEncode(<String, Object?>{
    'app': kBackupApp,
    'version': kBackupVersion,
    'created': now.toIso8601String(),
    'meals': meals,
    'extra_meals': extras,
    'canteen_entries': canteen,
    'prefs': prefs,
  });
}

final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

double? _amount(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite || d < 0 || d > 10000000) return null;
  return d;
}

String? _text(Object? v, int max) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty || t.length > max) return null;
  return t;
}

Map<String, Object?>? _cleanMeal(Map<String, dynamic> m) {
  final date = m['date'];
  final type = m['meal_type'];
  if (date is! String || !_dateRe.hasMatch(date)) return null;
  if (type is! String || !kMealTypes.contains(type)) return null;
  final eaten = m['is_eaten'] == true || m['is_eaten'] == 1;
  final reason = _text(m['skip_reason'], 60);
  return <String, Object?>{
    'date': date,
    'meal_type': type,
    'is_eaten': eaten ? 1 : 0,
    'skip_reason': eaten ? null : reason,
  };
}

Map<String, Object?>? _cleanExtra(Map<String, dynamic> m) {
  final date = m['date'];
  if (date is! String || !_dateRe.hasMatch(date)) return null;
  final name = _text(m['name'], 80);
  final amount = _amount(m['amount']);
  if (name == null || amount == null) return null;
  return <String, Object?>{
    'date': date,
    'meal_type': _text(m['meal_type'], 20) ?? 'General',
    'name': name,
    'amount': amount,
  };
}

Map<String, Object?>? _cleanCanteen(Map<String, dynamic> m) {
  final date = m['date'];
  if (date is! String || !_dateRe.hasMatch(date)) return null;
  final kind = m['kind'];
  if (kind is! String || !kCanteenKinds.contains(kind)) return null;
  final name = _text(m['name'], 80);
  final amount = _amount(m['amount']);
  if (name == null || amount == null) return null;
  final method = m['method'];
  return <String, Object?>{
    'date': date,
    'kind': kind,
    'name': name,
    'amount': amount,
    'method': (method is String && kCanteenMethods.contains(method)) ? method : 'cash',
  };
}

/// Parses and validates backup text. Throws [FormatException] when the text
/// is not a Meal Streak backup at all; individual bad rows are skipped and
/// counted in [BackupData.skipped].
BackupData decodeBackup(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text.trim());
  } on FormatException {
    throw const FormatException('This is not a valid backup.');
  }
  if (raw is! Map) {
    throw const FormatException('This is not a valid backup.');
  }
  final root = Map<String, dynamic>.from(raw);
  if (root['app'] != kBackupApp) {
    throw const FormatException('This backup is not from Meal Streak.');
  }
  final version = root['version'];
  if (version is! int || version < 1 || version > kBackupVersion) {
    throw const FormatException('Unsupported backup version.');
  }

  var skipped = 0;

  List<Map<String, Object?>> readList(
    String key,
    Map<String, Object?>? Function(Map<String, dynamic>) clean,
  ) {
    final v = root[key];
    if (v == null) return <Map<String, Object?>>[];
    if (v is! List) throw FormatException('Backup field "$key" is damaged.');
    final out = <Map<String, Object?>>[];
    for (final item in v) {
      if (item is Map) {
        final cleaned = clean(Map<String, dynamic>.from(item));
        if (cleaned == null) {
          skipped++;
        } else {
          out.add(cleaned);
        }
      } else {
        skipped++;
      }
    }
    return out;
  }

  final meals = readList('meals', _cleanMeal);
  final extras = readList('extra_meals', _cleanExtra);
  final canteen = readList('canteen_entries', _cleanCanteen);

  final prefs = <String, Object>{};
  final rawPrefs = root['prefs'];
  if (rawPrefs is Map) {
    rawPrefs.forEach((key, value) {
      if (key is! String || !kBackupPrefKeys.contains(key)) return;
      if (value is String || value is bool || value is int || value is double) {
        prefs[key] = value as Object;
      } else if (value is List) {
        prefs[key] = value.map((e) => e.toString()).toList();
      }
    });
  }

  DateTime? created;
  final c = root['created'];
  if (c is String) created = DateTime.tryParse(c);

  return BackupData(
    meals: meals,
    extras: extras,
    canteen: canteen,
    prefs: prefs,
    created: created,
    skipped: skipped,
  );
}
