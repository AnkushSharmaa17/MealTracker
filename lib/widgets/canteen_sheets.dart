import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../core/canteen.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/notifiers.dart';
import '../core/upi.dart';
import '../data/database_helper.dart';
import '../screens/canteen_scan_screen.dart';
import '../services/canteen_settings.dart';

// ---------------------------------------------------------------- shared UI

BoxDecoration _sheetDecoration(AppColors c) {
  return BoxDecoration(
    color: c.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
  );
}

Widget _grabHandle(AppColors c) {
  return Center(
    child: Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: c.border,
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}

Widget _fieldLabel(AppColors c, String text) {
  return Text(
    text,
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      color: c.textMuted,
    ),
  );
}

InputDecoration _decoration(String label, {IconData? icon, Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    isDense: true,
    prefixIcon: icon == null ? null : Icon(icon, size: 18),
    suffixIcon: suffix,
    counterText: '',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: canteenTeal, width: 1.5),
    ),
  );
}

Widget _amountChips(void Function(int) onAdd, AppColors c) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in const [10, 20, 50, 100, 500])
        GestureDetector(
          onTap: () => onAdd(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border),
            ),
            child: Text(
              '+$v',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget _primaryButton({
  required String label,
  required VoidCallback? onPressed,
  IconData? icon,
  bool busy = false,
}) {
  return SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: canteenTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
    ),
  );
}

// ------------------------------------------------------------- entry sheet

/// Add a canteen entry (paid / udhaar / settlement). Returns true when saved.
Future<bool> showCanteenEntrySheet(
  BuildContext context, {
  String kind = kKindSpend,
  double? amount,
  String? name,
  String method = 'cash',
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _EntrySheet(
      initialKind: kind,
      initialAmount: amount,
      initialName: name,
      initialMethod: method,
    ),
  );
  return saved == true;
}

class _EntrySheet extends StatefulWidget {
  final String initialKind;
  final double? initialAmount;
  final String? initialName;
  final String initialMethod;

