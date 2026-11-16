# Meal Streak

Offline mess-meal tracker: mark Morning / Afternoon / Night meals, log extra
cravings, keep a daily streak and see your monthly mess bill. Everything is
stored locally (SQLite + SharedPreferences). No account, no internet.

## Run

```bash
flutter pub get
flutter run
flutter test        # unit tests for billing / streak / formatting logic
```

## Project layout

```
lib/
  main.dart                    app bootstrap, bottom navigation, lifecycle
  core/
    models.dart                pure data models (DayMeals, ExtraMeal, AppSettings)
    billing.dart               ALL bill/statistics/streak logic (pure Dart, unit-tested)
    format.dart                ₹ formatting (Indian grouping), date keys, parsing
    settings_repository.dart   reads SharedPreferences into AppSettings
    app_theme.dart             light/dark palette (AppColors) + ThemeData
    constants.dart             brand colours, meal metadata, skip reasons
    notifiers.dart             tiny app-wide ValueNotifiers
  data/database_helper.dart    SQLite (schema v5, migrations, queries)
  services/notification_service.dart   smart reminders
  widgets/                     shared UI (cards, skeletons, extra sheet, bill sheet)
  screens/                     home, history, stats (insights), settings
test/billing_test.dart
```

## How billing works

* Eaten meal -> charged at the meal rate (monthly fee is spread over every meal of
  the month, or a per-meal rate; rates can be the same or different per meal).
* **Fixed meals** are charged on every elapsed day even when skipped.
* A meal is "missed" only after its reminder time has passed, and only from the
  first day you logged something.
* Extras are added on top.

## Database

Version 5 adds a unique index on `(date, meal_type)` (old duplicate rows are
cleaned automatically on upgrade) and a date index on extras. Existing data and
preference keys are fully preserved.
