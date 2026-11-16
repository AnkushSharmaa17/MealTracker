import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
import '../core/models.dart';
import '../core/settings_repository.dart';
import '../data/database_helper.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  NotificationService._init();

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'meal_channel_id',
      'Meal Reminders',
      channelDescription: 'Notifications for daily mess meals',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    ),
  );

  static const Map<String, String> _titles = {
    'Morning': 'Good Morning! ☀️',
    'Afternoon': 'Good Afternoon! 🍛',
    'Night': 'Good Night! 🌙',
  };

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final dynamic tzInfo = await FlutterTimezone.getLocalTimezone();
      final String currentTimeZone = tzInfo is String ? tzInfo : tzInfo.identifier;
      tz.setLocalLocation(tz.getLocation(currentTimeZone));
    } catch (e) {
      debugPrint('Timezone error: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  // ------------------------------------------------------------ scheduling

  bool _syncing = false;
  bool _syncAgain = false;

  /// Re-schedules every reminder from the current settings and today's data.
  ///
  /// Smart behaviour: if a meal is already marked as eaten today, both its
  /// reminder and its "you haven't marked" follow-up start from tomorrow, so
  /// you are never nagged about something you already did.
  Future<void> syncReminders() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _syncOnce();
      } while (_syncAgain);
    } catch (e) {
      debugPrint('Reminder sync error: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    final settings = await SettingsRepository.load();
    var today = DayMeals.empty;
    try {
      today = await DatabaseHelper.instance.getDay(dateKey(DateTime.now()));
    } catch (e) {
      debugPrint('Could not read today meals for reminders: $e');
    }

    for (var i = 0; i < kMealTypes.length; i++) {
      final type = kMealTypes[i];
      final minutes = settings.minutesOf(type);
      final eatenToday = today.of(type).eaten;

      await _scheduleNotification(
        minutes ~/ 60,
        minutes % 60,
        1 + i,
        _titles[type] ?? 'Meal time',
        'Time for $type Mess Diet. Have you eaten?',
        skipToday: eatenToday,
      );

      final follow = (minutes + 15) % 1440;
      await _scheduleNotification(
        follow ~/ 60,
        follow % 60,
        101 + i,
        'Reminder! ⏰',
        'You haven\'t marked your $type diet yet.',
        skipToday: eatenToday,
      );
    }
  }

  // Kept for compatibility with older call sites.
  Future<void> scheduleDailyNotifications() => syncReminders();
  Future<void> scheduleEscalationNotifications() => syncReminders();

  Future<void> _scheduleNotification(
    int hour,
    int minute,
    int id,
    String title,
    String body, {
    bool skipToday = false,
  }) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    final when = _nextInstanceOfTime(hour, minute, skipToday: skipToday);
    try {
      await _zoned(id, title, body, when, AndroidScheduleMode.exactAllowWhileIdle);
    } catch (e) {
      // Exact alarms can be refused by the OS; fall back to an inexact one
      // instead of losing the reminder completely.
      debugPrint('Exact schedule failed for #$id ($e), using inexact.');
      try {
        await _zoned(
            id, title, body, when, AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e2) {
        debugPrint('Inexact schedule failed for #$id: $e2');
      }
    }
  }

  Future<void> _zoned(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    AndroidScheduleMode mode,
  ) {
    return flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute,
      {bool skipToday = false}) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (skipToday || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  // ------------------------------------------------------------- instant

  Future<void> showTestNotification() async {
    await flutterLocalNotificationsPlugin.show(
      0,
      'Test Notification 🔔',
      'Your notification system is working perfectly!',
      _details,
    );
  }

  Future<void> showBillNotification(int amount) async {
    await flutterLocalNotificationsPlugin.show(
      amount,
      'Mess Bill Alert 🚨',
      'Your mess bill has exceeded ₹$amount!',
      _details,
    );
  }

  /// Canteen budget alert: 80% used (over = false) or budget crossed.
  Future<void> showCanteenBudgetNotification({
    required int percent,
    required bool over,
  }) async {
    await flutterLocalNotificationsPlugin.show(
      over ? 9002 : 9001,
      over ? 'Canteen budget crossed 🚨' : 'Canteen budget alert ⚠️',
      over
          ? 'You have gone over your monthly canteen budget.'
          : 'You have used $percent% of your monthly canteen budget.',
      _details,
    );
  }

  Future<void> showSmartWarning(String mealType, String message) async {
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Attention! ⚠️',
      message,
      _details,
    );
  }
}
