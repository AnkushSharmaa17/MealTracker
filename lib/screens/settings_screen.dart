import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/backup.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/notifiers.dart';
import '../data/database_helper.dart';
import '../services/app_lock_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import 'lock_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Function(bool)? onThemeChanged;
  const SettingsScreen({super.key, this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();

  String rateType = 'monthly';
  bool perMealSameRate = true;
  bool isDarkMode = false;
  bool appLockEnabled = false;

  double monthlyFee = 3000;
  double rateSame = 40;
  double rateMorning = 40;
  double rateAfternoon = 40;
  double rateNight = 40;

  bool _fixedMorning = false;
  bool _fixedAfternoon = false;
  bool _fixedNight = false;

  TimeOfDay morningTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay afternoonTime = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay nightTime = const TimeOfDay(hour: 21, minute: 0);

  final Map<String, bool> _permStatus = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadLockState();
    _refreshPermissions();
    tabIndexNotifier.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    tabIndexNotifier.removeListener(_onTabChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    FocusManager.instance.primaryFocus?.unfocus();
    if (tabIndexNotifier.value == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshPermissions();
      });
    }
  }

  Future<void> _refreshPermissions() async {
    try {
      final notif = await Permission.notification.status;
      if (!mounted) return;
      final alarm = await Permission.scheduleExactAlarm.status;
      if (!mounted) return;
      final battery = await Permission.ignoreBatteryOptimizations.status;
      if (!mounted) return;
      setState(() {
        _permStatus['notification'] = notif.isGranted;
        _permStatus['alarm'] = alarm.isGranted;
        _permStatus['battery'] = battery.isGranted;
      });
    } catch (e) {
      debugPrint('Permission refresh error: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final fixedMeals = prefs.getStringList('fixed_meals') ?? [];
    setState(() {
      monthlyFee =
          double.tryParse(prefs.getString('monthly_fee') ?? '3000') ?? 3000;
      rateSame = double.tryParse(prefs.getString('rate_same') ?? '40') ?? 40;
      rateMorning =
          double.tryParse(prefs.getString('rate_morning') ?? '40') ?? 40;
      rateAfternoon =
          double.tryParse(prefs.getString('rate_afternoon') ?? '40') ?? 40;
      rateNight = double.tryParse(prefs.getString('rate_night') ?? '40') ?? 40;
      rateType = prefs.getString('rate_type') ?? 'monthly';
      perMealSameRate = prefs.getBool('per_meal_same') ?? true;
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _fixedMorning = fixedMeals.contains('Morning');
      _fixedAfternoon = fixedMeals.contains('Afternoon');
      _fixedNight = fixedMeals.contains('Night');
      morningTime = TimeOfDay(
          hour: prefs.getInt('time_morning_h') ?? 9,
          minute: prefs.getInt('time_morning_m') ?? 0);
      afternoonTime = TimeOfDay(
          hour: prefs.getInt('time_afternoon_h') ?? 14,
          minute: prefs.getInt('time_afternoon_m') ?? 0);
      nightTime = TimeOfDay(
          hour: prefs.getInt('time_night_h') ?? 21,
          minute: prefs.getInt('time_night_m') ?? 0);
    });
  }

  void _triggerDbUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dbUpdateNotifier.value++;
    });
  }

  Future<void> _saveRateType(String value) async {
    if (!mounted) return;
    setState(() => rateType = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rate_type', value);
    _triggerDbUpdate();
  }

  Future<void> _saveFixedMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final fixedMeals = <String>[];
    if (_fixedMorning) fixedMeals.add('Morning');
    if (_fixedAfternoon) fixedMeals.add('Afternoon');
    if (_fixedNight) fixedMeals.add('Night');
    await prefs.setStringList('fixed_meals', fixedMeals);
    _triggerDbUpdate();
  }

  Future<void> _saveTime(String meal, TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    switch (meal) {
      case 'Morning':
        if (!mounted) return;
        setState(() => morningTime = time);
        await prefs.setInt('time_morning_h', time.hour);
        await prefs.setInt('time_morning_m', time.minute);
        break;
      case 'Afternoon':
        if (!mounted) return;
        setState(() => afternoonTime = time);
        await prefs.setInt('time_afternoon_h', time.hour);
        await prefs.setInt('time_afternoon_m', time.minute);
        break;
      case 'Night':
        if (!mounted) return;
        setState(() => nightTime = time);
        await prefs.setInt('time_night_h', time.hour);
        await prefs.setInt('time_night_m', time.minute);
        break;
    }
    await NotificationService.instance.syncReminders();
  }

  Future<void> _toggleDarkMode(bool value) async {
    if (!mounted) return;
    setState(() => isDarkMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    widget.onThemeChanged?.call(value);
  }

  void _showSnack(String message, Color color) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(message,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        debugPrint('Snackbar error: $e');
      }
    });
  }

  Future<void> _loadLockState() async {
    final enabled = await AppLockService.instance.isEnabled();
    if (!mounted) return;
    setState(() => appLockEnabled = enabled);
  }

  Future<void> _toggleAppLock(bool value) async {
    final mode = value ? PinPageMode.setup : PinPageMode.verify;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => PinPage(mode: mode),
      ),
    );
    if (ok != true) return;
    if (!value) {
      await AppLockService.instance.disable();
    }
    await _loadLockState();
    if (!mounted) return;
    _showSnack(value ? 'App lock turned on' : 'App lock turned off',
        value ? sageGreen : tomatoRed);
  }

  Future<void> _backupData() async {
    try {
      final text = await BackupService.createBackup();
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Backup copied',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text(
            'All your data is now on the clipboard as text.\n\n'
            'Paste it into Notes, or send it to yourself on WhatsApp, and keep it safe. '
            'It is not encrypted, so do not share it with anyone.\n\n'
            'The app-lock PIN is never included.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: sageGreen),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Backup error: $e');
      if (mounted) _showSnack('Backup failed. Please try again.', tomatoRed);
    }
  }

  Future<void> _restoreData() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      _showSnack('Clipboard is empty. Copy your backup text first.', tomatoRed);
      return;
    }

    BackupData parsed;
    try {
      parsed = decodeBackup(text);
    } on FormatException catch (e) {
      _showSnack(e.message, tomatoRed);
      return;
    }

    final created = parsed.created == null
        ? ''
        : '\nBackup date: ${DateFormat('d MMM yyyy, hh:mm a').format(parsed.created!)}';
    final skipped =
        parsed.skipped > 0 ? '\n${parsed.skipped} damaged rows will be skipped.' : '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restore this backup?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Found ${parsed.meals.length} meals, ${parsed.extras.length} extras '
          'and ${parsed.canteen.length} canteen entries.$created$skipped\n\n'
          'This REPLACES all data currently on this phone.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
            child: const Text('Replace & restore',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await BackupService.restore(parsed);
      await _loadSettings();
      if (!mounted) return;
      _showSnack('Backup restored', sageGreen);
    } catch (e) {
      debugPrint('Restore error: $e');
      if (mounted) _showSnack('Restore failed. Your data was not changed.', tomatoRed);
    }
  }

  Future<void> _togglePerMealSame(bool value) async {
    if (!mounted) return;
    setState(() => perMealSameRate = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('per_meal_same', value);
    _triggerDbUpdate();
  }

  double _mealRate(String meal) {
    switch (meal) {
      case 'Morning':
        return rateMorning;
      case 'Afternoon':
        return rateAfternoon;
      default:
        return rateNight;
    }
  }

  Future<void> _editMealRate(String meal) async {
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => _RateEditDialog(
        title: '$meal Rate (₹)',
        initialValue: _mealRate(meal),
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
    if (result == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rate_${meal.toLowerCase()}', result.toStringAsFixed(0));
    if (!mounted) return;
    setState(() {
      if (meal == 'Morning') {
        rateMorning = result;
      } else if (meal == 'Afternoon') {
        rateAfternoon = result;
      } else {
        rateNight = result;
      }
    });
    _triggerDbUpdate();
    _showSnack('$meal rate updated', sageGreen);
  }

  Future<void> _showRateDialog() async {
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => _RateEditDialog(
        title: rateType == 'monthly' ? 'Monthly Fee (₹)' : 'Rate per Meal (₹)',
        initialValue: rateType == 'monthly' ? monthlyFee : rateSame,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    );

    if (result == null || !mounted) return;

    if (result > 0) {
      if (rateType == 'monthly') {
        setState(() => monthlyFee = result);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('monthly_fee', result.toStringAsFixed(0));
      } else {
        setState(() => rateSame = result);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('rate_same', result.toStringAsFixed(0));
      }
      _triggerDbUpdate();
      _showSnack('Rate updated', sageGreen);
    } else {
      _showSnack('Invalid amount', tomatoRed);
    }
  }

  Permission _permFor(String key) {
    switch (key) {
      case 'notification':
        return Permission.notification;
      case 'alarm':
        return Permission.scheduleExactAlarm;
      case 'battery':
        return Permission.ignoreBatteryOptimizations;
      default:
        return Permission.notification;
    }
  }

  Future<void> _handlePermission(String key) async {
    final perm = _permFor(key);
    final current = await perm.status;
    if (!mounted) return;

    if (current.isGranted) {
      _showDisableDialog(key);
    } else if (current.isPermanentlyDenied) {
      _showOpenSettingsDialog(key);
    } else {
      final result = await perm.request();
      if (!mounted) return;
      if (result.isGranted) {
        _showSnack('Permission enabled', sageGreen);
      } else {
        _showSnack('Permission denied', tomatoRed);
      }
      _refreshPermissions();
    }
  }

  Map<String, String> _permInfo(String key) {
    switch (key) {
      case 'notification':
        return {
          'title': 'Notification Access',
          'subtitle': 'Allow meal reminders'
        };
      case 'alarm':
        return {'title': 'Exact Alarm', 'subtitle': 'Precise reminder timing'};
      case 'battery':
        return {
          'title': 'Background Alerts',
          'subtitle': 'Alerts when app is closed'
        };
      default:
        return {'title': '', 'subtitle': ''};
    }
  }

  void _showDisableDialog(String key) {
    final info = _permInfo(key);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('${info['title']} is On',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
            'To disable, open app settings.\n\nDisabling may stop notifications.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
            child: const Text('Open Settings',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showOpenSettingsDialog(String key) {
    final info = _permInfo(key);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('${info['title']} Blocked',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
            'Permission was permanently denied. Please enable from app settings.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
            child: const Text('Open Settings',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(TimeOfDay current, String meal) async {
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !mounted) return;
    await _saveTime(meal, picked);
    _showSnack('$meal time updated', sageGreen);
  }

  String _formatTime(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  String _formatTimeHm(int h, int m) {
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$hour:${m.toString().padLeft(2, '0')} $period';
  }

  Future<void> _runDiagnostics() async {
    final results = <String, Map<String, dynamic>>{};
    final prefs = await SharedPreferences.getInstance();

    try {
      final nowDt = DateTime.now();
      await DatabaseHelper.instance.getDay(dateKey(nowDt));
      final monthData =
          await DatabaseHelper.instance.getMonth(nowDt.year, nowDt.month);
      final extras =
          await DatabaseHelper.instance.getMonthExtras(nowDt.year, nowDt.month);
      results['Database'] = {
        'ok': true,
        'detail': '${monthData.length} days • ${extras.length} extras',
      };
    } catch (e) {
      results['Database'] = {'ok': false, 'detail': 'Error: $e'};
    }

    final notifPerm = await Permission.notification.status;
    results['Notification Permission'] = {
      'ok': notifPerm.isGranted,
      'detail':
          notifPerm.isGranted ? 'Granted' : 'Denied — tap to enable',
    };

    final alarmPerm = await Permission.scheduleExactAlarm.status;
    results['Exact Alarm'] = {
      'ok': alarmPerm.isGranted,
      'detail': alarmPerm.isGranted
          ? 'Granted (exact timing works)'
          : 'Denied — notifications may be late',
    };

    final batteryPerm = await Permission.ignoreBatteryOptimizations.status;
    results['Background Alerts'] = {
      'ok': batteryPerm.isGranted,
      'detail': batteryPerm.isGranted
          ? 'Unrestricted (works when closed)'
          : 'Optimized — may miss alerts',
    };

    final rateTypePref = prefs.getString('rate_type') ?? 'monthly';
    final monthlyFeePref = prefs.getString('monthly_fee') ?? '3000';
    final rateSamePref = prefs.getString('rate_same') ?? '40';
    results['Rate Config'] = {
      'ok': true,
      'detail': rateTypePref == 'monthly'
          ? 'Monthly ₹$monthlyFeePref'
          : 'Per meal ₹$rateSamePref',
    };

    final fixedMeals = prefs.getStringList('fixed_meals') ?? [];
    results['Fixed Meals'] = {
      'ok': true,
      'detail': fixedMeals.isEmpty
          ? 'None set (flexible mode)'
          : '${fixedMeals.join(", ")} (always charged)',
    };

    final mH = prefs.getInt('time_morning_h') ?? 9;
    final mM = prefs.getInt('time_morning_m') ?? 0;
    final aH = prefs.getInt('time_afternoon_h') ?? 14;
    final aM = prefs.getInt('time_afternoon_m') ?? 0;
    final nH = prefs.getInt('time_night_h') ?? 21;
    final nM = prefs.getInt('time_night_m') ?? 0;
    results['Reminder Times'] = {
      'ok': true,
      'detail':
          '${_formatTimeHm(mH, mM)} • ${_formatTimeHm(aH, aM)} • ${_formatTimeHm(nH, nM)}',
    };

    try {
      final pending = await NotificationService
          .instance.flutterLocalNotificationsPlugin
          .pendingNotificationRequests();
      results['Scheduled Notifications'] = {
        'ok': pending.isNotEmpty,
        'detail': pending.isEmpty
            ? '0 pending — change time to schedule'
            : '${pending.length} notifications scheduled',
      };
    } catch (e) {
      results['Scheduled Notifications'] = {
        'ok': false,
        'detail': 'Error: $e',
      };
    }

    results['Theme'] = {
      'ok': true,
      'detail':
          (prefs.getBool('isDarkMode') ?? false) ? 'Dark mode' : 'Light mode',
    };

    try {
      final nowDt = DateTime.now();
      final monthData =
          await DatabaseHelper.instance.getMonth(nowDt.year, nowDt.month);
      int totalEaten = 0;
      for (final day in monthData.values) {
        totalEaten += day.eatenCount;
      }
      results['Meal Tracker'] = {
        'ok': true,
        'detail': '$totalEaten meals eaten this month',
      };
    } catch (e) {
      results['Meal Tracker'] = {'ok': false, 'detail': 'Error: $e'};
    }

    if (!mounted) return;
    _showDiagnosticsDialog(results);
  }

  void _showDiagnosticsDialog(Map<String, Map<String, dynamic>> results) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allOk = results.values.every((r) => r['ok'] == true);
    final failCount = results.values.where((r) => r['ok'] != true).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              allOk ? Icons.check_circle_rounded : Icons.warning_rounded,
              color: allOk ? sageGreen : tomatoRed,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                allOk ? 'All Systems OK' : '$failCount issue(s) found',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: allOk ? sageGreen : tomatoRed,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: results.entries.map((entry) {
                final ok = entry.value['ok'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          ok
                              ? Icons.check_circle_outline_rounded
                              : Icons.cancel_outlined,
                          size: 16,
                          color: ok ? sageGreen : tomatoRed,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              entry.value['detail'].toString(),
                              style: TextStyle(
                                fontSize: 11,
                                color: ok
                                    ? (isDark
                                        ? Colors.grey.shade500
                                        : Colors.grey.shade600)
                                    : tomatoRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (!allOk)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _refreshPermissions();
              },
              style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
              child: const Text('Refresh',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E0E10) : offWhite;
    final cardColor = isDark ? const Color(0xFF16161A) : Colors.white;
    final dividerColor = isDark ? Colors.grey.shade900 : Colors.grey.shade200;

    return Scaffold(
      backgroundColor: bgColor,
      body: ListView(
        controller: _scrollController,
        physics:
            const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // Info strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: sageGreen.withValues(alpha: isDark ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: sageGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.bolt_rounded,
                      size: 14, color: sageGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All changes save automatically',
                    style: TextStyle(
                        fontSize: 11,
                        color: sageGreen,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // APPEARANCE
          _sectionHeader('Appearance', isDark),
          _card(cardColor, dividerColor, [
            _switchTile(
              icon: Icons.dark_mode_rounded,
              color: tomatoRed,
              title: 'Dark Mode',
              subtitle: 'Reduce eye strain at night',
              value: isDarkMode,
              onChanged: _toggleDarkMode,
              isDark: isDark,
            ),
          ]),

          const SizedBox(height: 20),

          // MESS BILL
          _sectionHeader('Mess Bill', isDark),
          _card(cardColor, dividerColor, [
            _tile(
              icon: Icons.account_balance_wallet_rounded,
              color: tomatoRed,
              title: rateType == 'monthly'
                  ? 'Monthly Fee: ₹${monthlyFee.toStringAsFixed(0)}'
                  : 'Per Meal: ₹${rateSame.toStringAsFixed(0)}',
              subtitle: rateType == 'monthly'
                  ? 'Tap to change your mess bill'
                  : (perMealSameRate
                      ? 'Charged per meal eaten'
                      : 'Used when "same rate" is on'),
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
              onTap: _showRateDialog,
              isDark: isDark,
            ),
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          size: 13,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text('Rate Type',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _rateChip('Monthly', rateType == 'monthly',
                            isDark, () => _saveRateType('monthly')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _rateChip('Per Meal', rateType == 'per_meal',
                            isDark, () => _saveRateType('per_meal')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (rateType == 'per_meal') ...[
              Divider(height: 1, color: dividerColor),
              _switchTile(
                icon: Icons.layers_rounded,
                color: sageGreen,
                title: 'Same Rate For All Meals',
                subtitle: 'Turn off to set separate rates',
                value: perMealSameRate,
                onChanged: _togglePerMealSame,
                isDark: isDark,
              ),
              if (!perMealSameRate)
                for (final meal in const ['Morning', 'Afternoon', 'Night']) ...[
                  Divider(height: 1, color: dividerColor),
                  _tile(
                    icon: mealMetaOf(meal).icon,
                    color: mealMetaOf(meal).color,
                    title: '$meal: ₹${_mealRate(meal).toStringAsFixed(0)}',
                    subtitle: 'Tap to change $meal rate',
                    trailing: Icon(Icons.chevron_right_rounded,
                        size: 20,
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade400),
                    onTap: () => _editMealRate(meal),
                    isDark: isDark,
                  ),
                ],
            ],
          ]),

          const SizedBox(height: 20),

          // FIXED MEALS
          _sectionHeader('Fixed Meals', isDark),
          _card(cardColor, dividerColor, [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: sageGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child:
                        const Icon(Icons.lock_rounded, color: sageGreen, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Charge Even If Skipped',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 2),
                        Text('Fixed meals are always charged',
                            style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor),
            _fixedMealTile('Morning', _fixedMorning, isDark, (v) async {
              setState(() => _fixedMorning = v);
              await _saveFixedMeals();
            }),
            Divider(height: 1, color: dividerColor),
            _fixedMealTile('Afternoon', _fixedAfternoon, isDark, (v) async {
              setState(() => _fixedAfternoon = v);
              await _saveFixedMeals();
            }),
            Divider(height: 1, color: dividerColor),
            _fixedMealTile('Night', _fixedNight, isDark, (v) async {
              setState(() => _fixedNight = v);
              await _saveFixedMeals();
            }),
          ]),

          const SizedBox(height: 20),

          // REMINDERS
          _sectionHeader('Meal Reminders', isDark),
          _card(cardColor, dividerColor, [
            _timeTile('Morning', morningTime, Icons.wb_twilight_rounded,
                tomatoRed, isDark, () => _pickTime(morningTime, 'Morning')),
            Divider(height: 1, color: dividerColor),
            _timeTile('Afternoon', afternoonTime, Icons.wb_sunny_rounded,
                sageGreen, isDark, () => _pickTime(afternoonTime, 'Afternoon')),
            Divider(height: 1, color: dividerColor),
            _timeTile('Night', nightTime, Icons.nightlight_rounded,
                isDark ? Colors.white70 : Colors.black87, isDark,
                () => _pickTime(nightTime, 'Night')),
          ]),

          const SizedBox(height: 20),

          // PERMISSIONS
          _sectionHeader('Permissions', isDark),
          _card(cardColor, dividerColor, [
            _permTile('notification', Icons.notifications_rounded, isDark),
            Divider(height: 1, color: dividerColor),
            _permTile('alarm', Icons.alarm_rounded, isDark),
            Divider(height: 1, color: dividerColor),
            _permTile('battery', Icons.battery_charging_full_rounded, isDark),
          ]),

          const SizedBox(height: 20),

          // SECURITY & BACKUP
          _sectionHeader('Security & Backup', isDark),
          _card(cardColor, dividerColor, [
            _switchTile(
              icon: Icons.lock_rounded,
              color: tomatoRed,
              title: 'App Lock (PIN)',
              subtitle: 'Ask for a 4-digit PIN when you open the app',
              value: appLockEnabled,
              onChanged: _toggleAppLock,
              isDark: isDark,
            ),
            Divider(height: 1, color: dividerColor),
            _tile(
              icon: Icons.upload_rounded,
              color: sageGreen,
              title: 'Backup Data',
              subtitle: 'Copy all your data as text. Nothing is uploaded.',
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
              onTap: _backupData,
              isDark: isDark,
            ),
            Divider(height: 1, color: dividerColor),
            _tile(
              icon: Icons.download_rounded,
              color: canteenTeal,
              title: 'Restore Data',
              subtitle: 'Paste a backup you copied earlier',
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
              onTap: _restoreData,
              isDark: isDark,
            ),
          ]),

          const SizedBox(height: 20),

          // TEST & DIAGNOSTICS
          _sectionHeader('Test & Diagnostics', isDark),
          _card(cardColor, dividerColor, [
            _tile(
              icon: Icons.notifications_active_rounded,
              color: tomatoRed,
              title: 'Test Notification',
              subtitle: 'Send a test notification',
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                NotificationService.instance.showTestNotification();
                _showSnack('Test notification sent', sageGreen);
              },
              isDark: isDark,
            ),
            Divider(height: 1, color: dividerColor),
            _tile(
              icon: Icons.bug_report_rounded,
              color: sageGreen,
              title: 'Run Diagnostics',
              subtitle: 'Full system health check',
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
              onTap: _runDiagnostics,
              isDark: isDark,
            ),
          ]),

          // DEVELOPER CARD
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 1,
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade300,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: dividerColor),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: tomatoRed.withValues(alpha: 0.1),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.person_rounded,
                            size: 22, color: tomatoRed),
                      ),
                      const SizedBox(height: 12),
                      Text('Ankush Sharma',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: isDark ? Colors.white : Colors.black87)),
                      const SizedBox(height: 3),
                      Text('Software Engineer',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade600)),
                      const SizedBox(height: 14),
                      Container(
                          width: 30,
                          height: 1,
                          color: dividerColor),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.school_rounded,
                              size: 12,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade600),
                          const SizedBox(width: 5),
                          Text('Computer Science • MCA Final Year',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF16161A)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('v1.1.0',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade500)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _card(Color cardColor, Color dividerColor, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dividerColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color, bool isDark) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }

  TextStyle _titleStyle(bool isDark) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white : Colors.black87,
    );
  }

  TextStyle _subtitleStyle(bool isDark) {
    return TextStyle(
      fontSize: 10,
      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required bool isDark,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      secondary: _iconBox(icon, color, isDark),
      title: Text(title, style: _titleStyle(isDark)),
      subtitle: Text(subtitle, style: _subtitleStyle(isDark)),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: color,
      onChanged: onChanged,
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: _iconBox(icon, color, isDark),
      title: Text(title, style: _titleStyle(isDark)),
      subtitle: Text(subtitle, style: _subtitleStyle(isDark)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _rateChip(
      String label, bool selected, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? tomatoRed.withValues(alpha: isDark ? 0.16 : 0.1)
              : (isDark ? const Color(0xFF0E0E10) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? tomatoRed.withValues(alpha: 0.5)
                : (isDark ? Colors.grey.shade900 : Colors.grey.shade200),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? tomatoRed
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeTile(String title, TimeOfDay time, IconData icon, Color color,
      bool isDark, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: _iconBox(icon, color, isDark),
      title: Text('$title Time', style: _titleStyle(isDark)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_formatTime(time),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              size: 20,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _fixedMealTile(
      String meal, bool value, bool isDark, Function(bool) onChanged) {
    final icons = {
      'Morning': Icons.wb_twilight_rounded,
      'Afternoon': Icons.wb_sunny_rounded,
      'Night': Icons.nightlight_rounded,
    };
    final colors = {
      'Morning': tomatoRed,
      'Afternoon': sageGreen,
      'Night': isDark ? Colors.white70 : Colors.black87,
    };
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      secondary: _iconBox(icons[meal]!, colors[meal]!, isDark),
      title: Text(meal, style: _titleStyle(isDark)),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: colors[meal]!,
      onChanged: onChanged,
    );
  }

  Widget _permTile(String key, IconData icon, bool isDark) {
    final info = _permInfo(key);
    final granted = _permStatus[key] ?? false;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: _iconBox(icon, granted ? sageGreen : tomatoRed, isDark),
      title: Text(info['title']!, style: _titleStyle(isDark)),
      subtitle: Text(info['subtitle']!, style: _subtitleStyle(isDark)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: granted
              ? sageGreen.withValues(alpha: 0.12)
              : tomatoRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: granted ? sageGreen : tomatoRed,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              granted ? 'ON' : 'OFF',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: granted ? sageGreen : tomatoRed),
            ),
          ],
        ),
      ),
      onTap: () => _handlePermission(key),
    );
  }
}

class _RateEditDialog extends StatefulWidget {
  final String title;
  final double initialValue;
  final bool isDark;
  const _RateEditDialog({
    required this.title,
    required this.initialValue,
    required this.isDark,
  });

  @override
  State<_RateEditDialog> createState() => _RateEditDialogState();
}

class _RateEditDialogState extends State<_RateEditDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialValue.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
        onSubmitted: (_) => _submit(),
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: widget.isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          prefixIcon:
              const Icon(Icons.currency_rupee, size: 18, color: tomatoRed),
          hintText: 'Amount',
          errorText: _error,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: tomatoRed, width: 1.5)),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: tomatoRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}