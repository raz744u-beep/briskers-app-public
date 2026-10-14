import 'package:flutter/material.dart';

import '../core/briskers_i18n.dart';
import '../services/job_profitability_summary.dart';

class JobProfitabilitySummaryView extends StatelessWidget {
  const JobProfitabilitySummaryView({
    super.key,
    required this.summary,
    required this.formatMoney,
  });

  final JobProfitabilitySummary summary;
  final String Function(num) formatMoney;

  @override
  Widget build(BuildContext context) {
    final profitColor = summary.profit < 0
        ? Colors.red.shade700
        : Colors.green.shade700;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(16) > 20;

        Widget amountRow(String key, num amount, {bool emphasized = false}) {
          final label = Text(
            tr(key),
            style: TextStyle(
              fontSize: emphasized ? 18 : 16,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
            ),
          );
          final value = Text(
            formatMoney(amount),
            style: TextStyle(
              fontSize: emphasized ? 22 : 17,
              fontWeight: FontWeight.w900,
              color: emphasized ? profitColor : null,
            ),
          );
          return Container(
            margin: EdgeInsets.only(bottom: emphasized ? 12 : 2),
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: emphasized ? 16 : 11,
            ),
            decoration: emphasized
                ? BoxDecoration(
                    color: profitColor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: profitColor.withValues(alpha: 0.28),
                    ),
                  )
                : null,
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, const SizedBox(height: 6), value],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: label),
                      const SizedBox(width: 16),
                      Flexible(child: value),
                    ],
                  ),
          );
        }

        final margin = summary.marginPercent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  tr('profitabilitySummary'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: profitColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    margin == null
                        ? tr('profitabilityMarginUnavailable')
                        : '${tr('profitabilityMargin')}: ${margin.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: profitColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            amountRow('profitabilityRevenueExTax', summary.revenue),
            amountRow('profitabilityTaxExcluded', summary.salesTax),
            amountRow('profitabilityPartsCost', summary.directCost),
            amountRow('profitabilityLaborCost', summary.mechanicCost),
            amountRow('profitabilityDirectCosts', summary.totalCost),
            const Divider(height: 18),
            amountRow(
              'profitabilityNetBeforeOverhead',
              summary.profit,
              emphasized: true,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr('profitabilityBasisNote'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
              ),
            ),
          ],
        );
      },
    );
  }
}
