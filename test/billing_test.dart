import 'package:flutter_test/flutter_test.dart';
import 'package:meal_streak/core/billing.dart';
import 'package:meal_streak/core/format.dart';
import 'package:meal_streak/core/models.dart';

const DayMeals _all = DayMeals(
  morning: MealEntry(eaten: true),
  afternoon: MealEntry(eaten: true),
  night: MealEntry(eaten: true),
);

MonthReport _report({
  required Map<String, DayMeals> days,
  required AppSettings settings,
  required DateTime now,
  List<ExtraMeal> extras = const <ExtraMeal>[],
  String? trackingStart = '2026-11-01',
}) {
  return computeMonthReport(
    year: 2026,
    month: 11,
    days: days,
    extras: extras,
    settings: settings,
    now: now,
    trackingStart: trackingStart,
  );
}

void main() {
  group('format helpers', () {
    test('formatRupees uses Indian grouping', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(999), '₹999');
      expect(formatRupees(1000), '₹1,000');
      expect(formatRupees(100000), '₹1,00,000');
      expect(formatRupees(1234567), '₹12,34,567');
      expect(formatRupees(-1500), '-₹1,500');
      expect(formatRupees(2500, symbol: false), '2,500');
      expect(formatRupees(double.nan), '₹0');
    });

    test('formatAmount trims needless decimals', () {
      expect(formatAmount(40), '40');
      expect(formatAmount(10.5), '10.5');
      expect(formatAmount(33.333), '33.33');
    });

    test('parseAmount rejects garbage', () {
      expect(parseAmount('12.5'), 12.5);
      expect(parseAmount(' 40 '), 40);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount(''), isNull);
      expect(parseAmount('1.2.3'), isNull);
    });

    test('formatClock and dateKey', () {
      expect(formatClock(540), '09:00 AM');
      expect(formatClock(0), '12:00 AM');
      expect(formatClock(13 * 60 + 5), '01:05 PM');
      expect(dateKey(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });

  group('rates', () {
    test('monthly fee is spread over every meal of the month', () {
      const s = AppSettings(rateType: 'monthly', monthlyFee: 3000);
      final r = MealRates.forMonth(s, 2026, 11); // 30 days -> 90 meals
      expect(r.morning, closeTo(3000 / 90, 0.0001));
    });

    test('per meal: same vs separate rates', () {
      const same = AppSettings(rateType: 'per_meal', rateSame: 40);
      expect(MealRates.forMonth(same, 2026, 11).night, 40);

      const separate = AppSettings(
        rateType: 'per_meal',
        perMealSame: false,
        rateMorning: 30,
        rateAfternoon: 50,
        rateNight: 45,
      );
      final r = MealRates.forMonth(separate, 2026, 11);
      expect(r.morning, 30);
      expect(r.afternoon, 50);
      expect(r.night, 45);
    });
  });

  group('month report', () {
    const perMeal = AppSettings(rateType: 'per_meal', rateSame: 40);

    test('fixed meals are charged even on days with no database row', () {
      final report = _report(
        days: const {},
        settings: const AppSettings(
          rateType: 'per_meal',
          rateSame: 40,
          fixedMeals: {'Morning'},
        ),
        now: DateTime(2026, 11, 3, 15, 0),
      );
      expect(report.bill.fixedSkipped('Morning'), 3);
      expect(report.bill.fixedSkippedCost, 120);
      expect(report.bill.eatenCost, 0);
    });

    test('eaten + fixed + missed + saved add up', () {
      final report = _report(
        days: const {
          '2026-11-01': DayMeals(
            morning: MealEntry(eaten: true),
            afternoon: MealEntry(eaten: true),
          ),
        },
        settings: const AppSettings(
          rateType: 'per_meal',
          rateSame: 40,
          fixedMeals: {'Morning'},
        ),
        now: DateTime(2026, 11, 2, 23, 0),
      );
      expect(report.bill.eatenCost, 80);
      expect(report.bill.fixedSkippedCost, 40); // day 2 morning
      expect(report.bill.messTotal, 120);
      expect(report.eaten, 2);
      expect(report.passedSlots, 6);
      expect(report.missed, 4);
      expect(report.saved, 120); // 4 misses, but fixed morning saves nothing
      expect(report.successPercent, 33);
      expect(report.perfectDays, 0);
    });

    test('a meal is not "missed" before its reminder time', () {
      final early = _report(
        days: const {},
        settings: perMeal,
        now: DateTime(2026, 11, 1, 8, 0),
      );
      expect(early.passedSlots, 0);
      expect(early.missed, 0);

      final later = _report(
        days: const {},
        settings: perMeal,
        now: DateTime(2026, 11, 1, 9, 30),
      );
      expect(later.passedSlots, 1);
      expect(later.missed, 1);
    });

    test('nothing is missed before the first logged day (fresh install)', () {
      final report = _report(
        days: const {},
        settings: perMeal,
        now: DateTime(2026, 11, 20, 22, 0),
        trackingStart: null,
      );
      expect(report.missed, 0);
      expect(report.passedSlots, 0);
    });

    test('extras are added to the total and grouped by name', () {
      final extras = [
        const ExtraMeal(id: 1, date: '2026-11-01', mealType: 'Morning', name: 'Chai', amount: 10),
        const ExtraMeal(id: 2, date: '2026-11-02', mealType: 'Night', name: 'chai', amount: 10),
        const ExtraMeal(id: 3, date: '2026-11-02', mealType: 'Night', name: 'Maggi', amount: 40),
      ];
      final report = _report(
        days: const {},
        settings: perMeal,
        now: DateTime(2026, 11, 2, 23, 0),
        extras: extras,
      );
      expect(report.bill.extraTotal, 60);
      expect(report.extraByMealType('Night'), 50);

      final groups = groupExtras(extras);
      expect(groups.first.name, 'Maggi');
      expect(groups.first.total, 40);
      expect(groups[1].count, 2);
      expect(groups[1].total, 20);
    });

    test('projection extrapolates the current pace', () {
      final days = <String, DayMeals>{
        for (var d = 1; d <= 10; d++) dateKey(DateTime(2026, 11, d)): _all,
      };
      final report = _report(
        days: days,
        settings: perMeal,
        now: DateTime(2026, 11, 10, 23, 0),
      );
      expect(report.bill.total, 1200); // 30 meals x 40
      expect(report.perfectDays, 10);
      expect(report.projectedTotal(DateTime(2026, 11, 10, 23, 0)), 3600);
      expect(report.projectedTotal(DateTime(2026, 12, 1)), isNull);
    });

    test('past months are fully charged, future months not at all', () {
      final past = computeMonthReport(
        year: 2026,
        month: 9,
        days: const {},
        extras: const <ExtraMeal>[],
        settings: const AppSettings(
          rateType: 'per_meal',
          rateSame: 40,
          fixedMeals: {'Night'},
        ),
        now: DateTime(2026, 11, 15),
        trackingStart: '2026-09-01',
      );
      expect(past.bill.fixedSkipped('Night'), 30); // all of September

      final future = computeMonthReport(
        year: 2027,
        month: 1,
        days: const {},
        extras: const <ExtraMeal>[],
        settings: const AppSettings(fixedMeals: {'Night'}),
        now: DateTime(2026, 11, 15),
        trackingStart: '2026-09-01',
      );
      expect(future.bill.total, 0);
      expect(future.missed, 0);
    });
  });

  group('streak', () {
    final perfect = {'2026-11-01', '2026-11-02', '2026-11-03', '2026-11-05'};

    test('counts consecutive perfect days ending today', () {
      final s = computeStreak(perfect, DateTime(2026, 11, 3, 10));
      expect(s.current, 3);
      expect(s.best, 3);
    });

    test('today in progress does not break the streak', () {
      final s = computeStreak(perfect, DateTime(2026, 11, 4, 8));
      expect(s.current, 3);
    });

    test('a gap resets the current streak but keeps the best', () {
      final s = computeStreak(perfect, DateTime(2026, 11, 5, 22));
      expect(s.current, 1);
      expect(s.best, 3);

      final later = computeStreak(perfect, DateTime(2026, 11, 7));
      expect(later.current, 0);
      expect(later.best, 3);
    });

    test('works across month boundaries', () {
      final s = computeStreak({'2026-10-31', '2026-11-01'}, DateTime(2026, 11, 1));
      expect(s.current, 2);
    });

    test('empty history', () {
      final s = computeStreak(<String>{}, DateTime(2026, 11, 1));
      expect(s.current, 0);
      expect(s.best, 0);
    });
  });

  group('models', () {
    test('DayMeals.withMeal does not mutate and counts correctly', () {
      final a = DayMeals.empty.withMeal('Morning', const MealEntry(eaten: true));
      expect(DayMeals.empty.eatenCount, 0);
      expect(a.eatenCount, 1);
      expect(a.of('Morning').eaten, isTrue);
      expect(a.of('Night').eaten, isFalse);
      expect(a.withMeal('Unknown', const MealEntry(eaten: true)).eatenCount, 1);
      expect(_all.isPerfect, isTrue);
    });

    test('mergeQuickPicks puts your items first without duplicates', () {
      final picks = mergeQuickPicks(
        const [QuickPick('chai', 12, count: 5)],
        limit: 3,
      );
      expect(picks.length, 3);
      expect(picks.first.amount, 12);
      expect(picks.where((p) => p.name.toLowerCase() == 'chai').length, 1);
    });

    test('mealTypeForHour', () {
      expect(mealTypeForHour(8), 'Morning');
      expect(mealTypeForHour(13), 'Afternoon');
      expect(mealTypeForHour(20), 'Night');
    });
  });
}
