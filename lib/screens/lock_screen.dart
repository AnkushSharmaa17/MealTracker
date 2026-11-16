import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/notifiers.dart';
import '../services/app_lock_service.dart';
import '../services/backup_service.dart';
import '../widgets/pin_pad.dart';

/// Full-screen overlay shown while the app is locked.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const int _maxAttempts = 5;
  static const int _lockoutSeconds = 30;

  int _attempts = 0;
  int _cooldown = 0;
  String? _error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onPin(String pin) async {
    if (_cooldown > 0) return;
    final ok = await AppLockService.instance.verify(pin);
    if (!mounted) return;
    if (ok) {
      appLockedNotifier.value = false;
      return;
    }
    _attempts++;
    if (_attempts >= _maxAttempts) {
      _startCooldown();
    } else {
      setState(() => _error = 'Wrong PIN ($_attempts/$_maxAttempts)');
    }
  }

  void _startCooldown() {
    setState(() {
      _attempts = 0;
      _cooldown = _lockoutSeconds;
      _error = 'Too many attempts. Try again in $_cooldown s';
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) {
          _cooldown = 0;
          _error = null;
          t.cancel();
        } else {
          _error = 'Too many attempts. Try again in $_cooldown s';
        }
      });
    });
  }

  Future<void> _forgotPin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Forgot PIN?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'There is no way to recover a forgotten PIN because nothing is stored online.\n\n'
          'You can reset the app, but this will DELETE ALL your data '
          '(meals, extras, canteen, settings) from this phone.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: tomatoRed),
            child: const Text('Delete all & reset',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await BackupService.eraseEverything();
      await AppLockService.instance.disable();
      appLockedNotifier.value = false;
    } catch (e) {
      debugPrint('Reset error: $e');
      if (!mounted) return;
      setState(() => _error = 'Reset failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.bg,
      child: SafeArea(
        child: PinPad(
          title: 'Enter PIN',
          subtitle: 'Meal Streak is locked',
          errorText: _error,
          enabled: _cooldown == 0,
          onCompleted: _onPin,
          bottomAction: TextButton(
            onPressed: _forgotPin,
            child: Text('Forgot PIN?',
                style: TextStyle(color: c.textMuted, fontSize: 12)),
          ),
        ),
      ),
    );
  }
}

enum PinPageMode { setup, verify }

/// Route used from Settings to create a PIN or to confirm the current one.
/// Pops with `true` on success.
class PinPage extends StatefulWidget {
  final PinPageMode mode;
  const PinPage({super.key, required this.mode});

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  String? _first;
  String? _error;
  int _attempts = 0;

  Future<void> _onPin(String pin) async {
    if (widget.mode == PinPageMode.verify) {
      final ok = await AppLockService.instance.verify(pin);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        _attempts++;
        setState(() => _error = 'Wrong PIN ($_attempts)');
      }
      return;
    }

    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (_first == pin) {
      try {
        await AppLockService.instance.setPin(pin);
        if (!mounted) return;
        Navigator.pop(context, true);
      } catch (e) {
        debugPrint('Set PIN error: $e');
        if (!mounted) return;
        setState(() {
          _first = null;
          _error = 'Could not save PIN. Try again.';
        });
      }
    } else {
      setState(() {
        _first = null;
        _error = 'PINs did not match. Start again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    String title;
    String subtitle;
    if (widget.mode == PinPageMode.verify) {
      title = 'Enter current PIN';
      subtitle = 'Confirm it is you to turn off the lock';
    } else if (_first == null) {
      title = 'Create a PIN';
      subtitle = 'Choose 4 digits. If you forget it, the app must be reset '
          'and all data is erased, so keep a backup.';
    } else {
      title = 'Confirm your PIN';
      subtitle = 'Enter the same 4 digits again';
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: PinPad(
          title: title,
          subtitle: subtitle,
          errorText: _error,
          onCompleted: _onPin,
        ),
      ),
    );
  }
}
