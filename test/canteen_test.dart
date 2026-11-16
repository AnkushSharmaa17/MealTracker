import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_streak/core/backup.dart';
import 'package:meal_streak/core/canteen.dart';
import 'package:meal_streak/core/upi.dart';

CanteenEntry _e(int id, String kind, String name, double amount,
    {String date = '2026-11-01', String method = 'cash'}) {
  return CanteenEntry(
    id: id,
    date: date,
    kind: kind,
    name: name,
    amount: amount,
    method: method,
  );
}

void main() {
  group('UPI helpers', () {
    test('isValidUpiId', () {
      expect(isValidUpiId('canteen@okaxis'), isTrue);
      expect(isValidUpiId('hostel.canteen-1@oksbi'), isTrue);
      expect(isValidUpiId(' 9876543210@ybl '), isTrue);
      expect(isValidUpiId('canteen'), isFalse);
      expect(isValidUpiId('@okaxis'), isFalse);
      expect(isValidUpiId('a b@okaxis'), isFalse);
      expect(isValidUpiId(''), isFalse);
    });

    test('parses a standard UPI QR payload', () {
      final p = parseUpiPayload(
          'upi://pay?pa=hostel.canteen@oksbi&pn=Hostel%20Canteen&cu=INR');
      expect(p, isNotNull);
      expect(p!.id, 'hostel.canteen@oksbi');
      expect(p.name, 'Hostel Canteen');
    });

    test('is tolerant: upper case keys, + and raw spaces in the name', () {
      final a = parseUpiPayload('UPI://pay?PA=canteen@okaxis&PN=Tea+Point');
      expect(a!.id, 'canteen@okaxis');
      expect(a.name, 'Tea Point');

      final b = parseUpiPayload('upi://pay?pa=canteen@okaxis&pn=Hostel Canteen');
      expect(b!.name, 'Hostel Canteen');
    });

    test('accepts a bare UPI id', () {
      final p = parseUpiPayload('canteen@okaxis');
      expect(p!.id, 'canteen@okaxis');
      expect(p.name, '');
    });

    test('rejects things that are not a payee', () {
      expect(parseUpiPayload(''), isNull);
      expect(parseUpiPayload('https://example.com/pay'), isNull);
      expect(parseUpiPayload('upi://pay'), isNull);
      expect(parseUpiPayload('upi://pay?pn=NoId'), isNull);
      expect(parseUpiPayload('upi://pay?pa=not-an-id'), isNull);
    });

    test('buildUpiPayUrl encodes values and formats the amount', () {
      final url = buildUpiPayUrl(
        payeeId: 'canteen@okaxis',
        payeeName: 'Hostel Canteen',
        amount: 40,
        note: 'Chai & samosa',
      );
      expect(
        url,
        'upi://pay?pa=canteen@okaxis&pn=Hostel%20Canteen&am=40.00&cu=INR&tn=Chai%20%26%20samosa',
      );
      expect(
        buildUpiPayUrl(payeeId: 'canteen@okaxis', payeeName: ''),
        'upi://pay?pa=canteen@okaxis&cu=INR',
      );
    });
  });

  group('canteen accounting', () {
    test('budgetLevel thresholds', () {
      expect(budgetLevel(500, 0), 0);
      expect(budgetLevel(79, 100), 0);
      expect(budgetLevel(80, 100), 1);
      expect(budgetLevel(99.9, 100), 1);
      expect(budgetLevel(100, 100), 2);
      expect(budgetLevel(150, 100), 2);
    });

    test('summary counts udhaar as spend but settlements as repayment', () {
      final entries = [
        _e(1, kKindSpend, 'Chai', 10),
        _e(2, kKindSpend, 'Samosa', 20),
        _e(3, kKindCredit, 'Maggi', 40, method: 'khata'),
        _e(4, kKindSettle, 'Udhaar settled', 30, method: 'upi'),
      ];
      final s = computeCanteenSummary(entries: entries, outstanding: 10, budget: 100);
      expect(s.spent, 70);
      expect(s.credit, 40);
      expect(s.settled, 30);
      expect(s.count, 4);
      expect(s.outstanding, 10);
      expect(s.remaining, 30);
      expect(s.progress, closeTo(0.7, 0.0001));
      expect(s.percent, 70);
      expect(s.level, 0);

      final tight = computeCanteenSummary(entries: entries, outstanding: 10, budget: 80);
      expect(tight.percent, 88); // 87.5 rounds up
      expect(tight.level, 1);

      final over = computeCanteenSummary(entries: entries, outstanding: 10, budget: 60);
      expect(over.level, 2);
      expect(over.progress, 1);
      expect(over.remaining, -10);
    });

    test('no budget means no progress and no alerts', () {
      final s = computeCanteenSummary(
        entries: [_e(1, kKindSpend, 'Chai', 10)],
        outstanding: 0,
        budget: 0,
      );
      expect(s.hasBudget, isFalse);
      expect(s.progress, 0);
      expect(s.percent, 0);
      expect(s.level, 0);
    });

    test('outstanding = credit - settlements (negative = advance)', () {
      final entries = [
        _e(1, kKindCredit, 'Maggi', 40),
        _e(2, kKindCredit, 'Samosa', 15),
        _e(3, kKindSettle, 'Paid back', 30),
        _e(4, kKindSpend, 'Chai', 10),
      ];
      expect(computeOutstanding(entries), 25);
      entries.add(_e(5, kKindSettle, 'Extra', 100));
      expect(computeOutstanding(entries), -75);
    });

    test('top spends group by name and ignore settlements', () {
      final groups = groupCanteenItems([
        _e(1, kKindSpend, 'Chai', 10),
        _e(2, kKindSpend, 'chai', 12),
        _e(3, kKindCredit, 'Maggi', 40),
        _e(4, kKindSettle, 'Chai', 1000),
      ]);
      expect(groups.length, 2);
      expect(groups[0].name, 'Maggi');
      expect(groups[0].total, 40);
      expect(groups[1].name, 'Chai');
      expect(groups[1].count, 2);
      expect(groups[1].total, 22);
    });

    test('profile helpers', () {
      expect(const CanteenProfile().displayName, 'Canteen');
      expect(const CanteenProfile().hasUpi, isFalse);
      expect(const CanteenProfile(name: ' Tea Point ', upiId: 'a@b1').displayName, 'Tea Point');
      expect(const CanteenProfile(budget: 500).hasBudget, isTrue);
    });

    test('CanteenEntry.fromMap', () {
      final e = CanteenEntry.fromMap({
        'id': 3,
        'date': '2026-11-02',
        'kind': 'credit',
        'name': 'Maggi',
        'amount': 40,
        'method': 'khata',
      });
      expect(e.id, 3);
      expect(e.isCredit, isTrue);
      expect(e.amount, 40.0);
    });
  });

  group('backup', () {
    String sample() {
      return encodeBackup(
        meals: [
          {'date': '2026-11-01', 'meal_type': 'Morning', 'is_eaten': 1, 'skip_reason': null},
        ],
        extras: [
          {'date': '2026-11-01', 'meal_type': 'Night', 'name': 'Chai', 'amount': 10.0},
        ],
        canteen: [
          {'date': '2026-11-02', 'kind': 'credit', 'name': 'Maggi', 'amount': 40.0, 'method': 'khata'},
        ],
        prefs: {
          'canteen_name': 'Hostel Canteen',
          'fixed_meals': ['Morning'],
          'rate_same': '40',
        },
        now: DateTime(2026, 11, 16, 10, 30),
      );
    }

    test('round trip keeps everything', () {
      final d = decodeBackup(sample());
      expect(d.meals.length, 1);
      expect(d.extras.length, 1);
      expect(d.canteen.length, 1);
      expect(d.totalRows, 3);
      expect(d.skipped, 0);
      expect(d.prefs['canteen_name'], 'Hostel Canteen');
      expect(d.prefs['fixed_meals'], ['Morning']);
      expect(d.created, DateTime(2026, 11, 16, 10, 30));
      expect(d.canteen.first['method'], 'khata');
    });

    test('rejects text that is not a Meal Streak backup', () {
      expect(() => decodeBackup('hello'), throwsFormatException);
      expect(() => decodeBackup('[1,2,3]'), throwsFormatException);
      expect(() => decodeBackup('{"app":"other","version":1}'), throwsFormatException);
      expect(() => decodeBackup('{"app":"meal_streak","version":99}'), throwsFormatException);
    });

    test('skips damaged rows instead of crashing', () {
      final text = jsonEncode({
        'app': 'meal_streak',
        'version': 1,
        'meals': [
          {'date': '2026-11-01', 'meal_type': 'Morning', 'is_eaten': 1},
          {'date': 'bad-date', 'meal_type': 'Morning', 'is_eaten': 1},
          {'date': '2026-11-02', 'meal_type': 'Brunch', 'is_eaten': 1},
          5,
        ],
        'canteen_entries': [
          {'date': '2026-11-01', 'kind': 'spend', 'name': 'Chai', 'amount': -5},
          {'date': '2026-11-01', 'kind': 'gift', 'name': 'Chai', 'amount': 5},
          {'date': '2026-11-01', 'kind': 'spend', 'name': 'Chai', 'amount': 5, 'method': 'weird'},
        ],
      });
      final d = decodeBackup(text);
      expect(d.meals.length, 1);
      expect(d.canteen.length, 1);
      expect(d.canteen.first['method'], 'cash'); // unknown method falls back
      expect(d.skipped, 5); // 3 bad meals + 2 bad canteen rows
    });

    test('only allow-listed preferences are restored (never the PIN)', () {
      final text = jsonEncode({
        'app': 'meal_streak',
        'version': 1,
        'prefs': {
          'lock_hash': 'abc',
          'lock_enabled': true,
          'canteen_upi': 'canteen@okaxis',
        },
      });
      final d = decodeBackup(text);
      expect(d.prefs.containsKey('lock_hash'), isFalse);
      expect(d.prefs.containsKey('lock_enabled'), isFalse);
      expect(d.prefs['canteen_upi'], 'canteen@okaxis');
    });

    test('a skipped meal keeps its reason, an eaten one drops it', () {
      final text = jsonEncode({
        'app': 'meal_streak',
        'version': 1,
        'meals': [
          {'date': '2026-11-01', 'meal_type': 'Morning', 'is_eaten': 0, 'skip_reason': 'Sick'},
          {'date': '2026-11-01', 'meal_type': 'Night', 'is_eaten': 1, 'skip_reason': 'Sick'},
        ],
      });
      final d = decodeBackup(text);
      expect(d.meals[0]['skip_reason'], 'Sick');
      expect(d.meals[1]['skip_reason'], isNull);
    });
  });
}
