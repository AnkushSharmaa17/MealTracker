import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../core/billing.dart';
import '../core/canteen.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/notifiers.dart';
import '../core/upi.dart';
import '../data/database_helper.dart';
import '../services/canteen_settings.dart';
import '../services/notification_service.dart';
import '../widgets/canteen_sheets.dart';
import '../widgets/common_widgets.dart';

/// Canteen mini-app: completely separate from the mess bill and streaks.
class CanteenScreen extends StatefulWidget {
  const CanteenScreen({super.key});

  @override
  State<CanteenScreen> createState() => _CanteenScreenState();
}

class _CanteenScreenState extends State<CanteenScreen>
    with WidgetsBindingObserver {
  static const int _tabIndex = 3;

  final ScrollController _scrollController = ScrollController();

  bool _loaded = false;
  bool _failed = false;
  bool _dirty = false;
  bool _askingPending = false;
  int _loadSeq = 0;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  CanteenProfile _profile = const CanteenProfile();
  List<CanteenEntry> _entries = const <CanteenEntry>[];
  double _outstanding = 0;
  List<QuickPick> _picks = const <QuickPick>[];
  CanteenSummary _summary = const CanteenSummary(
    spent: 0,
    credit: 0,
    settled: 0,
    count: 0,
    budget: 0,
    outstanding: 0,
  );
  String _quickKind = kKindSpend;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    dbUpdateNotifier.addListener(_onDbUpdated);
    tabIndexNotifier.addListener(_onTabChanged);
    appLockedNotifier.addListener(_onLockChanged);
    if (tabIndexNotifier.value == _tabIndex) {
      _load();
    } else {
      _dirty = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    dbUpdateNotifier.removeListener(_onDbUpdated);
    tabIndexNotifier.removeListener(_onTabChanged);
    appLockedNotifier.removeListener(_onLockChanged);
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
    if (tabIndexNotifier.value == _tabIndex) {
      if (_dirty) {
        _dirty = false;
        _load();
      }
      unawaited(_maybeAskPending());
    }
  }

  void _onLockChanged() {
    if (!appLockedNotifier.value) unawaited(_maybeAskPending());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_maybeAskPending());
    }
  }

  // ----------------------------------------------------------------- data

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      final db = DatabaseHelper.instance;
      final profile = await CanteenSettings.load();
      final entries = await db.getCanteenMonth(_month.year, _month.month);
      final outstanding = await db.getCanteenOutstanding();
      final picks = await db.getCanteenFrequent(limit: 8);
      final summary = computeCanteenSummary(
        entries: entries,
        outstanding: outstanding,
        budget: profile.budget,
      );

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _profile = profile;
        _entries = entries;
        _outstanding = outstanding;
        _picks = mergeQuickPicks(picks);
        _summary = summary;
        _loaded = true;
        _failed = false;
      });
      if (_isCurrentMonth) unawaited(_checkBudgetAlert(summary));
    } catch (e) {
      debugPrint('Canteen load error: $e');
      if (!mounted || seq != _loadSeq) return;
      if (!_loaded) setState(() => _failed = true);
    }
  }

  /// Notifies once at 80% and once when the budget is crossed (per month).
  Future<void> _checkBudgetAlert(CanteenSummary s) async {
    try {
      final monthKey = dateKey(_month).substring(0, 7);
      final state = await CanteenSettings.loadAlertState();
      if (state.month != monthKey || state.budget != s.budget) {
        await CanteenSettings.saveAlertState(monthKey, s.level, s.budget);
        return;
      }
      if (s.level > state.level) {
        await NotificationService.instance.showCanteenBudgetNotification(
          percent: s.percent,
          over: s.level >= 2,
        );
        await CanteenSettings.saveAlertState(monthKey, s.level, s.budget);
      } else if (s.level < state.level) {
        await CanteenSettings.saveAlertState(monthKey, s.level, s.budget);
      }
    } catch (e) {
      debugPrint('Budget alert error: $e');
    }
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    HapticFeedback.selectionClick();
    setState(() => _month = next);
    _load();
  }

  // -------------------------------------------------------------- actions

  Future<int?> _insert({
    required String kind,
    required String name,
    required double amount,
    required String method,
  }) async {
    try {
      final id = await DatabaseHelper.instance.addCanteenEntry(
        date: dateKey(DateTime.now()),
        kind: kind,
        name: name,
        amount: amount,
        method: method,
      );
      dbUpdateNotifier.value++;
      return id;
    } catch (e) {
      debugPrint('Canteen insert error: $e');
      if (mounted) {
        showAppSnack(context, 'Could not save. Please try again.',
            color: tomatoRed);
      }
      return null;
    }
  }

  Future<void> _undoDelete(int id) async {
    try {
      await DatabaseHelper.instance.deleteCanteenEntry(id);
      dbUpdateNotifier.value++;
    } catch (e) {
      debugPrint('Undo error: $e');
    }
  }

  Future<void> _quickAdd(QuickPick pick) async {
    HapticFeedback.lightImpact();
    final kind = _quickKind;
    final id = await _insert(
      kind: kind,
      name: pick.name,
      amount: pick.amount,
      method: kind == kKindCredit ? 'khata' : 'cash',
    );
    if (id == null || !mounted) return;
    showAppSnack(
      context,
      '${pick.name} added • ${formatRupees(pick.amount)}'
      '${kind == kKindCredit ? ' (udhaar)' : ''}',
      color: canteenTeal,
      actionLabel: 'UNDO',
      onAction: () => _undoDelete(id),
    );
  }

  Future<void> _deleteEntry(CanteenEntry e) async {
    setState(() {
      _entries = _entries.where((x) => x.id != e.id).toList();
    });
    try {
      await DatabaseHelper.instance.deleteCanteenEntry(e.id);
    } catch (err) {
      debugPrint('Delete canteen entry error: $err');
    }
    dbUpdateNotifier.value++;
    if (!mounted) return;
    showAppSnack(
      context,
      '${e.name} removed',
      color: tomatoRed,
      actionLabel: 'UNDO',
      onAction: () async {
        try {
          await DatabaseHelper.instance.addCanteenEntry(
            date: e.date,
            kind: e.kind,
            name: e.name,
            amount: e.amount,
            method: e.method,
          );
          dbUpdateNotifier.value++;
        } catch (err) {
          debugPrint('Undo delete error: $err');
        }
      },
    );
  }

  Future<void> _openAddEntry({
    String kind = kKindSpend,
    double? amount,
    String? name,
    String method = 'cash',
  }) async {
    await showCanteenEntrySheet(
      context,
      kind: kind,
      amount: amount,
      name: name,
      method: method,
    );
  }

  Future<void> _openSettings() async {
    await showCanteenSettingsSheet(context, profile: _profile);
  }

  Future<void> _scanSetup() async {
    final payee = await scanAndConfirmPayee(context);
    if (payee == null) return;
    try {
      await CanteenSettings.saveProfile(
        name: payee.name.isEmpty ? _profile.name : payee.name,
        upiId: payee.id,
      );
      dbUpdateNotifier.value++;
      if (!mounted) return;
      showAppSnack(context, 'Canteen saved. You can now pay in one tap.',
          color: canteenTeal);
    } catch (e) {
      debugPrint('Save payee error: $e');
      if (mounted) {
        showAppSnack(context, 'Could not save. Please try again.',
            color: tomatoRed);
      }
    }
  }

  Future<void> _pay() async {
    if (!_profile.hasUpi) {
      await _scanSetup();
      return;
    }
    final req = await showCanteenPaySheet(
      context,
      profile: _profile,
      suggested: _outstanding > 0 ? _outstanding : null,
    );
    if (req == null || !mounted) return;

    final url = buildUpiPayUrl(
      payeeId: _profile.upiId,
      payeeName: _profile.name,
      amount: req.amount,
      note: req.note,
    );
    await CanteenSettings.setPending(
      PendingPayment(amount: req.amount, kind: req.kind, note: req.note),
    );

    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('UPI launch error: $e');
    }

    if (!launched) {
      await CanteenSettings.takePending();
      if (!mounted) return;
      showAppSnack(
        context,
        'Could not open a UPI app. Pay manually, then add the entry.',
        color: tomatoRed,
        actionLabel: 'ADD ENTRY',
        onAction: () {
          if (!mounted) return;
          _openAddEntry(
            kind: req.kind,
            amount: req.amount,
            name: req.note,
            method: 'upi',
          );
        },
      );
    }
  }

  /// When the user comes back from their UPI app, offer to record the payment.
  Future<void> _maybeAskPending() async {
    if (_askingPending || !mounted) return;
    if (tabIndexNotifier.value != _tabIndex || appLockedNotifier.value) return;
    _askingPending = true;
    try {
      final pending = await CanteenSettings.takePending();
      if (pending == null || !mounted) return;
      await _confirmPending(pending);
    } catch (e) {
      debugPrint('Pending payment error: $e');
    } finally {
      _askingPending = false;
    }
  }

  Future<void> _confirmPending(PendingPayment p) async {
    final isSettle = p.kind == kKindSettle;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Did the payment go through?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Add ${formatRupees(p.amount)} to your canteen record'
          '${isSettle ? ' as udhaar settled' : ' as a purchase'}?\n\n'
          'Only add it if your UPI app showed success.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'no'),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const Text('Edit'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'add'),
            style: ElevatedButton.styleFrom(backgroundColor: canteenTeal),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'add') {
      final id = await _insert(
        kind: p.kind,
        name: p.note,
        amount: p.amount,
        method: 'upi',
      );
      if (id != null && mounted) {
        showAppSnack(context, 'Payment added', color: sageGreen);
      }
    } else if (choice == 'edit') {
      await _openAddEntry(
        kind: p.kind,
        amount: p.amount,
        name: p.note,
        method: 'upi',
      );
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    if (!_loaded) {
      if (_failed) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: c.textFaint),
              const SizedBox(height: 12),
              Text('Could not load canteen data',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() => _failed = false);
                  _load();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: canteenTeal, foregroundColor: Colors.white),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      return const _CanteenSkeleton();
    }

    return RefreshIndicator(
      color: canteenTeal,
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics:
            const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMonthBar(c),
            const SizedBox(height: 4),
            _buildHero(c),
            if (_isCurrentMonth && _summary.level > 0) ...[
              const SizedBox(height: 12),
              _buildBudgetBanner(c),
            ],
            const SizedBox(height: 14),
            _buildKhataCard(c),
            const SizedBox(height: 14),
            _buildPayCard(c),
            const SizedBox(height: 24),
            _buildQuickAdd(c),
            ..._buildTopSpends(c),
            const SizedBox(height: 24),
            _buildEntries(c),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ----- month bar

  Widget _buildMonthBar(AppColors c) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left_rounded),
          color: c.text,
          onPressed: () => _changeMonth(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              DateFormat('MMMM yyyy').format(_month),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right_rounded),
          color: c.text,
          onPressed: _isCurrentMonth ? null : () => _changeMonth(1),
        ),
        IconButton(
          tooltip: 'Canteen settings',
          icon: const Icon(Icons.tune_rounded),
          color: canteenTeal,
          onPressed: _openSettings,
        ),
      ],
    );
  }

  // ----- hero

  Color _levelColor(int level) {
    if (level >= 2) return const Color(0xFFFF8A80);
    if (level == 1) return const Color(0xFFFFD54F);
    return Colors.white;
  }

  Widget _buildHero(AppColors c) {
    final s = _summary;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [canteenTeal, canteenTealDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: canteenTeal.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(right: -30, top: -30, child: _circle(130, 0.09)),
            Positioned(left: -24, bottom: -46, child: _circle(120, 0.06)),
            Padding(
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storefront_rounded,
                                size: 12, color: Colors.white),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                _profile.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${s.count} ${s.count == 1 ? 'entry' : 'entries'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isCurrentMonth ? 'Spent this month' : 'Spent in this month',
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
                              value: s.spent,
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildBudgetSection(s),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _heroStat(Icons.bookmark_rounded,
                            formatRupees(s.credit), 'On udhaar'),
                        _heroDivider(),
                        _heroStat(Icons.task_alt_rounded,
                            formatRupees(s.settled), 'Settled'),
                        _heroDivider(),
                        _heroStat(Icons.receipt_long_rounded,
                            formatRupees(s.spent - s.credit), 'Paid now'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetSection(CanteenSummary s) {
    if (!s.hasBudget) {
      return InkWell(
        onTap: _openSettings,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.savings_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Set a monthly budget to get alerts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      );
    }

    final color = _levelColor(s.level);
    final over = s.remaining < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: s.progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${s.percent}% of ${formatRupees(s.budget)} budget',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            Text(
              over
                  ? '${formatRupees(-s.remaining)} over'
                  : '${formatRupees(s.remaining)} left',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _circle(double size, double alpha) {
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
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
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

  // ----- budget banner

  Widget _buildBudgetBanner(AppColors c) {
    final s = _summary;
    final over = s.level >= 2;
    final color = over ? tomatoRed : streakAmber;
    final text = over
        ? 'Budget crossed by ${formatRupees(-s.remaining)}. Time to slow down on canteen spends.'
        : 'You have used ${s.percent}% of your ${formatRupees(s.budget)} budget. ${formatRupees(s.remaining)} left.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: c.isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            over ? Icons.error_rounded : Icons.warning_amber_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
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

  // ----- khata (udhaar)

  Widget _buildKhataCard(AppColors c) {
    final owed = _outstanding;
    final due = owed > 0.005;
    final advance = owed < -0.005;
    final color = due ? tomatoRed : sageGreen;
    final label = due ? 'Udhaar baaki' : (advance ? 'Advance paid' : 'Udhaar balance');
    final amount = advance ? -owed : (due ? owed : 0.0);
    final sub = due
        ? 'You owe the canteen'
        : (advance ? 'Canteen owes you this much' : 'All clear, nothing due');

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              due ? Icons.bookmark_rounded : Icons.verified_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatRupees(amount),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: color,
                  ),
                ),
                Text(sub, style: TextStyle(fontSize: 11, color: c.textMuted)),
              ],
            ),
          ),
          if (due)
            OutlinedButton(
              onPressed: () =>
                  _openAddEntry(kind: kKindSettle, amount: owed),
              style: OutlinedButton.styleFrom(
                foregroundColor: canteenTeal,
                side: BorderSide(color: canteenTeal.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Settle up',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  // ----- pay card

  Widget _buildPayCard(AppColors c) {
    final hasUpi = _profile.hasUpi;

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: canteenTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasUpi ? Icons.storefront_rounded : Icons.qr_code_2_rounded,
                  color: canteenTeal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasUpi ? _profile.displayName : 'Set up your canteen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasUpi
                          ? _profile.upiId
                          : 'Scan the canteen\'s UPI QR once to enable one-tap Pay',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              if (hasUpi)
                IconButton(
                  tooltip: 'Scan a different QR',
                  icon: const Icon(Icons.qr_code_scanner_rounded,
                      color: canteenTeal),
                  onPressed: _scanSetup,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _pay,
                  icon: Icon(
                    hasUpi
                        ? Icons.account_balance_wallet_rounded
                        : Icons.qr_code_scanner_rounded,
                    size: 18,
                  ),
                  label: Text(hasUpi ? 'Pay via UPI' : 'Scan QR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canteenTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _openAddEntry(),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Add manually'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: canteenTeal,
                    side: BorderSide(color: canteenTeal.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          if (!hasUpi) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openSettings,
                style: TextButton.styleFrom(
                  foregroundColor: c.textMuted,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Or type the UPI ID yourself',
                    style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ----- quick add

  Widget _buildQuickAdd(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Quick Add',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _kindToggle(c, kKindSpend, 'Paid'),
              const SizedBox(width: 6),
              _kindToggle(c, kKindCredit, 'Udhaar'),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
      ],
    );
  }

  Widget _kindToggle(AppColors c, String kind, String label) {
    final selected = _quickKind == kind;
    final color = kind == kKindCredit ? streakAmber : canteenTeal;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _quickKind = kind);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? color : c.textMuted,
          ),
        ),
      ),
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
              const Icon(Icons.add_rounded, size: 14, color: canteenTeal),
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

  // ----- top spends

  List<Widget> _buildTopSpends(AppColors c) {
    final groups = groupCanteenItems(_entries, limit: 5);
    if (groups.isEmpty) return const <Widget>[];
    final maxTotal = groups.first.total <= 0 ? 1.0 : groups.first.total;

    return [
      const SizedBox(height: 24),
      const SectionTitle('Top Spends'),
      const SizedBox(height: 10),
      SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _topRow(c, i + 1, groups[i], maxTotal),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _topRow(AppColors c, int rank, ExtraGroup g, double maxTotal) {
    final ratio = (g.total / maxTotal).clamp(0.0, 1.0);
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: canteenTeal.withValues(alpha: rank == 1 ? 0.18 : 0.08),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$rank',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: canteenTeal,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                  ),
                  Text('×${g.count}',
                      style: TextStyle(fontSize: 10, color: c.textMuted)),
                  const SizedBox(width: 10),
                  Text(
                    formatRupees(g.total),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: canteenTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: c.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(canteenTeal),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----- entries

  Widget _buildEntries(AppColors c) {
    // Entries arrive newest first; keep the groups in that order.
    final groups = <String, List<CanteenEntry>>{};
    for (final e in _entries) {
      groups.putIfAbsent(e.date, () => <CanteenEntry>[]).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('Entries', trailing: PillBadge('${_entries.length}', color: canteenTeal)),
        const SizedBox(height: 10),
        if (_entries.isEmpty)
          SurfaceCard(
            shadow: false,
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            child: const SizedBox(
              width: double.infinity,
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No canteen entries this month',
                subtitle: 'Use Quick Add or Add manually',
                color: canteenTeal,
              ),
            ),
          )
        else ...[
          for (final entry in groups.entries) ...[
            _dayHeader(c, entry.key, entry.value),
            const SizedBox(height: 6),
            _dayCard(c, entry.value),
            const SizedBox(height: 14),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Tip: swipe left on an entry to delete it',
              style: TextStyle(fontSize: 10, color: c.textFaint),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dayHeader(AppColors c, String key, List<CanteenEntry> items) {
    final date = parseDateKey(key);
    var total = 0.0;
    for (final e in items) {
      if (e.kind != kKindSettle) total += e.amount;
    }
    return Row(
      children: [
        Text(
          date == null ? key : DateFormat('EEE, d MMM').format(date),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: c.textMuted,
          ),
        ),
        const Spacer(),
        if (total > 0)
          Text(
            formatRupees(total),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
      ],
    );
  }

  Widget _dayCard(AppColors c, List<CanteenEntry> items) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.border),
              _entryRow(c, items[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entryRow(AppColors c, CanteenEntry e) {
    IconData icon;
    Color color;
    if (e.kind == kKindCredit) {
      icon = Icons.bookmark_rounded;
      color = streakAmber;
    } else if (e.kind == kKindSettle) {
      icon = Icons.task_alt_rounded;
      color = sageGreen;
    } else {
      icon = Icons.shopping_bag_rounded;
      color = canteenTeal;
    }
    final methodLabel = e.method == 'upi'
        ? 'UPI'
        : (e.method == 'khata' ? 'On account' : 'Cash');

    return Dismissible(
      key: ValueKey<int>(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: tomatoRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (direction) => _deleteEntry(e),
      child: Container(
        color: c.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 16),
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
                    '${canteenKindLabel(e.kind)} • $methodLabel',
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '${e.kind == kKindSettle ? '+' : ''}₹${formatAmount(e.amount)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: e.kind == kKindSettle ? sageGreen : c.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanteenSkeleton extends StatelessWidget {
  const _CanteenSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          children: [
            SkeletonBox(height: 44, radius: 12),
            SizedBox(height: 8),
            SkeletonBox(height: 240, radius: 24),
            SizedBox(height: 14),
            SkeletonBox(height: 90, radius: 18),
            SizedBox(height: 14),
            SkeletonBox(height: 130, radius: 18),
          ],
        ),
      ),
    );
  }
}
