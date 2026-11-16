import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_theme.dart';
import 'core/constants.dart';
import 'core/notifiers.dart';
import 'screens/canteen_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/app_lock_service.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  // Start locked (before the first frame) when the PIN lock is enabled.
  try {
    appLockedNotifier.value = await AppLockService.instance.isEnabled();
  } catch (e) {
    debugPrint('Lock check error: $e');
  }

  runApp(const MealTrackerApp());

  // Do not block the first frame on notification set-up.
  unawaited(_bootstrapNotifications());
}

Future<void> _bootstrapNotifications() async {
  try {
    await NotificationService.instance.init();

    // Ask for permissions once on first launch. Afterwards the Settings
    // screen is the place to change them (no nagging on every start).
    final prefs = await SharedPreferences.getInstance();
    final alreadyPrompted = prefs.getBool('perm_prompted') ?? false;
    if (!alreadyPrompted) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
      await prefs.setBool('perm_prompted', true);
    }
    await NotificationService.instance.syncReminders();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }
}

void applyTheme(bool isDark) {
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
}

class MealTrackerApp extends StatelessWidget {
  const MealTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Meal Streak',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime? _pausedAt;

  /// The app locks again if it stayed in the background longer than this.
  static const Duration _lockAfter = Duration(seconds: 30);

  late final List<Widget> _screens = [
    const HomeScreen(),
    const HistoryScreen(),
    const StatsScreen(),
    const CanteenScreen(),
    SettingsScreen(onThemeChanged: applyTheme),
  ];

  static const List<String> _titles = [
    'Meal Streak',
    'History',
    'Insights',
    'Canteen',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for app updates after the first frame renders.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  /// Checks GitHub for a newer version and shows the update dialog if found.
  Future<void> _checkForUpdate() async {
    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(
        latestVersion: updateInfo['latestVersion']!,
        releaseNotes: updateInfo['releaseNotes']!,
        downloadUrl: updateInfo['downloadUrl']!,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the app (maybe after midnight): refresh dates, data and
  /// reminders.
  Future<void> _maybeLock() async {
    final paused = _pausedAt;
    _pausedAt = null;
    if (paused == null) return;
    if (DateTime.now().difference(paused) < _lockAfter) return;
    try {
      if (await AppLockService.instance.isEnabled()) {
        appLockedNotifier.value = true;
      }
    } catch (e) {
      debugPrint('Lock check error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_maybeLock());
      if (mounted) setState(() {});
      dbUpdateNotifier.value++;
      unawaited(NotificationService.instance.syncReminders());
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    if (h < 21) return 'Good Evening';
    return 'Good Night';
  }

  String _subtitle() {
    switch (_currentIndex) {
      case 0:
        return '${_greeting()} • ${DateFormat('EEE, d MMM').format(DateTime.now())}';
      case 1:
        return 'Monthly overview';
      case 2:
        return 'Your eating pattern';
      case 3:
        return 'Separate from your mess bill';
      default:
        return 'Personalize your app';
    }
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    tabIndexNotifier.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildScaffold(c),
          ValueListenableBuilder<bool>(
            valueListenable: appLockedNotifier,
            builder: (context, locked, child) =>
                locked ? const LockScreen() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildScaffold(AppColors c) {
    return PopScope(
      // Back button returns to Home first instead of closing the app.
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _selectTab(0);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          toolbarHeight: 66,
          titleSpacing: 20,
          centerTitle: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _titles[_currentIndex],
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
          actions: [
            ValueListenableBuilder<int>(
              valueListenable: streakNotifier,
              builder: (context, streak, child) =>
                  _StreakChip(streak: streak, onTap: () => _selectTab(2)),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.border, width: 0.5)),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            height: 66,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: _selectTab,
            backgroundColor: Colors.transparent,
            indicatorColor: tomatoRed.withValues(alpha: 0.12),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, size: 22),
                label: 'Home',
                selectedIcon:
                    Icon(Icons.home_rounded, color: tomatoRed, size: 22),
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined, size: 22),
                label: 'History',
                selectedIcon: Icon(Icons.calendar_month_rounded,
                    color: tomatoRed, size: 22),
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined, size: 22),
                label: 'Insights',
                selectedIcon:
                    Icon(Icons.insights_rounded, color: tomatoRed, size: 22),
              ),
              NavigationDestination(
                icon: Icon(Icons.storefront_outlined, size: 22),
                label: 'Canteen',
                selectedIcon:
                    Icon(Icons.storefront_rounded, color: canteenTeal, size: 22),
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined, size: 22),
                label: 'Settings',
                selectedIcon:
                    Icon(Icons.settings_rounded, color: tomatoRed, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int streak;
  final VoidCallback onTap;
  const _StreakChip({required this.streak, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = streak > 0;
    final c = AppColors.of(context);
    return Material(
      color: streakAmber.withValues(alpha: active ? 0.16 : 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 16,
                color: active ? streakAmber : c.textFaint,
              ),
              const SizedBox(width: 4),
              Text(
                '$streak',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: active ? streakAmber : c.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}