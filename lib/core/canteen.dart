// Canteen mini-app logic. Completely separate from the mess bill: nothing in
// here touches meals, rates or streaks. Pure Dart, unit-tested.

import 'billing.dart';

/// Paid on the spot (cash / UPI).
const String kKindSpend = 'spend';

/// Taken on credit (udhaar).
const String kKindCredit = 'credit';

/// Paid back some of the udhaar.
const String kKindSettle = 'settle';

const List<String> kCanteenKinds = [kKindSpend, kKindCredit, kKindSettle];
const List<String> kCanteenMethods = ['cash', 'upi', 'khata'];

String canteenKindLabel(String kind) {
  switch (kind) {
    case kKindCredit:
      return 'Udhaar';
    case kKindSettle:
      return 'Settled';
    default:
      return 'Paid';
  }
}

class CanteenEntry {
  final int id;
  final String date;
  final String kind;
  final String name;
  final double amount;
  final String method;

  const CanteenEntry({
    required this.id,
    required this.date,
    required this.kind,
    required this.name,
    required this.amount,
    required this.method,
  });

  factory CanteenEntry.fromMap(Map<String, Object?> m) {
    return CanteenEntry(
      id: (m['id'] as num).toInt(),
      date: m['date'] as String,
      kind: (m['kind'] as String?) ?? kKindSpend,
      name: (m['name'] as String?) ?? '',
      amount: (m['amount'] as num).toDouble(),
      method: (m['method'] as String?) ?? 'cash',
    );
  }

  bool get isSettlement => kind == kKindSettle;
  bool get isCredit => kind == kKindCredit;
}

/// Saved canteen details + monthly budget (0 = no budget).
class CanteenProfile {
  final String name;
  final String upiId;
  final double budget;

  const CanteenProfile({this.name = '', this.upiId = '', this.budget = 0});

  bool get hasUpi => upiId.trim().isNotEmpty;
  bool get hasBudget => budget > 0;
  String get displayName => name.trim().isEmpty ? 'Canteen' : name.trim();
}

/// 0 = fine / no budget, 1 = 80% or more used, 2 = budget crossed.
int budgetLevel(double spent, double budget) {
  if (budget <= 0) return 0;
  final ratio = spent / budget;
  if (ratio >= 1) return 2;
  if (ratio >= 0.8) return 1;
  return 0;
}

class CanteenSummary {
  /// Everything consumed this month (paid + udhaar). Settlements are not
  /// consumption, they only reduce the udhaar balance.
  final double spent;
  final double credit;
  final double settled;
  final int count;
  final double budget;

  /// All-time udhaar still to be paid (negative = advance paid).
  final double outstanding;

  const CanteenSummary({
    required this.spent,
    required this.credit,
    required this.settled,
    required this.count,
    required this.budget,
    required this.outstanding,
  });

  bool get hasBudget => budget > 0;
  double get remaining => budget - spent;

  double get progress {
    if (!hasBudget) return 0;
    final r = spent / budget;
    if (r < 0) return 0;
    if (r > 1) return 1;
    return r;
  }

  int get percent => hasBudget ? (spent / budget * 100).round() : 0;
  int get level => budgetLevel(spent, budget);
}

CanteenSummary computeCanteenSummary({
  required List<CanteenEntry> entries,
  required double outstanding,
  required double budget,
}) {
  var spent = 0.0;
  var credit = 0.0;
  var settled = 0.0;
  for (final e in entries) {
    if (e.kind == kKindSettle) {
      settled += e.amount;
    } else if (e.kind == kKindCredit) {
      spent += e.amount;
      credit += e.amount;
    } else {
      spent += e.amount;
    }
  }
  return CanteenSummary(
    spent: spent,
    credit: credit,
    settled: settled,
    count: entries.length,
    budget: budget,
    outstanding: outstanding,
  );
}

/// All-time udhaar balance from a list of entries.
double computeOutstanding(List<CanteenEntry> entries) {
  var total = 0.0;
  for (final e in entries) {
    if (e.kind == kKindCredit) total += e.amount;
    if (e.kind == kKindSettle) total -= e.amount;
  }
  return total;
}

/// Biggest spends by item name (settlements are ignored).
List<ExtraGroup> groupCanteenItems(List<CanteenEntry> entries, {int limit = 5}) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final e in entries) {
    if (e.kind == kKindSettle) continue;
    final key = e.name.trim().toLowerCase();
    if (key.isEmpty) continue;
    totals[key] = (totals[key] ?? 0) + e.amount;
    counts[key] = (counts[key] ?? 0) + 1;
    names.putIfAbsent(key, () => e.name.trim());
  }
  final list = [
    for (final k in totals.keys) ExtraGroup(names[k]!, counts[k]!, totals[k]!),
  ];
  list.sort((a, b) => b.total.compareTo(a.total));
  return list.length > limit ? list.sublist(0, limit) : list;
}
