// All money / statistics logic lives here as pure functions (no Flutter, no
// database) so the exact same numbers are shown on Home, History and Insights
// and everything can be unit-tested.

import 'dart:math' as math;

import 'format.dart';
import 'models.dart';

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Price of one meal of each type for a given month.
class MealRates {
  final double morning;
  final double afternoon;
  final double night;
  const MealRates(this.morning, this.afternoon, this.night);

  double of(String type) {
    switch (type) {
      case 'Morning':
        return morning;
      case 'Afternoon':
        return afternoon;
      default:
        return night;
    }
  }

  factory MealRates.forMonth(AppSettings s, int year, int month) {
    if (s.rateType == 'monthly') {
      final r = s.monthlyFee / (daysInMonth(year, month) * 3);
      return MealRates(r, r, r);
    }
    if (s.perMealSame) {
      return MealRates(s.rateSame, s.rateSame, s.rateSame);
    }
    return MealRates(s.rateMorning, s.rateAfternoon, s.rateNight);
  }
}

class BillSummary {
  final MealRates rates;
  final Map<String, int> eatenCount;
  final Map<String, int> fixedSkippedCount;
  final double extraTotal;

  const BillSummary({
    required this.rates,
    required this.eatenCount,
    required this.fixedSkippedCount,
    required this.extraTotal,
  });

  int eaten(String type) => eatenCount[type] ?? 0;
  int fixedSkipped(String type) => fixedSkippedCount[type] ?? 0;

  double get eatenCost {
    var s = 0.0;
    for (final t in kMealTypes) {
      s += eaten(t) * rates.of(t);
    }
    return s;
  }

  double get fixedSkippedCost {
    var s = 0.0;
    for (final t in kMealTypes) {
      s += fixedSkipped(t) * rates.of(t);
    }
    return s;
  }

  double get messTotal => eatenCost + fixedSkippedCost;
  double get total => messTotal + extraTotal;
}

class MonthReport {
  final int year;
  final int month;
  final BillSummary bill;
  final List<ExtraMeal> extras;

  /// Every meal marked as eaten this month.
  final int eaten;

  /// Meals whose time has already passed and were not eaten.
  final int missed;

  /// Meals whose time has already passed (tracked days only).
  final int passedSlots;
  final int perfectDays;

  /// Money not spent on meals that were skipped (and are not "fixed").
  final double saved;
  final String? bestDate;
  final int bestCount;
  final Map<String, int> skipReasons;
  final Map<String, int> eatenByMeal;
  final Map<String, int> passedByMeal;
  final Map<String, int> missedByMeal;

  const MonthReport({
    required this.year,
    required this.month,
    required this.bill,
    required this.extras,
    required this.eaten,
    required this.missed,
    required this.passedSlots,
    required this.perfectDays,
    required this.saved,
    required this.bestDate,
    required this.bestCount,
    required this.skipReasons,
    required this.eatenByMeal,
    required this.passedByMeal,
    required this.missedByMeal,
  });

  int get totalSlots => daysInMonth(year, month) * 3;

  /// Percentage of already-due meals that were eaten.
  int get successPercent {
    if (passedSlots == 0) return 0;
    return (((passedSlots - missed) / passedSlots) * 100).round();
  }

  /// Rough month-end bill if the current pace continues (current month only).
  double? projectedTotal(DateTime now) {
    if (now.year != year || now.month != month) return null;
    if (now.day < 3) return null;
    return bill.total / now.day * daysInMonth(year, month);
  }

  double extraByMealType(String type) {
    var s = 0.0;
    for (final e in extras) {
      if (e.mealType == type) s += e.amount;
    }
    return s;
  }
}

int _chargeableDays(int year, int month, DateTime now) {
  if (year == now.year && month == now.month) return now.day;
  final monthIndex = year * 12 + month;
  final nowIndex = now.year * 12 + now.month;
  return monthIndex < nowIndex ? daysInMonth(year, month) : 0;
}

