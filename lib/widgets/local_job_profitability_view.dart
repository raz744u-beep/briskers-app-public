import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../services/job_profitability_summary.dart';
import '../services/local_job_profitability.dart';
import 'job_profitability_summary_view.dart';

class LocalJobProfitabilityView extends StatelessWidget {
  const LocalJobProfitabilityView({
    super.key, required this.report, required this.onExpense,
  });
  final LocalJobProfitability report;
  final ValueChanged<String> onExpense;
  static String money(int? cents) => cents == null ? 'Not saved'
      : NumberFormat.simpleCurrency(locale: 'en_US').format(cents / 100);

  @override
  Widget build(BuildContext context) {
    final summary = JobProfitabilitySummary.fromRpc({
      'revenue': report.revenueCents == null ? null : report.revenueCents! / 100,
      'sales_tax': report.taxCents == null ? null : report.taxCents! / 100,
      'direct_cost': report.directCents == null ? null : report.directCents! / 100,
      'mechanic_cost': report.laborCents == null ? null : report.laborCents! / 100,
    });
    Widget amount(String title, int? cents, String key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(title)),
        const SizedBox(width: 8),
        Flexible(child: Text(money(cents), key: ValueKey(key),
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Saved local job figures',
            style: TextStyle(fontWeight: FontWeight.w700, color: BriskersColors.confirm)),
          const SizedBox(height: 8),
          if (summary != null) JobProfitabilitySummaryView(
            summary: summary,
            formatMoney: (n) => NumberFormat.simpleCurrency(locale: 'en_US').format(n),
          ) else ...[
            amount('Revenue excluding tax', report.revenueCents, 'local-job-revenue'),
            amount('Recorded expenses', report.directCents, 'local-job-expenses'),
            amount('Recorded labor cost', report.laborCents, 'local-job-labor'),
            amount('Total costs', report.costCents, 'local-job-cost'),
            amount('Profit', report.profitCents, 'local-job-profit'),
          ],
          const SizedBox(height: 8),
          const Text(
            'Recalculated from invoices, expenses and labor saved on this device. '
            'Labor includes completed work and recorded paid portions. Unfinished unpaid work, '
            'historical records not saved here, and weekly base pay or adjustments '
            'without a job allocation are not included.',
            style: TextStyle(fontSize: 12, color: BriskersColors.secondaryText),
          ),
          for (final issue in report.issues) Padding(
            padding: const EdgeInsets.only(top: 6), child: Text(issue),
          ),
          if (report.expenses.isNotEmpty) ...[
            const Divider(),
            const Text('Job expenses', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final expense in report.expenses) ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(expense['counterparty']?.toString() ?? 'Expense'),
              subtitle: Text([
                if (expense['remarks'] != null) expense['remarks'].toString(),
                if (expense['transaction_date'] != null) expense['transaction_date'].toString(),
                if ((expense['receipt_count'] as int? ?? 0) > 0) 'Receipt photos saved',
              ].join(' · ')),
              trailing: Text(money(expense['amount_minor'] is int
                ? expense['amount_minor'] as int : LocalJobProfitability.cents(expense['amount']))),
              onTap: () => onExpense(expense['id'].toString()),
            ),
          ],
        ]),
      ),
    );
  }
}
