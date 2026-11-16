import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Reads every setting from SharedPreferences in one place.
/// Keys are identical to the previous version, so existing user data is kept.
class SettingsRepository {
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    double d(String key, double fallback) =>
        double.tryParse(prefs.getString(key) ?? '') ?? fallback;
    int i(String key, int fallback) => prefs.getInt(key) ?? fallback;

    return AppSettings(
      rateType: prefs.getString('rate_type') ?? 'monthly',
      monthlyFee: d('monthly_fee', 3000),
      perMealSame: prefs.getBool('per_meal_same') ?? true,
      rateSame: d('rate_same', 40),
      rateMorning: d('rate_morning', 40),
      rateAfternoon: d('rate_afternoon', 40),
      rateNight: d('rate_night', 40),
      fixedMeals: (prefs.getStringList('fixed_meals') ?? const <String>[]).toSet(),
      morningMin: i('time_morning_h', 9) * 60 + i('time_morning_m', 0),
      afternoonMin: i('time_afternoon_h', 14) * 60 + i('time_afternoon_m', 0),
      nightMin: i('time_night_h', 21) * 60 + i('time_night_m', 0),
    );
  }
}
