import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../core/billing.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/notifiers.dart';
import '../core/settings_repository.dart';
import '../data/database_helper.dart';
import '../widgets/common_widgets.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const int _tabIndex = 2;

  final ScrollController _scrollController = ScrollController();

  bool _loaded = false;
  bool _failed = false;
  bool _dirty = false;
  int _loadSeq = 0;

  MonthReport? _report;
  StreakInfo _streak = const StreakInfo(0, 0);
  List<FlSpot> _weeklyTrend = const <FlSpot>[];
  List<DateTime> _weekDates = const <DateTime>[];

  @override
  void initState() {
    super.initState();
    dbUpdateNotifier.addListener(_onDbUpdated);
    tabIndexNotifier.addListener(_onTabChanged);
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

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      final now = DateTime.now();
      final db = DatabaseHelper.instance;

      final settings = await SettingsRepository.load();
      final monthDays = await db.getMonth(now.year, now.month);
      final extras = await db.getMonthExtras(now.year, now.month);
      final firstTracked = await db.getFirstTrackedDate();
      final perfect = await db.getPerfectDates();

      // The weekly trend can span two months, so it has its own query.
      final weekStart = DateTime(now.year, now.month, now.day - 6);
      final weekMap = await db.getRange(dateKey(weekStart), dateKey(now));
      final spots = <FlSpot>[];
      final dates = <DateTime>[];
      for (var i = 0; i < 7; i++) {
        final d = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
        dates.add(d);
        final count = (weekMap[dateKey(d)] ?? DayMeals.empty).eatenCount;
        spots.add(FlSpot(i.toDouble(), count.toDouble()));
      }

      final report = computeMonthReport(
        year: now.year,
        month: now.month,
        days: monthDays,
        extras: extras,
        settings: settings,
        now: now,
        trackingStart: firstTracked,
      );

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _report = report;
        _streak = computeStreak(perfect, now);
        _weeklyTrend = spots;
        _weekDates = dates;
        _loaded = true;
        _failed = false;
      });
    } catch (e) {
      debugPrint('Stats load error: $e');
      if (!mounted || seq != _loadSeq) return;
      if (!_loaded) setState(() => _failed = true);
    }
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
              Text('Could not load insights',
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
      return const SkeletonPulse(
        child: SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(
            children: [
              Row(children: [
                Expanded(child: SkeletonBox(height: 120, radius: 16)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 120, radius: 16)),
              ]),
              SizedBox(height: 10),
              Row(children: [
                Expanded(child: SkeletonBox(height: 120, radius: 16)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 120, radius: 16)),
              ]),
              SizedBox(height: 24),
              SkeletonBox(height: 220, radius: 18),
            ],
          ),
        ),
      );
    }

    final bestDay = report.bestDate == null
        ? 'N/A'
        : DateFormat('EEE, d MMM').format(parseDateKey(report.bestDate!) ?? DateTime.now());

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
            _buildInsightBanner(c, report),
            const SizedBox(height: 12),
            Row(
              children: [
                _kpiCard(c, 'Total Eaten', '${report.eaten}',
                    Icons.restaurant_menu, sageGreen, 'this month'),
                const SizedBox(width: 10),
                _kpiCard(c, 'Missed', '${report.missed}', Icons.close_rounded,
                    tomatoRed, 'this month'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _kpiCard(c, 'Best Day', bestDay, Icons.emoji_events_outlined,
                    Colors.amber.shade700, '${report.bestCount} meals',
                    isSmall: true),
                const SizedBox(width: 10),
                _kpiCard(
                  c,
                  'Success Rate',
                  '${report.successPercent}%',
                  Icons.trending_up,
                  sageGreen,
                  report.missed > (report.passedSlots - report.missed)
                      ? 'Needs work'
                      : 'On track',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _kpiCard(c, 'Current Streak', '${_streak.current}',
                    Icons.local_fire_department_rounded, streakAmber, 'days'),
                const SizedBox(width: 10),
                _kpiCard(c, 'Best Streak', '${_streak.best}',
                    Icons.workspace_premium_rounded, streakAmber, 'days'),
              ],
            ),
            const SizedBox(height: 24),
            const SectionTitle('Weekly Trend'),
            const SizedBox(height: 10),
            _buildTrendChart(c),
            const SizedBox(height: 24),
            const SectionTitle('Meal-wise Discipline'),
            const SizedBox(height: 10),
            _buildDiscipline(c, report),
            const SizedBox(height: 24),
            const SectionTitle('Where your money goes'),
            const SizedBox(height: 10),
            _buildSpend(c, report),
            const SizedBox(height: 24),
            const SectionTitle('Why you skip'),
            const SizedBox(height: 10),
            _buildSkipReasons(c, report),
          ],
        ),
      ),
    );
  }

  // ----- insight banner

  String _insightText(MonthReport r) {
    if (r.passedSlots == 0) {
      return 'Log your first meals and insights will appear here.';
    }
    if (r.missed == 0) {
      return 'No missed meals this month. Brilliant consistency!';
    }
    String worst = kMealTypes.first;
    for (final t in kMealTypes) {
      if ((r.missedByMeal[t] ?? 0) > (r.missedByMeal[worst] ?? 0)) worst = t;
    }
    final n = r.missedByMeal[worst] ?? 0;
    final total = r.passedByMeal[worst] ?? 0;
    return 'You skip $worst the most: $n of $total meals.';
  }

  Widget _buildInsightBanner(AppColors c, MonthReport r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tomatoRed.withValues(alpha: c.isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tomatoRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_rounded, color: streakAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _insightText(r),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- weekly trend (same chart as before)

  Widget _buildTrendChart(AppColors c) {
    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
        boxShadow: [
          if (!c.isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: c.border,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= _weekDates.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('E').format(_weekDates[i]),
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: 3,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => tomatoRed,
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '${s.y.toInt()} meals',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: _weeklyTrend,
              isCurved: true,
              curveSmoothness: 0.4,
              color: tomatoRed,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                  radius: 4,
                  color: c.surface,
                  strokeWidth: 2.5,
                  strokeColor: tomatoRed,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    tomatoRed.withValues(alpha: 0.2),
                    tomatoRed.withValues(alpha: 0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----- meal-wise discipline

  Widget _buildDiscipline(AppColors c, MonthReport r) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var i = 0; i < mealMetas.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _disciplineRow(c, mealMetas[i], r),
          ],
        ],
      ),
    );
  }

  Widget _disciplineRow(AppColors c, MealMeta meta, MonthReport r) {
    final passed = r.passedByMeal[meta.type] ?? 0;
    final missed = r.missedByMeal[meta.type] ?? 0;
    final done = passed - missed;
    final ratio = passed == 0 ? 0.0 : done / passed;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(meta.icon, size: 16, color: meta.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    meta.type,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  Text(
                    '$done/$passed  •  ${(ratio * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: c.border,
                    valueColor: AlwaysStoppedAnimation<Color>(meta.color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----- spend

  Widget _buildSpend(AppColors c, MonthReport r) {
    final mess = r.bill.messTotal;
    final extra = r.bill.extraTotal;
    final total = mess + extra;
    final messFlex = total <= 0 ? 1 : (mess / total * 1000).round();
    final extraFlex = total <= 0 ? 0 : (extra / total * 1000).round();
    final top = groupExtras(r.extras, limit: 5);

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: messFlex < 1 ? 1 : messFlex,
                    child: Container(color: sageGreen),
                  ),
                  if (extraFlex > 0)
                    Expanded(flex: extraFlex, child: Container(color: tomatoRed)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendAmount(c, sageGreen, 'Mess', mess),
              const SizedBox(width: 24),
              _legendAmount(c, tomatoRed, 'Extras', extra),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 12),
            Text(
              'TOP CRAVINGS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            for (final g in top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                    Text(
                      '×${g.count}',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatRupees(g.total),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tomatoRed,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _legendAmount(AppColors c, Color color, String label, double amount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: c.textMuted)),
            Text(
              formatRupees(amount),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ----- skip reasons (same pie as before)

  Widget _buildSkipReasons(AppColors c, MonthReport r) {
    final reasons = r.skipReasons;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
        boxShadow: [
          if (!c.isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: reasons.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Icon(Icons.celebration_outlined,
                        size: 36, color: sageGreen.withValues(alpha: 0.6)),
                    const SizedBox(height: 8),
                    Text('No skipped meals yet!',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text('Keep up the streak 🔥',
                        style: TextStyle(fontSize: 11, color: c.textMuted)),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 50,
                      sections: reasons.entries
                          .map((e) => PieChartSectionData(
                                color: _reasonColor(e.key),
                                value: e.value.toDouble(),
                                title: '${e.value}',
                                radius: 40,
                                titleStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: reasons.keys.map((reason) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _reasonColor(reason),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          reason,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }

  Widget _kpiCard(
    AppColors c,
    String title,
    String value,
    IconData icon,
    Color color,
    String subtext, {
    bool isSmall = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
          boxShadow: [
            if (!c.isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: isSmall ? 16 : 22,
                  fontWeight: FontWeight.w900,
                  color: c.text,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: c.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                subtext,
                style: TextStyle(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _reasonColor(String reason) {
    switch (reason) {
      case 'Not Hungry':
        return tomatoRed;
      case 'Out of Campus':
        return sageGreen;
      case 'Sick':
        return const Color(0xFF9E2A2B);
      case 'Guests/Party':
        return const Color(0xFF5F634F);
      default:
        return Colors.grey;
    }
  }
}
