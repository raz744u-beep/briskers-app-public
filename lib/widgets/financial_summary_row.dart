import 'package:flutter/material.dart';

/// Compact, informational emphasis for invoice/estimate totals.
/// This widget never calculates or changes any financial amounts.
enum FinancialSummaryTone { subtotal, total, balanceDue }

class FinancialSummaryRow extends StatelessWidget {
  const FinancialSummaryRow({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final FinancialSummaryTone tone;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color background;
    final Color foreground;
    switch (tone) {
      case FinancialSummaryTone.subtotal:
        background = dark ? const Color(0xFF27374A) : const Color(0xFFE6EDF5);
        foreground = dark ? const Color(0xFFE8F0FA) : const Color(0xFF172A46);
        break;
      case FinancialSummaryTone.total:
        background = dark ? const Color(0xFF183F2C) : const Color(0xFFE2F6E4);
        foreground = dark ? const Color(0xFFB2EBC4) : const Color(0xFF086B3E);
        break;
      case FinancialSummaryTone.balanceDue:
        background = dark ? const Color(0xFF4D252B) : const Color(0xFFFBE5E5);
        foreground = dark ? const Color(0xFFFFB8B8) : const Color(0xFFAF2027);
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
