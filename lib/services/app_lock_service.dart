import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional 4-digit PIN lock. Fully offline: only a salted hash of the PIN is
/// stored on the device. This is a privacy convenience, not bank-grade
/// security (a 4-digit PIN can always be guessed by someone with the phone).
class AppLockService {
  static final AppLockService instance = AppLockService._();
  AppLockService._();

  static const String _kEnabled = 'lock_enabled';
  static const String _kHash = 'lock_hash';
  static const String _kSalt = 'lock_salt';

  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(_kEnabled) ?? false) &&
        (prefs.getString(_kHash) ?? '').isNotEmpty;
  }

  String _hash(String salt, String pin) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  String _newSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('PIN must be exactly 4 digits');
    }
    final prefs = await SharedPreferences.getInstance();
    final salt = _newSalt();
    await prefs.setString(_kSalt, salt);
    await prefs.setString(_kHash, _hash(salt, pin));
    await prefs.setBool(_kEnabled, true);
  }

  Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_kSalt) ?? '';
    final stored = prefs.getString(_kHash) ?? '';
    if (salt.isEmpty || stored.isEmpty) return false;
    return _hash(salt, pin) == stored;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEnabled);
    await prefs.remove(_kHash);
    await prefs.remove(_kSalt);
  }
}
