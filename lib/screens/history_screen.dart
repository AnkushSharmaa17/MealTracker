import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

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

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const int _tabIndex = 1;

  final ScrollController _scrollController = ScrollController();

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  Map<String, DayMeals> _days = {};
  List<ExtraMeal> _extras = const <ExtraMeal>[];
  AppSettings _settings = const AppSettings();
  MonthReport? _report;

  bool _loaded = false;
  bool _failed = false;
  bool _refreshing = false;
  bool _editing = false;
  bool _dirty = false;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    dbUpdateNotifier.addListener(_onDbUpdated);
    tabIndexNotifier.addListener(_onTabChanged);
    // The tab is built lazily on first visit to keep app start fast.
    if (tabIndexNotifier.value == _tabIndex) {
      _load();
    } else {
      _dirty = true;
    }
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
    final month = _focusedDay;
    if (mounted) setState(() => _refreshing = true);
    try {
      final db = DatabaseHelper.instance;
      final settings = await SettingsRepository.load();
      final days = await db.getMonth(month.year, month.month);
      final extras = await db.getMonthExtras(month.year, month.month);
      final firstTracked = await db.getFirstTrackedDate();

      final report = computeMonthReport(
        year: month.year,
        month: month.month,
        days: days,
        extras: extras,
        settings: settings,
        now: DateTime.now(),
        trackingStart: firstTracked,
      );

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _settings = settings;
        _days = days;
        _extras = extras;
        _report = report;
        _loaded = true;
        _failed = false;
        _refreshing = false;
      });
    } catch (e) {
      debugPrint('History load error: $e');
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _refreshing = false;
        if (!_loaded) _failed = true;
      });
    }
  }

  DayMeals _dayOf(DateTime d) => _days[dateKey(d)] ?? DayMeals.empty;

  List<ExtraMeal> _extrasOf(DateTime d) {
    final key = dateKey(d);
    return _extras.where((e) => e.date == key).toList();
  }

  bool _isFuture(DateTime d) {
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day).isAfter(DateTime(now.year, now.month, now.day));
  }

  // -------------------------------------------------------------- actions

  Future<void> _setMeal(String mealType, bool eaten, String? reason) async {
    final day = _selectedDay;
    final key = dateKey(day);
    final previous = _days[key];

    // Optimistic update so the UI reacts instantly.
    setState(() {
      _days = Map<String, DayMeals>.from(_days)
        ..[key] = _dayOf(day)
            .withMeal(mealType, MealEntry(eaten: eaten, reason: reason));
    });
    HapticFeedback.selectionClick();

    try {
      await DatabaseHelper.instance
          .setMealStatus(key, mealType, eaten, reason: reason);
    } catch (e) {
      debugPrint('Set meal error: $e');
      if (!mounted) return;
      setState(() {
        final copy = Map<String, DayMeals>.from(_days);
        if (previous == null) {
          copy.remove(key);
        } else {
          copy[key] = previous;
        }
        _days = copy;
      });
      showAppSnack(context, 'Could not save. Please try again.', color: tomatoRed);
      return;
    }
    dbUpdateNotifier.value++;
    if (key == dateKey(DateTime.now())) {
      unawaited(NotificationService.instance.syncReminders());
    }
  }

  Future<void> _togglePastMeal(String mealType) async {
    final current = _dayOf(_selectedDay).of(mealType).eaten;
    if (current) {
      final reason = await _showReasonDialog(null);
      if (reason == null) return;
      await _setMeal(mealType, false, reason);
    } else {
      await _setMeal(mealType, true, null);
    }
  }

  Future<void> _changeReason(String mealType) async {
    final entry = _dayOf(_selectedDay).of(mealType);
    if (entry.eaten) return;
    final reason = await _showReasonDialog(entry.reason);
    if (reason == null) return;
    await _setMeal(mealType, false, reason);
  }

  Future<String?> _showReasonDialog(String? initial) {
    String? selected = initial;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final c = AppColors.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Why skip?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in kSkipReasons)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r, style: TextStyle(color: c.text, fontSize: 13)),
                    trailing: Icon(
                      selected == r
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected == r ? tomatoRed : Colors.grey,
                      size: 18,
                    ),
                    onTap: () => setDialogState(() => selected = r),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, selected),
                style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteExtra(ExtraMeal e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Extra?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('Remove "${e.name}"?'),
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
    if (confirm != true) return;
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

  void _onPageChanged(DateTime focused) {
    final now = DateTime.now();
    final sameAsNow = focused.year == now.year && focused.month == now.month;
    setState(() {
      _focusedDay = focused;
      _editing = false;
      // Keep the selected day inside the visible month so the card and the
      // calendar can never disagree.
      _selectedDay = sameAsNow
          ? DateTime(now.year, now.month, now.day)
          : DateTime(focused.year, focused.month, 1);
    });
    _load();
  }

  void _openBreakdown() {
    final report = _report;
    if (report == null) return;
    showBillSheet(
      context,
      monthLabel: DateFormat('MMMM yyyy').format(_focusedDay),
      report: report,
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final report = _report;

    if (!_loaded || report == null) {
      if (_failed) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: c.textFaint),
              const SizedBox(height: 12),
              Text('Could not load history',
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
      return const _HistorySkeleton();
    }

    final now = DateTime.now();
    final isFutureMonth = _focusedDay.year > now.year ||
        (_focusedDay.year == now.year && _focusedDay.month > now.month);
    final canEdit = !isFutureMonth && !_isFuture(_selectedDay);

    return RefreshIndicator(
      color: tomatoRed,
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics:
            const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBillCard(report),
            const SizedBox(height: 12),
            _buildMiniStats(c, report),
            const SizedBox(height: 12),
            _buildCalendar(c),
            const SizedBox(height: 12),
            _buildSelectedDayCard(c, canEdit),
          ],
        ),
      ),
    );
  }

  Widget _buildBillCard(MonthReport report) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [tomatoRed, tomatoDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: tomatoRed.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _openBreakdown,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${DateFormat('MMM yyyy').format(_focusedDay)} Bill',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedAmount(
                        value: report.bill.total,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_refreshing)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward,
                      color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStats(AppColors c, MonthReport report) {
    return Row(
      children: [
        _miniStat(c, 'Total', '${report.totalSlots}', c.textMuted),
        const SizedBox(width: 6),
        _miniStat(c, 'Eaten', '${report.eaten}', sageGreen),
        const SizedBox(width: 6),
        _miniStat(c, 'Perfect', '${report.perfectDays}', tomatoRed),
        const SizedBox(width: 6),
        _miniStat(c, 'Rate', '${report.successPercent}%', c.text),
      ],
    );
  }

  Widget _miniStat(AppColors c, String title, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              title,
              style: TextStyle(
                fontSize: 9,
                color: c.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar(AppColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Month'},
            startingDayOfWeek: StartingDayOfWeek.monday,
            rowHeight: 44,
            daysOfWeekHeight: 20,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: c.text,
              ),
              leftChevronIcon:
                  const Icon(Icons.chevron_left, color: tomatoRed, size: 20),
              rightChevronIcon:
                  const Icon(Icons.chevron_right, color: tomatoRed, size: 20),
              headerPadding: const EdgeInsets.symmetric(vertical: 8),
              headerMargin: EdgeInsets.zero,
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                color: c.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              weekendStyle: TextStyle(
                color: c.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            calendarStyle: const CalendarStyle(outsideDaysVisible: false),
            onDaySelected: (selectedDay, focusedDay) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
                _editing = false;
              });
            },
            onPageChanged: _onPageChanged,
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) =>
                  _buildDayCell(c, day, isToday: false, isSelected: false),
              todayBuilder: (context, day, focusedDay) => _buildDayCell(c, day,
                  isToday: true, isSelected: isSameDay(_selectedDay, day)),
              selectedBuilder: (context, day, focusedDay) => _buildDayCell(c, day,
                  isToday: isSameDay(day, DateTime.now()), isSelected: true),
            ),
          ),
          const SizedBox(height: 6),
          _buildLegend(c),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _buildLegend(AppColors c) {
    Widget item(Widget leading, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, color: c.textMuted)),
        ],
      );
    }

    Widget dot(Color color) => Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        item(dot(sageGreen), 'Eaten'),
        item(dot(tomatoRed.withValues(alpha: 0.35)), 'Skipped'),
        item(const Text('🔥', style: TextStyle(fontSize: 9)), 'All 3'),
        item(const Text('🍔', style: TextStyle(fontSize: 9)), 'Extra'),
      ],
    );
  }

  Widget _buildDayCell(AppColors c, DateTime day,
      {required bool isToday, required bool isSelected}) {
    final meals = _dayOf(day);
    final future = _isFuture(day);
    final count = meals.eatenCount;
    final hasExtra = _extras.any((e) => e.date == dateKey(day));

    Color background;
    if (isSelected) {
      background = tomatoRed;
    } else if (future || count == 0) {
      background = Colors.transparent;
    } else if (count == 3) {
      background = sageGreen.withValues(alpha: c.isDark ? 0.22 : 0.16);
    } else {
      background = tomatoRed.withValues(alpha: c.isDark ? 0.16 : 0.08);
    }

    final textColor = isSelected
        ? Colors.white
        : (future ? c.textFaint : (isToday ? tomatoRed : c.text));

    Widget dotFor(bool eaten) {
      Color color;
      if (isSelected) {
        color = Colors.white.withValues(alpha: eaten ? 1.0 : 0.4);
      } else {
        color = eaten ? sageGreen : tomatoRed.withValues(alpha: 0.3);
      }
      return Container(
        width: 5,
        height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 0.75),
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
    }

    return Container(
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: (isToday && !isSelected)
            ? Border.all(color: tomatoRed, width: 1.2)
            : null,
      ),
      child: Stack(
        children: [
          if (count == 3 && !future)
            const Positioned(
              top: 1,
              right: 2,
              child: Text('🔥', style: TextStyle(fontSize: 7)),
            ),
          if (hasExtra)
            const Positioned(
              bottom: 1,
              right: 2,
              child: Text('🍔', style: TextStyle(fontSize: 7)),
            ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        (isToday || isSelected) ? FontWeight.bold : FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                if (!future)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      dotFor(meals.morning.eaten),
                      dotFor(meals.afternoon.eaten),
                      dotFor(meals.night.eaten),
                    ],
                  )
                else
                  const SizedBox(height: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDayCard(AppColors c, bool canEdit) {
    final extras = _extrasOf(_selectedDay);
    final day = _dayOf(_selectedDay);

    return SurfaceCard(
      shadow: false,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: tomatoRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DateFormat('EEEE, d MMM').format(_selectedDay),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              if (canEdit) ...[
                _smallAction(
                  icon: Icons.add,
                  label: 'Extra',
                  color: tomatoRed,
                  onTap: () => showAddExtraSheet(context, date: _selectedDay),
                ),
                const SizedBox(width: 6),
                _smallAction(
                  icon: _editing ? Icons.check : Icons.edit,
                  label: _editing ? 'Done' : 'Edit',
                  color: _editing ? sageGreen : tomatoRed,
                  onTap: () => setState(() => _editing = !_editing),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final meta in mealMetas)
                _buildMealDetail(c, meta, day.of(meta.type),
                    editable: canEdit && _editing,
                    isFixed: _settings.isFixed(meta.type)),
            ],
          ),
          if (canEdit && _editing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  'Tap to toggle • Long-press a skipped meal to change its reason',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: c.textFaint),
                ),
              ),
            ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.fastfood_outlined, size: 12, color: tomatoRed),
                const SizedBox(width: 4),
                Text(
                  'Extras',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final e in extras) _extraTile(c, e),
          ],
        ],
      ),
    );
  }

  Widget _smallAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _extraTile(AppColors c, ExtraMeal e) {
    final meta = mealMetaOf(e.mealType);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(meta.icon, size: 14, color: meta.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '₹${formatAmount(e.amount)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tomatoRed,
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _confirmDeleteExtra(e),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 14, color: tomatoRed.withValues(alpha: 0.7)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealDetail(
    AppColors c,
    MealMeta meta,
    MealEntry entry, {
    required bool editable,
    required bool isFixed,
  }) {
    final eaten = entry.eaten;
    final reason = entry.reason;
    final label = eaten ? 'Eaten' : (reason ?? (isFixed ? 'Fixed' : 'Skip'));
    final labelColor = eaten
        ? sageGreen
        : ((isFixed || reason != null) ? tomatoRed : Colors.grey);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: editable ? () => _togglePastMeal(meta.type) : null,
        onLongPress:
            (editable && !eaten) ? () => _changeReason(meta.type) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: eaten
                          ? meta.color.withValues(alpha: 0.15)
                          : c.surfaceAlt,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: eaten ? meta.color : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      meta.icon,
                      color: eaten ? meta.color : c.textFaint,
                      size: 16,
                    ),
                  ),
                  if (isFixed)
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: tomatoRed, shape: BoxShape.circle),
                      child: const Icon(Icons.lock, size: 7, color: Colors.white),
                    ),
                  if (editable && !isFixed)
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: c.isDark ? Colors.grey.shade700 : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit, size: 8, color: tomatoRed),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                meta.type,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 80),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    color: labelColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          children: [
            SkeletonBox(height: 72, radius: 20),
            SizedBox(height: 12),
            SkeletonBox(height: 52, radius: 12),
            SizedBox(height: 12),
            SkeletonBox(height: 340, radius: 18),
            SizedBox(height: 12),
            SkeletonBox(height: 110, radius: 18),
          ],
        ),
      ),
    );
  }
}
