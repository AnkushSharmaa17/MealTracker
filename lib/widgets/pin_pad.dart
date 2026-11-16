import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/constants.dart';

/// 4-digit PIN entry: dots + numeric keypad. Clears itself after every
/// completed entry; the parent decides what to do with the PIN.
class PinPad extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String> onCompleted;
  final Widget? bottomAction;

  const PinPad({
    super.key,
    required this.title,
    required this.onCompleted,
    this.subtitle,
    this.errorText,
    this.enabled = true,
    this.bottomAction,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  static const int _length = 4;
  String _digits = '';

  void _tap(String digit) {
    if (!widget.enabled || _digits.length >= _length) return;
    HapticFeedback.selectionClick();
    setState(() => _digits += digit);
    if (_digits.length == _length) {
      final pin = _digits;
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _digits = '');
        widget.onCompleted(pin);
      });
    }
  }

  void _backspace() {
    if (!widget.enabled || _digits.isEmpty || _digits.length >= _length) return;
    HapticFeedback.selectionClick();
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tomatoRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, color: tomatoRed, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: c.text,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _digits.length ? tomatoRed : Colors.transparent,
                      border: Border.all(
                        color: hasError ? tomatoRed : c.textFaint,
                        width: 1.6,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 36,
              child: Center(
                child: hasError
                    ? Text(
                        widget.errorText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: tomatoRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 8),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final d in row) _key(c, d)],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 84, height: 64),
                  _key(c, '0'),
                  _iconKey(c, Icons.backspace_outlined, _backspace),
                ],
              ),
            ),
            if (widget.bottomAction != null) ...[
              const SizedBox(height: 10),
              widget.bottomAction!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _key(AppColors c, String digit) {
    return SizedBox(
      width: 84,
      height: 64,
      child: Center(
        child: Material(
          color: c.surface,
          shape: CircleBorder(side: BorderSide(color: c.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.enabled ? () => _tap(digit) : null,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Center(
                child: Text(
                  digit,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: widget.enabled ? c.text : c.textFaint,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconKey(AppColors c, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 84,
      height: 64,
      child: Center(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.enabled ? onTap : null,
          child: SizedBox(
            width: 62,
            height: 62,
            child: Icon(icon, color: c.textMuted, size: 24),
          ),
        ),
      ),
    );
  }
}