  const _EntrySheet({
    required this.initialKind,
    required this.initialAmount,
    required this.initialName,
    required this.initialMethod,
  });

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  late String _kind;
  late String _method;
  DateTime _date = DateTime.now();
  List<QuickPick> _picks = mergeQuickPicks(const <QuickPick>[]);
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _method = _kind == kKindCredit ? 'khata' : widget.initialMethod;
    if (widget.initialName != null) _nameCtrl.text = widget.initialName!;
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _amountCtrl.text = formatAmount(widget.initialAmount!);
    }
    _loadPicks();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPicks() async {
    try {
      final mine = await DatabaseHelper.instance.getCanteenFrequent(limit: 8);
      if (!mounted) return;
      setState(() => _picks = mergeQuickPicks(mine));
    } catch (e) {
      debugPrint('Canteen picks error: $e');
    }
  }

  void _setKind(String kind) {
    HapticFeedback.selectionClick();
    setState(() {
      _kind = kind;
      _error = null;
      if (kind == kKindCredit) {
        _method = 'khata';
      } else if (_method == 'khata') {
        _method = 'cash';
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    var name = _nameCtrl.text.trim();
    final amount = parseAmount(_amountCtrl.text);

    if (_kind == kKindSettle && name.isEmpty) name = 'Udhaar settled';
    if (name.isEmpty) {
      setState(() => _error = 'Enter what you bought');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (amount > 100000) {
      setState(() => _error = 'Amount is too large');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DatabaseHelper.instance.addCanteenEntry(
        date: dateKey(_date),
        kind: _kind,
        name: name,
        amount: amount,
        method: _kind == kKindCredit ? 'khata' : _method,
      );
      dbUpdateNotifier.value++;
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Add canteen entry error: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final showMethods = _kind != kKindCredit;
    final showPicks = _kind != kKindSettle;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: _sheetDecoration(c),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _grabHandle(c),
              const SizedBox(height: 18),
              Text(
                'Add Canteen Entry',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _kindChip(c, kKindSpend, 'Paid', Icons.payments_rounded, canteenTeal),
                  const SizedBox(width: 8),
                  _kindChip(c, kKindCredit, 'Udhaar', Icons.bookmark_added_rounded, streakAmber),
                  const SizedBox(width: 8),
                  _kindChip(c, kKindSettle, 'Settle', Icons.task_alt_rounded, sageGreen),
                ],
              ),
              if (showPicks) ...[
                const SizedBox(height: 16),
                _fieldLabel(c, 'QUICK PICKS'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final p in _picks) _pickChip(c, p)],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 40,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: _decoration(
                  _kind == kKindSettle ? 'Note (optional)' : 'What did you buy?',
                  icon: Icons.restaurant_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: _decoration('Amount (₹)', icon: Icons.currency_rupee),
              ),
              const SizedBox(height: 10),
              _amountChips((v) {
                HapticFeedback.selectionClick();
                final current = parseAmount(_amountCtrl.text) ?? 0;
                setState(() {
                  _amountCtrl.text = formatAmount(current + v);
                  _error = null;
                });
              }, c),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_rounded,
                                size: 16, color: canteenTeal),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                DateFormat('EEE, d MMM yyyy').format(_date),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showMethods) ...[
                    const SizedBox(width: 8),
                    _methodChip(c, 'cash', 'Cash'),
                    const SizedBox(width: 6),
                    _methodChip(c, 'upi', 'UPI'),
                  ],
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: tomatoRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _primaryButton(
                label: 'Save Entry',
                onPressed: _saving ? null : _save,
                busy: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindChip(AppColors c, String kind, String label, IconData icon, Color color) {
    final selected = _kind == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setKind(kind),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: selected ? color : c.textFaint),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodChip(AppColors c, String method, String label) {
    final selected = _method == method;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _method = method);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? canteenTeal.withValues(alpha: 0.14) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? canteenTeal : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? canteenTeal : c.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _pickChip(AppColors c, QuickPick p) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _nameCtrl.text = p.name;
          _amountCtrl.text = formatAmount(p.amount);
          _error = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: canteenTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: canteenTeal.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '₹${formatAmount(p.amount)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: canteenTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- pay sheet

class PayRequest {
  final double amount;
  final String kind;
  final String note;
  const PayRequest({
    required this.amount,
    required this.kind,
    required this.note,
  });
}

/// Collects amount + purpose before opening the user's UPI app.
Future<PayRequest?> showCanteenPaySheet(
  BuildContext context, {
  required CanteenProfile profile,
  double? suggested,
}) {
  return showModalBottomSheet<PayRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PaySheet(profile: profile, suggested: suggested),
  );
}

class _PaySheet extends StatefulWidget {
  final CanteenProfile profile;
  final double? suggested;
  const _PaySheet({required this.profile, required this.suggested});

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  String _kind = kKindSpend;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.suggested;
    if (s != null && s > 0) {
      _amountCtrl.text = formatAmount(s);
      _kind = kKindSettle;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseAmount(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (amount > 100000) {
      setState(() => _error = 'UPI limit is ₹1,00,000 per payment');
      return;
    }
    final note = _noteCtrl.text.trim();
    Navigator.pop(
      context,
      PayRequest(
        amount: amount,
        kind: _kind,
        note: note.isEmpty
            ? (_kind == kKindSettle ? 'Udhaar settled' : 'Canteen payment')
            : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final p = widget.profile;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: _sheetDecoration(c),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _grabHandle(c),
              const SizedBox(height: 18),
              Text(
                'Pay via UPI',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: canteenTeal.withValues(alpha: c.isDark ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: canteenTeal.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_rounded,
                        color: canteenTeal, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: c.text,
                            ),
                          ),
                          Text(
                            p.upiId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
                decoration: _decoration('Amount (₹)', icon: Icons.currency_rupee),
              ),
              const SizedBox(height: 10),
              _amountChips((v) {
                HapticFeedback.selectionClick();
                final current = parseAmount(_amountCtrl.text) ?? 0;
                setState(() {
                  _amountCtrl.text = formatAmount(current + v);
                  _error = null;
                });
              }, c),
              const SizedBox(height: 16),
              _fieldLabel(c, 'THIS PAYMENT IS FOR'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _purposeChip(c, kKindSpend, 'Purchase'),
                  const SizedBox(width: 8),
                  _purposeChip(c, kKindSettle, 'Settle udhaar'),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration('Note (optional)', icon: Icons.notes_rounded),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: tomatoRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Payment is made inside your UPI app. This app never sees your '
                'PIN or bank details and only adds an entry after you confirm.',
                style: TextStyle(fontSize: 10, color: c.textFaint, height: 1.4),
              ),
              const SizedBox(height: 14),
              _primaryButton(
                label: 'Open UPI app',
                icon: Icons.open_in_new_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _purposeChip(AppColors c, String kind, String label) {
    final selected = _kind == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _kind = kind);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? canteenTeal.withValues(alpha: 0.14) : c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? canteenTeal : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? canteenTeal : c.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ QR + verify

/// Opens the scanner, then makes the user verify the payee before it is used.
/// Returns null when cancelled.
Future<UpiPayee?> scanAndConfirmPayee(BuildContext context) async {
  final payee = await Navigator.of(context).push<UpiPayee>(
    MaterialPageRoute<UpiPayee>(builder: (_) => const CanteenScanScreen()),
  );
  if (payee == null || !context.mounted) return null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Is this your canteen?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Name', style: TextStyle(fontSize: 11)),
          Text(payee.name.isEmpty ? '(not in QR)' : payee.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('UPI ID', style: TextStyle(fontSize: 11)),
          Text(payee.id,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text(
            'Check this carefully. A fake QR sticker can point to someone else.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: canteenTeal),
          child: const Text('Use this', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  return ok == true ? payee : null;
}

// ---------------------------------------------------------- settings sheet

/// Canteen name, UPI id (type or scan) and monthly budget. Returns true when
/// something was saved.
Future<bool> showCanteenSettingsSheet(
  BuildContext context, {
  required CanteenProfile profile,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SettingsSheet(profile: profile),
  );
  return saved == true;
}

class _SettingsSheet extends StatefulWidget {
  final CanteenProfile profile;
  const _SettingsSheet({required this.profile});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _upiCtrl;
  late final TextEditingController _budgetCtrl;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.name);
    _upiCtrl = TextEditingController(text: widget.profile.upiId);
    _budgetCtrl = TextEditingController(
      text: widget.profile.hasBudget ? formatAmount(widget.profile.budget) : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _upiCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final payee = await scanAndConfirmPayee(context);
    if (payee == null || !mounted) return;
    setState(() {
      _upiCtrl.text = payee.id;
      if (payee.name.isNotEmpty) _nameCtrl.text = payee.name;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final upi = _upiCtrl.text.trim();
    if (upi.isNotEmpty && !isValidUpiId(upi)) {
      setState(() => _error = 'This is not a valid UPI ID (example: name@bank)');
      return;
    }
    double budget = 0;
    if (_budgetCtrl.text.trim().isNotEmpty) {
      final parsed = parseAmount(_budgetCtrl.text);
      if (parsed == null || parsed < 0 || parsed > 1000000) {
        setState(() => _error = 'Enter a valid budget');
        return;
      }
      budget = parsed;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await CanteenSettings.saveProfile(name: _nameCtrl.text, upiId: upi);
      await CanteenSettings.saveBudget(budget);
      dbUpdateNotifier.value++;
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save canteen settings error: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: _sheetDecoration(c),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _grabHandle(c),
              const SizedBox(height: 18),
              Text(
                'Canteen Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Saved only on this phone.',
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Canteen name', icon: Icons.storefront_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _upiCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: _decoration(
                  'UPI ID',
                  icon: Icons.alternate_email_rounded,
                  suffix: IconButton(
                    tooltip: 'Scan QR',
                    icon: const Icon(Icons.qr_code_scanner_rounded,
                        color: canteenTeal),
                    onPressed: _scan,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _budgetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: _decoration(
                  'Monthly budget (₹) - leave empty for none',
                  icon: Icons.savings_rounded,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You get a notification at 80% and when the budget is crossed.',
                style: TextStyle(fontSize: 10, color: c.textFaint),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: tomatoRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _primaryButton(
                label: 'Save',
                onPressed: _saving ? null : _save,
                busy: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
