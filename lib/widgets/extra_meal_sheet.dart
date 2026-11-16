import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/notifiers.dart';
import '../data/database_helper.dart';

/// Bottom sheet to add an extra craving. Returns true when something was added.
Future<bool> showAddExtraSheet(BuildContext context, {required DateTime date}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddExtraSheet(date: date),
  );
  return added == true;
}

class _AddExtraSheet extends StatefulWidget {
  final DateTime date;
  const _AddExtraSheet({required this.date});

  @override
  State<_AddExtraSheet> createState() => _AddExtraSheetState();
}

class _AddExtraSheetState extends State<_AddExtraSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  late String _mealType;
  List<QuickPick> _picks = mergeQuickPicks(const <QuickPick>[]);
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final isToday = widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
    _mealType = isToday ? mealTypeForHour(now.hour) : 'Morning';
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
      final mine = await DatabaseHelper.instance.getFrequentExtras(limit: 8);
      if (!mounted) return;
      setState(() => _picks = mergeQuickPicks(mine));
    } catch (e) {
      debugPrint('Quick picks error: $e');
    }
  }

  void _applyPick(QuickPick p) {
    HapticFeedback.selectionClick();
    setState(() {
      _nameCtrl.text = p.name;
      _amountCtrl.text = formatAmount(p.amount);
      _error = null;
    });
  }

  void _addToAmount(int delta) {
    HapticFeedback.selectionClick();
    final current = parseAmount(_amountCtrl.text) ?? 0;
    setState(() {
      _amountCtrl.text = formatAmount(current + delta);
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    final amount = parseAmount(_amountCtrl.text);
    if (name.isEmpty) {
      setState(() => _error = 'Enter what you ate');
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
      await DatabaseHelper.instance.addExtraMeal(
        dateKey(widget.date),
        _mealType,
        name,
        amount,
      );
      dbUpdateNotifier.value++;
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Add extra error: $e');
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
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Add Extra Craving',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('EEEE, d MMM').format(widget.date),
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
              const SizedBox(height: 16),
              _label('QUICK PICKS', c),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _picks) _pickChip(p, c),
                ],
              ),
              const SizedBox(height: 16),
              _label('MEAL', c),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < mealMetas.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: _mealChip(mealMetas[i], c)),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 40,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: _inputDecoration('What did you eat?', c).copyWith(
                  counterText: '',
                  prefixIcon: const Icon(Icons.restaurant_rounded, size: 18),
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
                onSubmitted: (_) => _save(),
                decoration: _inputDecoration('Amount (₹)', c).copyWith(
                  prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final v in const [10, 20, 50, 100]) ...[
                    GestureDetector(
                      onTap: () => _addToAmount(v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        margin: const EdgeInsets.only(right: 8),
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
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tomatoRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Add Craving',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, AppColors c) {
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

  InputDecoration _inputDecoration(String label, AppColors c) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: tomatoRed, width: 1.5),
      ),
    );
  }

  Widget _pickChip(QuickPick p, AppColors c) {
    return GestureDetector(
      onTap: () => _applyPick(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tomatoRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tomatoRed.withValues(alpha: 0.25)),
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
                color: tomatoRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mealChip(MealMeta meta, AppColors c) {
    final selected = _mealType == meta.type;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _mealType = meta.type);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? meta.color.withValues(alpha: 0.14) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? meta.color : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(meta.icon, size: 18, color: selected ? meta.color : c.textFaint),
            const SizedBox(height: 4),
            Text(
              meta.type,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? meta.color : c.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
