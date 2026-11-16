import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_theme.dart';
import '../core/billing.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/notifiers.dart';
import '../core/settings_repository.dart';
import '../data/database_helper.dart';
import '../services/notification_service.dart';
import '../widgets/bill_sheet.dart';
import '../widgets/common_widgets.dart';
import '../widgets/extra_meal_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _tabIndex = 0;

  final ScrollController _scrollController = ScrollController();

  bool _loaded = false;
  bool _failed = false;
  bool _dirty = false;
  int _loadSeq = 0;

  AppSettings _settings = const AppSettings();
  DayMeals _today = DayMeals.empty;
  DayMeals _yesterday = DayMeals.empty;
  List<DateTime> _weekDates = const <DateTime>[];
  List<DayMeals> _week = const <DayMeals>[];
  List<ExtraMeal> _todayExtras = const <ExtraMeal>[];
  MonthReport? _report;
  StreakInfo _streak = const StreakInfo(0, 0);
  List<QuickPick> _picks = const <QuickPick>[];

  String get _todayKey => dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    dbUpdateNotifier.addListener(_onDbUpdated);
    tabIndexNotifier.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    dbUpdateNotifier.removeListener(_onDbUpdated);
    tabIndexNotifier.removeListener(_onTabChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onDbUpdated() {
    if (tabIndexNotifier.value == _tabIndex) {
      _load();
    } else {
      _dirty = true;
    }
  }

  void _onTabChanged() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    FocusManager.instance.primaryFocus?.unfocus();
    if (tabIndexNotifier.value == _tabIndex && _dirty) {
      _dirty = false;
      _load();
    }
  }

  // ----------------------------------------------------------------- data

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      final now = DateTime.now();
      final todayKey = dateKey(now);
      final db = DatabaseHelper.instance;

      final settings = await SettingsRepository.load();
      final monthDays = await db.getMonth(now.year, now.month);
      final monthExtras = await db.getMonthExtras(now.year, now.month);
      final weekStart = DateTime(now.year, now.month, now.day - 6);
      final weekMap = await db.getRange(dateKey(weekStart), todayKey);
      final perfect = await db.getPerfectDates();
      final firstTracked = await db.getFirstTrackedDate();
      final picks = await db.getFrequentExtras(limit: 8);

      final report = computeMonthReport(
        year: now.year,
        month: now.month,
        days: monthDays,
        extras: monthExtras,
        settings: settings,
        now: now,
        trackingStart: firstTracked,
      );
      final streak = computeStreak(perfect, now);

      final weekDates = <DateTime>[];
      final week = <DayMeals>[];
      for (var i = 6; i >= 0; i--) {
        final d = DateTime(now.year, now.month, now.day - i);
        weekDates.add(d);
        week.add(weekMap[dateKey(d)] ?? DayMeals.empty);
      }
      final yesterdayKey = dateKey(DateTime(now.year, now.month, now.day - 1));

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _settings = settings;
        _today = monthDays[todayKey] ?? DayMeals.empty;
        _yesterday = weekMap[yesterdayKey] ?? DayMeals.empty;
        _weekDates = weekDates;
        _week = week;
        _todayExtras = monthExtras.where((e) => e.date == todayKey).toList();
        _report = report;
        _streak = streak;
        _picks = mergeQuickPicks(picks);
        _loaded = true;
        _failed = false;
      });
      streakNotifier.value = streak.current;
      unawaited(_checkBillThresholds(report.bill.total));
    } catch (e) {
      debugPrint('Home load error: $e');
      if (!mounted || seq != _loadSeq) return;
      if (!_loaded) setState(() => _failed = true);
    }
  }

  Future<void> _checkBillThresholds(double spent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentMonth = dateKey(DateTime.now()).substring(0, 7);
      final savedMonth = prefs.getString('threshold_month') ?? '';
      if (savedMonth != currentMonth) {
        await prefs.setString('notified_thresholds', '');
        await prefs.setString('threshold_month', currentMonth);
      }
      const thresholds = [500, 1000, 1500, 2000, 2500, 3000, 4000, 5000];
      final notifiedStr = prefs.getString('notified_thresholds') ?? '';
      final notified = notifiedStr.isEmpty ? <String>[] : notifiedStr.split(',');

      for (final t in thresholds) {
        if (spent >= t && !notified.contains(t.toString())) {
          // Show first, then remember it: if the plugin is not ready yet this
          // throws and the alert is retried on the next refresh.
          await NotificationService.instance.showBillNotification(t);
          notified.add(t.toString());
          await prefs.setString('notified_thresholds', notified.join(','));
        }
      }
    } catch (e) {
      debugPrint('Threshold check error: $e');
    }
  }

  // -------------------------------------------------------------- actions

  Future<void> _toggleMeal(String mealType, bool value) async {
    if (!value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Remove this meal?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text('Are you sure you want to remove your $mealType diet?',
              style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
              child: const Text('Yes, Remove',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    HapticFeedback.mediumImpact();
    final updated = _today.withMeal(mealType, MealEntry(eaten: value));
    setState(() => _today = updated);

    try {
      await DatabaseHelper.instance.setMealStatus(_todayKey, mealType, value);
    } catch (e) {
      debugPrint('Toggle meal error: $e');
      if (mounted) {
        showAppSnack(context, 'Could not save. Please try again.',
            color: tomatoRed);
      }
      await _load();
      return;
    }
    dbUpdateNotifier.value++;
    unawaited(NotificationService.instance.syncReminders());

    if (!mounted) return;
    if (value && updated.isPerfect) {
      showAppSnack(context, 'Perfect day! All 3 meals done 🔥', color: sageGreen);
    } else {
      showAppSnack(
        context,
        value ? '$mealType diet marked as eaten' : '$mealType diet removed',
        color: value ? sageGreen : tomatoRed,
      );
    }
  }

  Future<void> _quickAdd(QuickPick pick) async {
    HapticFeedback.lightImpact();
    final type = mealTypeForHour(DateTime.now().hour);
    try {
      final id = await DatabaseHelper.instance
          .addExtraMeal(_todayKey, type, pick.name, pick.amount);
      dbUpdateNotifier.value++;
      if (!mounted) return;
      showAppSnack(
        context,
        '${pick.name} added • ${formatRupees(pick.amount)}',
        color: tomatoRed,
        actionLabel: 'UNDO',
        onAction: () async {
          await DatabaseHelper.instance.deleteExtraMeal(id);
          dbUpdateNotifier.value++;
        },
      );
    } catch (e) {
      debugPrint('Quick add error: $e');
      if (mounted) {
        showAppSnack(context, 'Could not add. Please try again.',
            color: tomatoRed);
      }
    }
  }

  Future<void> _confirmDeleteExtra(ExtraMeal e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Extra Diet?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to remove "${e.name}" from today\'s list?',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _deleteExtra(e);
    }
  }

  /// Used by both the swipe gesture and the delete button. Offers UNDO.
  Future<void> _deleteExtra(ExtraMeal e) async {
    setState(() {
      _todayExtras = _todayExtras.where((x) => x.id != e.id).toList();
    });
    try {
      await DatabaseHelper.instance.deleteExtraMeal(e.id);
    } catch (err) {
      debugPrint('Delete extra error: $err');
    }
    dbUpdateNotifier.value++;
    if (!mounted) return;
    showAppSnack(
      context,
      '${e.name} removed',
      color: tomatoRed,
      actionLabel: 'UNDO',
      onAction: () async {
        await DatabaseHelper.instance
            .addExtraMeal(e.date, e.mealType, e.name, e.amount);
        dbUpdateNotifier.value++;
      },
    );
  }

  Future<void> _openAddExtra() async {
    await showAddExtraSheet(context, date: DateTime.now());
  }

  void _openBreakdown() {
    final report = _report;
    if (report == null) return;
    showBillSheet(
      context,
      monthLabel: DateFormat('MMMM yyyy').format(DateTime.now()),
      report: report,
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final report = _report;

    if (!_loaded || report == null) {
      return _failed ? _buildError(c) : const _HomeSkeleton();
    }

    return RefreshIndicator(
      color: tomatoRed,
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics:
            const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHero(c, report),
            const SizedBox(height: 14),
            _buildStreakCard(c),
            const SizedBox(height: 24),
            _buildMealsSection(c),
            const SizedBox(height: 24),
            _buildExtrasSection(c),
            const SizedBox(height: 24),
            _buildYesterday(c),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildError(AppColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: c.textFaint),
          const SizedBox(height: 12),
          Text('Could not load your data',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              setState(() => _failed = false);
              _load();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: tomatoRed, foregroundColor: Colors.white),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ----- hero

  Widget _buildHero(AppColors c, MonthReport report) {
    final now = DateTime.now();
    final projected = report.projectedTotal(now);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [tomatoRed, tomatoDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: tomatoRed.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(right: -30, top: -30, child: _heroCircle(130, 0.09)),
            Positioned(left: -24, bottom: -46, child: _heroCircle(120, 0.06)),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openBreakdown,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              DateFormat('MMMM yyyy').format(now),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'View breakdown',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Spent this month',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '₹',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: AnimatedAmount(
                                  value: report.bill.total,
                                  style: const TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.2,
                                    height: 1,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (projected != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'On pace ≈ ${formatRupees(projected)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            _heroStat(Icons.check_circle_rounded,
                                '${report.eaten}', 'Eaten'),
                            _heroDivider(),
                            _heroStat(Icons.cancel_rounded, '${report.missed}',
                                'Missed'),
                            _heroDivider(),
                            _heroStat(Icons.savings_rounded,
                                formatRupees(report.saved), 'Saved'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCircle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }

  Widget _heroDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withValues(alpha: 0.25),
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----- streak

  Widget _buildStreakCard(AppColors c) {
    final current = _streak.current;
    final title = current == 0 ? 'Start your streak' : '$current day streak';
    String subtitle;
    if (current == 0) {
      subtitle = 'Eat all 3 meals today to begin';
    } else if (_today.isPerfect) {
      subtitle = 'Today is done • Best: ${_streak.best}';
    } else {
      subtitle = 'Finish today to make it ${current + 1} • Best: ${_streak.best}';
    }

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: streakAmber.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  color: current > 0 ? streakAmber : c.textFaint,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _weekDates.length; i++)
                _weekDot(c, _weekDates[i], _week[i], i == _weekDates.length - 1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekDot(AppColors c, DateTime date, DayMeals day, bool isToday) {
    final count = day.eatenCount;
    Color fill;
    Widget inner;
    if (count == 3) {
      fill = streakAmber;
      inner = const Icon(Icons.check_rounded, size: 15, color: Colors.white);
    } else if (count > 0) {
      fill = streakAmber.withValues(alpha: 0.22);
      inner = Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: streakAmber,
        ),
      );
    } else {
      fill = c.surfaceAlt;
      inner = const SizedBox.shrink();
    }

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: isToday ? tomatoRed : c.border,
              width: isToday ? 1.6 : 1,
            ),
          ),
          child: inner,
        ),
        const SizedBox(height: 5),
        Text(
          weekdayLetter(date),
          style: TextStyle(
            fontSize: 10,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
            color: isToday ? tomatoRed : c.textMuted,
          ),
        ),
      ],
    );
  }

  // ----- meals

  Widget _buildMealsSection(AppColors c) {
    final eatenCount = _today.eatenCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          "Today's Meals",
          trailing: PillBadge('$eatenCount of 3 eaten'),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: eatenCount / 3),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: c.border,
              valueColor: const AlwaysStoppedAnimation<Color>(sageGreen),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < mealMetas.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _buildMealCard(c, mealMetas[i]),
            ],
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: eatenCount == 3
              ? Container(
                  key: const ValueKey<String>('perfect'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: sageGreen.withValues(alpha: c.isDark ? 0.16 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sageGreen.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.local_fire_department_rounded,
                          color: streakAmber, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Perfect day! All 3 meals done.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: sageGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey<String>('not-perfect')),
        ),
      ],
    );
  }

  Widget _buildMealCard(AppColors c, MealMeta meta) {
    final eaten = _today.of(meta.type).eaten;
    final now = DateTime.now();
    final minutes = _settings.minutesOf(meta.type);
    final due = !eaten && (now.hour * 60 + now.minute) >= minutes;

    final statusText = eaten ? 'Eaten' : (due ? 'Due now' : 'Tap to eat');
    final statusColor = eaten ? meta.color : (due ? tomatoRed : c.textFaint);

    Color borderColor;
    if (eaten) {
      borderColor = meta.color.withValues(alpha: 0.5);
    } else if (due) {
      borderColor = tomatoRed.withValues(alpha: 0.4);
    } else {
      borderColor = c.border;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => _toggleMeal(meta.type, !eaten),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: eaten
                ? meta.color.withValues(alpha: c.isDark ? 0.14 : 0.08)
                : c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: eaten ? 1.5 : 1),
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: eaten
                          ? meta.color.withValues(alpha: 0.16)
                          : c.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      meta.icon,
                      color: eaten ? meta.color : c.textFaint,
                      size: 22,
                    ),
                  ),
                  if (eaten)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: meta.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.surface, width: 2),
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 9),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                meta.type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: eaten ? c.text : c.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatClock(minutes),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: c.textFaint,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (eaten || due)
                      ? statusColor.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- extras

  Widget _buildExtrasSection(AppColors c) {
    var todayTotal = 0.0;
    for (final e in _todayExtras) {
      todayTotal += e.amount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    'Extra Cravings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: c.text,
                    ),
                  ),
                  if (_todayExtras.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: tomatoRed,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_todayExtras.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            InkWell(
              onTap: _openAddExtra,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: tomatoRed,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: tomatoRed.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 15),
                    SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_picks.isNotEmpty) ...[
          Text(
            'QUICK ADD',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _picks.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _quickChip(c, _picks[index]),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_todayExtras.isEmpty)
          SurfaceCard(
            shadow: false,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            child: const SizedBox(
              width: double.infinity,
              child: EmptyState(
                icon: Icons.fastfood_outlined,
                title: 'No extra cravings today',
                subtitle: 'Tap a quick add chip or use Add',
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  for (var i = 0; i < _todayExtras.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.border),
                    _extraRow(c, _todayExtras[i]),
                  ],
                  Container(
                    color: c.surfaceAlt,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Today\'s extras',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.textMuted,
                          ),
                        ),
                        Text(
                          formatRupees(todayTotal),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: tomatoRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_todayExtras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Tip: swipe left on an item to remove it',
              style: TextStyle(fontSize: 10, color: c.textFaint),
            ),
          ),
      ],
    );
  }

  Widget _quickChip(AppColors c, QuickPick pick) {
    return Material(
      color: c.surface,
      shape: StadiumBorder(side: BorderSide(color: c.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _quickAdd(pick),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 14, color: tomatoRed),
              const SizedBox(width: 4),
              Text(
                pick.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '₹${formatAmount(pick.amount)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _extraRow(AppColors c, ExtraMeal e) {
    final meta = mealMetaOf(e.mealType);
    return Dismissible(
      key: ValueKey<int>(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: tomatoRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (direction) => _deleteExtra(e),
      child: Container(
        color: c.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(meta.icon, color: meta.color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${e.mealType} craving',
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '₹${formatAmount(e.amount)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: tomatoRed,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _confirmDeleteExtra(e),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: tomatoRed.withValues(alpha: 0.7),
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----- yesterday

  Widget _buildYesterday(AppColors c) {
    final count = _yesterday.eatenCount;
    final perfect = count == 3;
    final yesterdayDate = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day - 1);
    final color = perfect ? sageGreen : tomatoRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Yesterday',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: c.text,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                DateFormat('EEE, d MMM').format(yesterdayDate),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          shadow: false,
          radius: 16,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  perfect
                      ? Icons.local_fire_department_rounded
                      : Icons.trending_up_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perfect ? 'Perfect day!' : 'You ate $count of 3',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      perfect ? 'Keep the streak going' : 'Try to hit all 3 meals today',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (final t in kMealTypes) ...[
                    Container(
                      width: 20,
                      height: 4,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: _yesterday.of(t).eaten ? sageGreen : c.border,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Placeholder shown while the first load is in progress.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 200, radius: 24),
            SizedBox(height: 14),
            SkeletonBox(height: 110, radius: 18),
            SizedBox(height: 24),
            SkeletonBox(width: 140, height: 18, radius: 6),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 130, radius: 18)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 130, radius: 18)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 130, radius: 18)),
              ],
            ),
            SizedBox(height: 24),
            SkeletonBox(height: 90, radius: 16),
          ],
        ),
      ),
    );
  }
}
