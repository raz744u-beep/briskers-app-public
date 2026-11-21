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
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
        final columns = largeText || constraints.maxWidth < 280
            ? 1
            : constraints.maxWidth >= 640
            ? 4
            : 2;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 8) / columns;
        Widget card(
          String label,
          String value, {
          String? caption,
          bool highlight = false,
        }) => Container(
          width: cardWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: highlight
                ? profitColor.withValues(alpha: .08)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? profitColor.withValues(alpha: .25)
                  : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: highlight ? profitColor : scheme.onSurface,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
        Widget breakdown(String label, num value) {
          final name = Text(tr(label), style: const TextStyle(fontSize: 12));
          final amount = Text(
            formatMoney(value),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: largeText
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, amount],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 12),
                      amount,
                    ],
                  ),
          );
        }

        final margin = summary.marginPercent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                card(
                  tr('profitabilityRevenueCard'),
                  formatMoney(summary.revenue),
                  caption: tr('profitabilityRevenueExTax'),
                ),
                card(
                  tr('profitabilityCostsCard'),
                  formatMoney(summary.totalCost),
                  caption: tr('profitabilityDirectCosts'),
                ),
                card(
                  tr('profitabilityProfitCard'),
                  formatMoney(summary.profit),
                  caption: tr('profitabilityNetBeforeOverhead'),
                  highlight: true,
                ),
                card(
                  tr('profitabilityMargin'),
                  margin == null
                      ? tr('profitabilityMarginUnavailable')
                      : '${margin.toStringAsFixed(1)}%',
                  highlight: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            breakdown('profitabilityPartsCost', summary.directCost),
            breakdown('profitabilityLaborCost', summary.mechanicCost),
            breakdown('profitabilityTaxExcluded', summary.salesTax),
            const Divider(height: 16),
            Text(
              tr('profitabilityBasisNote'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}