/// Computes bill + statistics for one month in a single pass.
///
/// * Eaten meals are charged at the meal rate.
/// * "Fixed" meals are charged on EVERY elapsed day even if there is no
///   database row for that day (previous versions missed those days).
/// * A meal counts as "missed" only after its reminder time has passed, and
///   only for days on/after [trackingStart] (first day anything was logged),
///   so a fresh install does not start with a pile of fake misses.
MonthReport computeMonthReport({
  required int year,
  required int month,
  required Map<String, DayMeals> days,
  required List<ExtraMeal> extras,
  required AppSettings settings,
  required DateTime now,
  String? trackingStart,
}) {
  final rates = MealRates.forMonth(settings, year, month);
  final chargeable = _chargeableDays(year, month, now);
  final isCurrent = year == now.year && month == now.month;
  final nowMinutes = now.hour * 60 + now.minute;

  var maxRecorded = 0;
  for (final k in days.keys) {
    final d = parseDateKey(k);
    if (d != null && d.year == year && d.month == month && d.day > maxRecorded) {
      maxRecorded = d.day;
    }
  }
  final lastDay = math.max(chargeable, maxRecorded);

  final eatenCount = <String, int>{for (final t in kMealTypes) t: 0};
  final fixedSkipped = <String, int>{for (final t in kMealTypes) t: 0};
  final eatenByMeal = <String, int>{for (final t in kMealTypes) t: 0};
  final passedByMeal = <String, int>{for (final t in kMealTypes) t: 0};
  final missedByMeal = <String, int>{for (final t in kMealTypes) t: 0};
  final reasons = <String, int>{};

  var eaten = 0;
  var missed = 0;
  var passedSlots = 0;
  var perfectDays = 0;
  var saved = 0.0;
  String? bestDate;
  var bestCount = 0;

  for (var d = 1; d <= lastDay; d++) {
    final key = dateKey(DateTime(year, month, d));
    final day = days[key] ?? DayMeals.empty;
    final tracked = trackingStart != null && key.compareTo(trackingStart) >= 0;

    for (final type in kMealTypes) {
      final entry = day.of(type);

      bool passed;
      if (isCurrent) {
        passed = d < now.day ||
            (d == now.day && settings.minutesOf(type) <= nowMinutes);
      } else {
        passed = d <= chargeable;
      }
      final counted = passed && tracked;

      if (entry.eaten) {
        eaten++;
        eatenCount[type] = eatenCount[type]! + 1;
        eatenByMeal[type] = eatenByMeal[type]! + 1;
      } else {
        if (settings.isFixed(type) && d <= chargeable) {
          fixedSkipped[type] = fixedSkipped[type]! + 1;
        }
        if (entry.reason != null) {
          reasons[entry.reason!] = (reasons[entry.reason!] ?? 0) + 1;
        }
        if (counted) {
          missed++;
          missedByMeal[type] = missedByMeal[type]! + 1;
          if (!settings.isFixed(type)) saved += rates.of(type);
        }
      }

      if (counted) {
        passedSlots++;
        passedByMeal[type] = passedByMeal[type]! + 1;
      }
    }

    final c = day.eatenCount;
    if (c == 3) perfectDays++;
    if (c > 0 && c >= bestCount) {
      bestCount = c;
      bestDate = key;
    }
  }

  var extraTotal = 0.0;
  for (final e in extras) {
    extraTotal += e.amount;
  }

  return MonthReport(
    year: year,
    month: month,
    bill: BillSummary(
      rates: rates,
      eatenCount: eatenCount,
      fixedSkippedCount: fixedSkipped,
      extraTotal: extraTotal,
    ),
    extras: extras,
    eaten: eaten,
    missed: missed,
    passedSlots: passedSlots,
    perfectDays: perfectDays,
    saved: saved,
    bestDate: bestDate,
    bestCount: bestCount,
    skipReasons: reasons,
    eatenByMeal: eatenByMeal,
    passedByMeal: passedByMeal,
    missedByMeal: missedByMeal,
  );
}

class StreakInfo {
  final int current;
  final int best;
  const StreakInfo(this.current, this.best);
}

/// A streak = consecutive "perfect" days (all 3 meals eaten).
/// Today does not break the streak while it is still in progress.
StreakInfo computeStreak(Set<String> perfectDates, DateTime today) {
  var cursor = DateTime.utc(today.year, today.month, today.day);
  if (!perfectDates.contains(dateKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var current = 0;
  while (perfectDates.contains(dateKey(cursor))) {
    current++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final sorted = perfectDates.toList()..sort();
  var best = 0;
  var run = 0;
  DateTime? prev;
  for (final k in sorted) {
    final d = parseDateKey(k);
    if (d == null) continue;
    final u = DateTime.utc(d.year, d.month, d.day);
    if (prev != null && u.difference(prev).inDays == 1) {
      run++;
    } else {
      run = 1;
    }
    if (run > best) best = run;
    prev = u;
  }
  return StreakInfo(current, math.max(best, current));
}

class ExtraGroup {
  final String name;
  final int count;
  final double total;
  const ExtraGroup(this.name, this.count, this.total);
}

/// Groups extras by item name (case-insensitive), biggest spend first.
List<ExtraGroup> groupExtras(List<ExtraMeal> extras, {int limit = 5}) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final e in extras) {
    final key = e.name.trim().toLowerCase();
    if (key.isEmpty) continue;
    totals[key] = (totals[key] ?? 0) + e.amount;
    counts[key] = (counts[key] ?? 0) + 1;
    names.putIfAbsent(key, () => e.name.trim());
  }
  final list = [
    for (final k in totals.keys) ExtraGroup(names[k]!, counts[k]!, totals[k]!),
  ];
  list.sort((a, b) => b.total.compareTo(a.total));
  return list.length > limit ? list.sublist(0, limit) : list;
}
