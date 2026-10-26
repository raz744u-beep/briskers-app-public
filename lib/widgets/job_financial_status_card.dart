import 'package:flutter/material.dart';

/// Convert the last synchronized payment state already shown on the Jobs list
/// into the first-frame Financial status label. Unknown must stay unknown;
/// never infer "Paid" from an empty, unhydrated invoice list.
String? savedJobFinancialStatus(Object? paymentState) {
  final value = paymentState?.toString().trim().toLowerCase() ?? '';
  return switch (value) {
    'paid' => 'Paid',
    'awaiting_clearance' => 'Awaiting payment clearance',
    'awaiting_payment' => 'Awaiting payment',
    'invoice_needed' => 'Invoice needed',
    _ => null,
  };
}

/// Derive only a *last verified* status from fully saved invoice detail.
/// A bare index row, missing payment totals, zero-total invoice, or estimate
/// does not prove Paid and must stay Not verified.
String? cachedVerifiedJobPaymentState(
  List<Map<String, dynamic>> savedInvoiceDetails,
) {
  final invoices = savedInvoiceDetails.where(
    (document) => document['kind']?.toString() == 'invoice',
  ).toList();
  if (invoices.isEmpty) return null;
  num total = 0;
  num paid = 0;
  num pending = 0;
  for (final invoice in invoices) {
    if (!invoice.containsKey('total_amount') ||
        !invoice.containsKey('paid_amount')) return null;
    final amount = num.tryParse(invoice['total_amount']?.toString() ?? '');
    final receipt = num.tryParse(invoice['paid_amount']?.toString() ?? '');
    if (amount == null || receipt == null ||
        !amount.isFinite || !receipt.isFinite ||
        amount <= 0 || receipt < 0) return null;
    final awaiting = num.tryParse(
      invoice['pending_payment']?.toString() ?? '0',
    );
    if (awaiting == null || !awaiting.isFinite || awaiting < 0) return null;
    total += amount;
    paid += receipt;
    pending += awaiting;
  }
  if (paid >= total - 0.005) return 'paid';
  if (pending > 0 && paid + pending >= total - 0.005) {
    return 'awaiting_clearance';
  }
  return 'awaiting_payment';
}

/// Keeps a completed Job's financial-status footprint stable while its linked
/// invoice/payment data is being verified. Never infer a paid/unpaid state from
/// an empty or not-yet-loaded document list.
class JobFinancialStatusCard extends StatelessWidget {
  const JobFinancialStatusCard({
    super.key,
    required this.status,
    this.offline = false,
  });

  /// Null means payment status is not yet verified.
  final String? status;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    // A compact, single-line status belongs next to its label, not in a
    // second tall panel. Never display a loading spinner or fabricate Paid
    // when no local/verified payment state is available.
    final label = status ?? 'Not verified';
    final unknown = status == null;
    final paid = status == 'Paid';
    final invoiceNeeded = status == 'Invoice needed';
    final color = unknown
        ? const Color(0xFF697586)
        : paid
            ? const Color(0xFF169B62)
            : invoiceNeeded
                ? const Color(0xFFC62828)
                : const Color(0xFFE58A00);
    final icon = unknown
        ? Icons.info_outline
        : paid
            ? Icons.check_circle_outline
            : invoiceNeeded
                ? Icons.receipt_long_outlined
                : Icons.hourglass_bottom_outlined;

    return SizedBox(
      height: 50,
      child: Card(
        margin: EdgeInsets.zero,
        color: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Financial status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  key: const ValueKey('job-financial-status-value'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
