import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../core/billing.dart';
import '../core/constants.dart';
import '../core/format.dart';
import '../core/models.dart';

/// Detailed bill breakdown, shared by Home and History.
Future<void> showBillSheet(
  BuildContext context, {
  required String monthLabel,
  required MonthReport report,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _BillSheet(monthLabel: monthLabel, report: report),
  );
}

String buildBillSummaryText(String monthLabel, MonthReport report) {
  final bill = report.bill;
  final b = StringBuffer('Meal Streak - $monthLabel\n');
  for (final t in kMealTypes) {
    final n = bill.eaten(t);
    final rate = bill.rates.of(t);
    b.writeln('$t: $n meals x ₹${formatAmount(rate)}'
        ' = ${formatRupees(n * rate)}');
  }
  if (bill.fixedSkippedCost > 0) {
    b.writeln('Fixed meals (skipped): ${formatRupees(bill.fixedSkippedCost)}');
  }
  b.writeln('Mess total: ${formatRupees(bill.messTotal)}');
  b.writeln('Extra cravings: ${formatRupees(bill.extraTotal)}');
  b.write('TOTAL: ${formatRupees(bill.total)}');
  return b.toString();
}

class _BillSheet extends StatelessWidget {
  final String monthLabel;
  final MonthReport report;
  const _BillSheet({required this.monthLabel, required this.report});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bill = report.bill;
    final projected = report.projectedTotal(DateTime.now());

    return Container(
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: tomatoRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: tomatoRed, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        monthLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: c.textMuted,
                        ),
                      ),
                      Text(
                        'Bill Breakdown',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _label('MESS DIET', sageGreen),
            const SizedBox(height: 6),
            for (final t in kMealTypes)
              _row(
                c,
                '$t  •  ${bill.eaten(t)} × ₹${formatAmount(bill.rates.of(t))}',
                formatRupees(bill.eaten(t) * bill.rates.of(t)),
              ),
            _row(c, 'Eaten subtotal', formatRupees(bill.eatenCost), bold: true),
            if (bill.fixedSkippedCost > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tomatoRed.withValues(alpha: c.isDark ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tomatoRed.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 15, color: tomatoRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fixed Meals (Skipped)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tomatoRed,
                            ),
                          ),
                          Text(
                            'Charged even though skipped',
                            style: TextStyle(fontSize: 10, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatRupees(bill.fixedSkippedCost),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tomatoRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            _row(c, 'Mess total', formatRupees(bill.messTotal), bold: true),
            Divider(height: 24, color: c.border),
            _label('EXTRA CRAVINGS', tomatoRed),
            const SizedBox(height: 6),
            if (bill.extraTotal == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No extra meals this month',
                  style: TextStyle(
                    color: c.textMuted,
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                  ),
                ),
              )
            else
              _row(c, 'Extra total  •  ${report.extras.length} items',
                  formatRupees(bill.extraTotal),
                  bold: true),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [tomatoRed, tomatoDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: tomatoRed.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Bill',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        formatRupees(bill.total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                        ),
                      ),
                    ],
                  ),
                  if (projected != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Estimated month-end',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          '≈ ${formatRupees(projected)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  await Clipboard.setData(
                    ClipboardData(text: buildBillSummaryText(monthLabel, report)),
                  );
                  HapticFeedback.lightImpact();
                  messenger?.hideCurrentSnackBar();
                  messenger?.showSnackBar(
                    SnackBar(
                      content: const Text('Bill summary copied'),
                      backgroundColor: sageGreen,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy summary'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tomatoRed,
                  side: BorderSide(color: tomatoRed.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: color,
      ),
    );
  }

  Widget _row(AppColors c, String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: c.isDark ? Colors.white70 : Colors.black87,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: c.text,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
