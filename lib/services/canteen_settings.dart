import 'package:shared_preferences/shared_preferences.dart';

import '../core/canteen.dart';

/// A payment the user started in their UPI app; we ask them to confirm it
/// when they come back so it can be added with one tap.
class PendingPayment {
  final double amount;
  final String kind;
  final String note;
  const PendingPayment({
    required this.amount,
    required this.kind,
    required this.note,
  });
}

/// Budget alert bookkeeping so each level notifies only once per month.
class BudgetAlertState {
  final String month;
  final int level;
  final double budget;
  const BudgetAlertState(this.month, this.level, this.budget);
}

/// Canteen preferences (all stored locally in SharedPreferences).
class CanteenSettings {
  static const String _kName = 'canteen_name';
  static const String _kUpi = 'canteen_upi';
  static const String _kBudget = 'canteen_budget';
  static const String _kAlertMonth = 'canteen_alert_month';
  static const String _kAlertLevel = 'canteen_alert_level';
  static const String _kAlertBudget = 'canteen_alert_budget';
  static const String _kPendAmount = 'canteen_pending_amount';
  static const String _kPendKind = 'canteen_pending_kind';
  static const String _kPendNote = 'canteen_pending_note';
  static const String _kPendTime = 'canteen_pending_time';

  static Future<CanteenProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CanteenProfile(
      name: prefs.getString(_kName) ?? '',
      upiId: prefs.getString(_kUpi) ?? '',
      budget: double.tryParse(prefs.getString(_kBudget) ?? '') ?? 0,
    );
  }

  static Future<void> saveProfile({
    required String name,
    required String upiId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, name.trim());
    await prefs.setString(_kUpi, upiId.trim());
  }

  static Future<void> saveBudget(double budget) async {
    final prefs = await SharedPreferences.getInstance();
    final double value = budget < 0 ? 0.0 : budget;
    await prefs.setString(_kBudget, value.toString());
  }

  // ------------------------------------------------------- budget alerts

  static Future<BudgetAlertState> loadAlertState() async {
    final prefs = await SharedPreferences.getInstance();
    return BudgetAlertState(
      prefs.getString(_kAlertMonth) ?? '',
      prefs.getInt(_kAlertLevel) ?? 0,
      double.tryParse(prefs.getString(_kAlertBudget) ?? '') ?? 0,
    );
  }

  static Future<void> saveAlertState(
      String month, int level, double budget) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAlertMonth, month);
    await prefs.setInt(_kAlertLevel, level);
    await prefs.setString(_kAlertBudget, budget.toString());
  }

  // ------------------------------------------------------ pending payment

  static Future<void> setPending(PendingPayment p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendAmount, p.amount.toString());
    await prefs.setString(_kPendKind, p.kind);
    await prefs.setString(_kPendNote, p.note);
    await prefs.setInt(_kPendTime, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns (and clears) the pending payment if it is recent enough.
  static Future<PendingPayment?> takePending({
    Duration maxAge = const Duration(minutes: 90),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final time = prefs.getInt(_kPendTime);
    final amount = double.tryParse(prefs.getString(_kPendAmount) ?? '');
    final kind = prefs.getString(_kPendKind) ?? kKindSpend;
    final note = prefs.getString(_kPendNote) ?? '';

    await prefs.remove(_kPendTime);
    await prefs.remove(_kPendAmount);
    await prefs.remove(_kPendKind);
    await prefs.remove(_kPendNote);

    if (time == null || amount == null || amount <= 0) return null;
    final age = DateTime.now().millisecondsSinceEpoch - time;
    if (age < 0 || age > maxAge.inMilliseconds) return null;
    return PendingPayment(amount: amount, kind: kind, note: note);
  }
}
