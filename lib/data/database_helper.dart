import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../core/canteen.dart';
import '../core/format.dart';
import '../core/models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Future<Database>? _opening;

  DatabaseHelper._init();

  /// Opens the database once, even if several screens ask at the same time.
  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final pending = _opening;
    if (pending != null) return pending;

    final future = _initDB('meal_streak.db');
    _opening = future;
    try {
      final db = await future;
      _database = db;
      return db;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE meals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  meal_type TEXT NOT NULL,
  is_eaten INTEGER NOT NULL,
  skip_reason TEXT
)
''');
    await db.execute('''
CREATE TABLE extra_meals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  meal_type TEXT NOT NULL DEFAULT 'General',
  name TEXT NOT NULL,
  amount REAL NOT NULL
)
''');
    await _createIndexes(db);
    await _createCanteenTable(db);
  }

  Future<void> _createCanteenTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS canteen_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  amount REAL NOT NULL,
  method TEXT NOT NULL DEFAULT 'cash'
)
''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_canteen_date ON canteen_entries(date)');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_meals_date_type ON meals(date, meal_type)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_extra_date ON extra_meals(date)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE meals ADD COLUMN skip_reason TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
CREATE TABLE extra_meals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  name TEXT NOT NULL,
  amount REAL NOT NULL
)
''');
    }
    if (oldVersion < 4) {
      await db.execute(
          "ALTER TABLE extra_meals ADD COLUMN meal_type TEXT DEFAULT 'General'");
    }
    if (oldVersion < 5) {
      // Remove accidental duplicates (keep the newest row), then enforce
      // "one row per meal per day" and speed up date lookups.
      await db.execute(
          'DELETE FROM meals WHERE id NOT IN (SELECT MAX(id) FROM meals GROUP BY date, meal_type)');
      await _createIndexes(db);
    }
    if (oldVersion < 6) {
      await _createCanteenTable(db);
    }
  }

  // ---------------------------------------------------------------- meals

  /// Insert-or-update in a single statement (backed by the unique index).
  Future<void> setMealStatus(
    String date,
    String mealType,
    bool isEaten, {
    String? reason,
  }) async {
    final db = await database;
    await db.insert(
      'meals',
      {
        'date': date,
        'meal_type': mealType,
        'is_eaten': isEaten ? 1 : 0,
        'skip_reason': isEaten ? null : reason,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DayMeals> getDay(String date) async {
    final db = await database;
    final rows = await db.query('meals', where: 'date = ?', whereArgs: [date]);
    var day = DayMeals.empty;
    for (final r in rows) {
      day = day.withMeal(r['meal_type'] as String, _entryOf(r));
    }
    return day;
  }

  /// All days between [startDate] and [endDate] (inclusive, "yyyy-MM-dd").
  Future<Map<String, DayMeals>> getRange(String startDate, String endDate) async {
    final db = await database;
    final rows = await db.query(
      'meals',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDate, endDate],
    );
    final map = <String, DayMeals>{};
    for (final r in rows) {
      final date = r['date'] as String;
      map[date] = (map[date] ?? DayMeals.empty)
          .withMeal(r['meal_type'] as String, _entryOf(r));
    }
    return map;
  }

  Future<Map<String, DayMeals>> getMonth(int year, int month) {
    return getRange(
      dateKey(DateTime(year, month, 1)),
      dateKey(DateTime(year, month, 31)),
    );
  }

  MealEntry _entryOf(Map<String, Object?> row) {
    return MealEntry(
      eaten: row['is_eaten'] == 1,
      reason: row['skip_reason'] as String?,
    );
  }

  /// Dates on which all three meals were eaten (for streaks).
  Future<Set<String>> getPerfectDates() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT date FROM meals GROUP BY date HAVING SUM(is_eaten) >= 3');
    return rows.map((r) => r['date'] as String).toSet();
  }

  /// First date anything was logged (null on a fresh install).
  Future<String?> getFirstTrackedDate() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT MIN(date) AS d FROM meals');
    if (rows.isEmpty) return null;
    return rows.first['d'] as String?;
  }

  Future<int> countMealRows() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM meals');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  // --------------------------------------------------------------- extras

  Future<int> addExtraMeal(
    String date,
    String mealType,
    String name,
    double amount,
  ) async {
    final db = await database;
    return db.insert('extra_meals', {
      'date': date,
      'meal_type': mealType,
      'name': name,
      'amount': amount,
    });
  }

  Future<void> deleteExtraMeal(int id) async {
    final db = await database;
    await db.delete('extra_meals', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ExtraMeal>> getExtrasForDate(String date) async {
    final db = await database;
    final rows = await db.query(
      'extra_meals',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return rows.map(ExtraMeal.fromMap).toList();
  }

  Future<List<ExtraMeal>> getMonthExtras(int year, int month) async {
    final db = await database;
    final rows = await db.query(
      'extra_meals',
      where: 'date >= ? AND date <= ?',
      whereArgs: [
        dateKey(DateTime(year, month, 1)),
        dateKey(DateTime(year, month, 31)),
      ],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(ExtraMeal.fromMap).toList();
  }

  /// Your most-ordered extras with their latest price (for one-tap add).
  Future<List<QuickPick>> getFrequentExtras({int limit = 8}) async {
    final db = await database;
    final rows = await db.rawQuery('''
SELECT (SELECT e3.name FROM extra_meals e3
         WHERE LOWER(e3.name) = LOWER(e.name)
         ORDER BY e3.id DESC LIMIT 1) AS name,
       COUNT(*) AS cnt,
       (SELECT e2.amount FROM extra_meals e2
         WHERE LOWER(e2.name) = LOWER(e.name)
         ORDER BY e2.id DESC LIMIT 1) AS last_amount
FROM extra_meals e
GROUP BY LOWER(e.name)
ORDER BY cnt DESC, MAX(e.id) DESC
LIMIT ?
''', [limit]);
    final picks = <QuickPick>[];
    for (final r in rows) {
      final name = r['name'] as String?;
      final amount = (r['last_amount'] as num?)?.toDouble();
      if (name == null || name.trim().isEmpty || amount == null) continue;
      picks.add(QuickPick(name, amount, count: (r['cnt'] as num).toInt()));
    }
    return picks;
  }

  // -------------------------------------------------------------- canteen

  Future<int> addCanteenEntry({
    required String date,
    required String kind,
    required String name,
    required double amount,
    required String method,
  }) async {
    final db = await database;
    return db.insert('canteen_entries', {
      'date': date,
      'kind': kind,
      'name': name,
      'amount': amount,
      'method': method,
    });
  }

  Future<void> deleteCanteenEntry(int id) async {
    final db = await database;
    await db.delete('canteen_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<CanteenEntry>> getCanteenMonth(int year, int month) async {
    final db = await database;
    final rows = await db.query(
      'canteen_entries',
      where: 'date >= ? AND date <= ?',
      whereArgs: [
        dateKey(DateTime(year, month, 1)),
        dateKey(DateTime(year, month, 31)),
      ],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(CanteenEntry.fromMap).toList();
  }

  /// All-time udhaar still to be paid (credit minus settlements).
  Future<double> getCanteenOutstanding() async {
    final db = await database;
    final rows = await db.rawQuery(
        "SELECT SUM(CASE kind WHEN 'credit' THEN amount WHEN 'settle' THEN -amount ELSE 0 END) AS bal FROM canteen_entries");
    if (rows.isEmpty) return 0;
    return (rows.first['bal'] as num?)?.toDouble() ?? 0;
  }

  Future<List<QuickPick>> getCanteenFrequent({int limit = 8}) async {
    final db = await database;
    final rows = await db.rawQuery('''
SELECT (SELECT e3.name FROM canteen_entries e3
         WHERE LOWER(e3.name) = LOWER(e.name) AND e3.kind != 'settle'
         ORDER BY e3.id DESC LIMIT 1) AS name,
       COUNT(*) AS cnt,
       (SELECT e2.amount FROM canteen_entries e2
         WHERE LOWER(e2.name) = LOWER(e.name) AND e2.kind != 'settle'
         ORDER BY e2.id DESC LIMIT 1) AS last_amount
FROM canteen_entries e
WHERE e.kind != 'settle'
GROUP BY LOWER(e.name)
ORDER BY cnt DESC, MAX(e.id) DESC
LIMIT ?
''', [limit]);
    final picks = <QuickPick>[];
    for (final r in rows) {
      final name = r['name'] as String?;
      final amount = (r['last_amount'] as num?)?.toDouble();
      if (name == null || name.trim().isEmpty || amount == null) continue;
      picks.add(QuickPick(name, amount, count: (r['cnt'] as num).toInt()));
    }
    return picks;
  }

  // --------------------------------------------------------------- backup

  Future<Map<String, List<Map<String, Object?>>>> exportTables() async {
    final db = await database;
    final meals = await db.query('meals',
        columns: ['date', 'meal_type', 'is_eaten', 'skip_reason'],
        orderBy: 'date ASC, meal_type ASC');
    final extras = await db.query('extra_meals',
        columns: ['date', 'meal_type', 'name', 'amount'], orderBy: 'id ASC');
    final canteen = await db.query('canteen_entries',
        columns: ['date', 'kind', 'name', 'amount', 'method'],
        orderBy: 'id ASC');
    return {
      'meals': meals.map((r) => Map<String, Object?>.from(r)).toList(),
      'extra_meals': extras.map((r) => Map<String, Object?>.from(r)).toList(),
      'canteen_entries': canteen.map((r) => Map<String, Object?>.from(r)).toList(),
    };
  }

  /// Replaces EVERYTHING in one transaction: either all rows are restored or
  /// (on any error) nothing changes.
  Future<void> replaceAllData({
    required List<Map<String, Object?>> meals,
    required List<Map<String, Object?>> extras,
    required List<Map<String, Object?>> canteen,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('meals');
      await txn.delete('extra_meals');
      await txn.delete('canteen_entries');
      final batch = txn.batch();
      for (final m in meals) {
        batch.insert('meals', m, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final m in extras) {
        batch.insert('extra_meals', m);
      }
      for (final m in canteen) {
        batch.insert('canteen_entries', m);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> wipeAll() {
    return replaceAllData(
      meals: const <Map<String, Object?>>[],
      extras: const <Map<String, Object?>>[],
      canteen: const <Map<String, Object?>>[],
    );
  }
}
