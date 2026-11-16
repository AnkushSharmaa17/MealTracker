// Pure-Dart UPI helpers (no Flutter imports) - unit-testable.

class UpiPayee {
  final String id;
  final String name;
  const UpiPayee(this.id, this.name);
}

final RegExp _upiIdPattern =
    RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z][a-zA-Z0-9.]{1,63}$');

bool isValidUpiId(String value) => _upiIdPattern.hasMatch(value.trim());

String _decode(String s) {
  try {
    return Uri.decodeQueryComponent(s);
  } catch (_) {
    return s;
  }
}

Map<String, String> _parseQuery(String query) {
  final out = <String, String>{};
  for (final part in query.split('&')) {
    if (part.isEmpty) continue;
    final i = part.indexOf('=');
    final key = i < 0 ? part : part.substring(0, i);
    final value = i < 0 ? '' : part.substring(i + 1);
    out[_decode(key).trim().toLowerCase()] = _decode(value).trim();
  }
  return out;
}

/// Understands the text inside a UPI QR code:
///   upi://pay?pa=canteen@okaxis&pn=Hostel%20Canteen&cu=INR
/// or a bare UPI id such as "canteen@okaxis".
/// Returns null when the text is not a valid UPI payee.
UpiPayee? parseUpiPayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  if (text.toLowerCase().startsWith('upi:')) {
    final q = text.indexOf('?');
    if (q < 0 || q == text.length - 1) return null;
    final params = _parseQuery(text.substring(q + 1));
    final pa = params['pa'] ?? '';
    if (!isValidUpiId(pa)) return null;
    final name = params['pn'] ?? '';
    return UpiPayee(pa, name.length > 60 ? name.substring(0, 60) : name);
  }

  if (isValidUpiId(text)) return UpiPayee(text, '');
  return null;
}

/// Builds the deep link that opens the user's UPI app (PhonePe, GPay, ...).
String buildUpiPayUrl({
  required String payeeId,
  required String payeeName,
  double? amount,
  String note = '',
}) {
  final b = StringBuffer('upi://pay?pa=${payeeId.trim()}');
  if (payeeName.trim().isNotEmpty) {
    b.write('&pn=${Uri.encodeComponent(payeeName.trim())}');
  }
  if (amount != null && amount > 0) {
    b.write('&am=${amount.toStringAsFixed(2)}');
  }
  b.write('&cu=INR');
  if (note.trim().isNotEmpty) {
    b.write('&tn=${Uri.encodeComponent(note.trim())}');
  }
  return b.toString();
}
