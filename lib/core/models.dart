// Pure-Dart data models (no Flutter imports).

const List<String> kMealTypes = ['Morning', 'Afternoon', 'Night'];

class MealEntry {
  final bool eaten;
  final String? reason;
  const MealEntry({this.eaten = false, this.reason});
  static const MealEntry empty = MealEntry();
}

/// The three meals of a single day.
class DayMeals {
  final MealEntry morning;
  final MealEntry afternoon;
  final MealEntry night;

  const DayMeals({
    this.morning = MealEntry.empty,
    this.afternoon = MealEntry.empty,
    this.night = MealEntry.empty,
  });

  static const DayMeals empty = DayMeals();

  MealEntry of(String type) {
    switch (type) {
      case 'Morning':
        return morning;
      case 'Afternoon':
        return afternoon;
      default:
        return night;
    }
  }

  DayMeals withMeal(String type, MealEntry entry) {
    switch (type) {
      case 'Morning':
        return DayMeals(morning: entry, afternoon: afternoon, night: night);
      case 'Afternoon':
        return DayMeals(morning: morning, afternoon: entry, night: night);
      case 'Night':
        return DayMeals(morning: morning, afternoon: afternoon, night: entry);
      default:
        return this;
    }
  }

  int get eatenCount =>
      (morning.eaten ? 1 : 0) + (afternoon.eaten ? 1 : 0) + (night.eaten ? 1 : 0);

  bool get isPerfect => eatenCount == 3;
}

class ExtraMeal {
  final int id;
  final String date;
  final String mealType;
  final String name;
  final double amount;

  const ExtraMeal({
    required this.id,
    required this.date,
    required this.mealType,
    required this.name,
    required this.amount,
  });

  factory ExtraMeal.fromMap(Map<String, Object?> m) {
    return ExtraMeal(
      id: (m['id'] as num).toInt(),
      date: m['date'] as String,
      mealType: (m['meal_type'] as String?) ?? 'General',
      name: (m['name'] as String?) ?? '',
      amount: (m['amount'] as num).toDouble(),
    );
  }
}

/// A one-tap "Instamart style" suggestion for extra cravings.
class QuickPick {
  final String name;
  final double amount;
  final int count;
  const QuickPick(this.name, this.amount, {this.count = 0});
}

const List<QuickPick> kDefaultQuickPicks = [
  QuickPick('Chai', 15),
  QuickPick('Coffee', 25),
  QuickPick('Samosa', 15),
  QuickPick('Maggi', 40),
  QuickPick('Cold Drink', 20),
  QuickPick('Sandwich', 40),
];

/// Your own frequent items first, then defaults, without duplicates.
List<QuickPick> mergeQuickPicks(List<QuickPick> mine, {int limit = 8}) {
  final out = <QuickPick>[];
  final seen = <String>{};
  for (final p in [...mine, ...kDefaultQuickPicks]) {
    if (out.length >= limit) break;
    if (seen.add(p.name.trim().toLowerCase())) out.add(p);
  }
  return out;
}

/// Which meal an "extra" most likely belongs to at a given hour.
String mealTypeForHour(int hour) {
  if (hour < 11) return 'Morning';
  if (hour < 17) return 'Afternoon';
  return 'Night';
}

/// All user settings that affect billing and reminders.
class AppSettings {
  final String rateType; // 'monthly' | 'per_meal'
  final double monthlyFee;
  final bool perMealSame;
  final double rateSame;
  final double rateMorning;
  final double rateAfternoon;
  final double rateNight;
  final Set<String> fixedMeals;
  final int morningMin; // minutes after midnight
  final int afternoonMin;
  final int nightMin;

  const AppSettings({
    this.rateType = 'monthly',
    this.monthlyFee = 3000,
    this.perMealSame = true,
    this.rateSame = 40,
    this.rateMorning = 40,
    this.rateAfternoon = 40,
    this.rateNight = 40,
    this.fixedMeals = const <String>{},
    this.morningMin = 9 * 60,
    this.afternoonMin = 14 * 60,
    this.nightMin = 21 * 60,
  });

  bool isFixed(String type) => fixedMeals.contains(type);

  int minutesOf(String type) {
    switch (type) {
      case 'Morning':
        return morningMin;
      case 'Afternoon':
        return afternoonMin;
      default:
        return nightMin;
    }
  }
}
