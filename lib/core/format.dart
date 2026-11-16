// Pure-Dart helpers (no Flutter imports) so they can be unit-tested anywhere.

/// Formats a number with Indian digit grouping: 1234567 -> ₹12,34,567.
String formatRupees(num value, {bool symbol = true}) {
  if (value is double && (value.isNaN || value.isInfinite)) {
    return symbol ? '₹0' : '0';
  }
  final n = value.round();
  final negative = n < 0;
  final digits = n.abs().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}${symbol ? '₹' : ''}$grouped';
}

/// Shows decimals only when needed: 40 -> "40", 33.333 -> "33.33", 10.5 -> "10.5".
String formatAmount(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

/// Locale-independent "yyyy-MM-dd" key used in the database.
String dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? parseDateKey(String s) {
  final p = s.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// Safe amount parser. Returns null for anything that is not a finite number.
double? parseAmount(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}

/// 540 -> "09:00 AM"
String formatClock(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final period = h24 >= 12 ? 'PM' : 'AM';
  var h = h24 % 12;
  if (h == 0) h = 12;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
}

/// Single-letter weekday (Mon -> "M").
String weekdayLetter(DateTime d) {
  const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return letters[d.weekday - 1];
}
