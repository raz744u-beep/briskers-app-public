import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/recorded_payroll_week.dart';
import '../../widgets/briskers_section_card.dart';

/// A saved weekly snapshot, never a new payment preparation or action.
class RecordedWeeklyPaymentCard extends StatelessWidget {
  const RecordedWeeklyPaymentCard({super.key, required this.recorded});
  final RecordedPayrollWeek recorded;
  static String money(int? cents) => cents == null
      ? 'Not saved'
      : NumberFormat.simpleCurrency(locale: 'en_US').format(cents / 100);
  Widget row(String label, String value, String key, {bool total = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: total ? FontWeight.w700 : null),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              key: ValueKey(key),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) => BriskersSectionCard(
    key: const Key('recorded-weekly-payment-summary'),
    title: 'Weekly Payment Summary',
    icon: Icons.payments_outlined,
    action: recorded.hasPayments
        ? const Text(
            'Recorded',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          )
        : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: recorded.hasPayments
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${recorded.payments.length} recorded payment${recorded.payments.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: BriskersColors.secondaryText),
                ),
                const SizedBox(height: 6),
                row(
                  'Paid Hours',
                  recorded.paidMinutes == null
                      ? 'Not saved'
                      : '${(recorded.paidMinutes! / 60).toStringAsFixed(2)} hrs',
                  'recorded-paid-hours',
                ),
                row(
                  'Labor Pay',
                  money(recorded.laborCents),
                  'recorded-labor-pay',
                ),
                if (recorded.baseCents == null || recorded.baseCents != 0)
                  row(
                    'Base Pay',
                    money(recorded.baseCents),
                    'recorded-base-pay',
                  ),
                row(
                  'Adjustments (+/−)',
                  money(recorded.adjustmentCents),
                  'recorded-adjustment',
                ),
                row('Gross Pay', money(recorded.grossCents), 'recorded-gross'),
                row(
                  'Advance repayment',
                  money(recorded.repaymentCents),
                  'recorded-repayment',
                ),
                Container(
                  decoration: BoxDecoration(
                    color: BriskersColors.confirm.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: row(
                    'Payment Total',
                    money(recorded.netCents),
                    'recorded-payment-total',
                    total: true,
                  ),
                ),
              ],
            )
          : const Text(
              'No recorded payments for this week.',
              style: TextStyle(color: BriskersColors.secondaryText),
            ),
    ),
  );
}
