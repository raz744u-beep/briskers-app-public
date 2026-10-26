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
    _ => null,
  };
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
    final label = status ??
        (offline ? 'Payment status not verified offline'
                 : 'Checking payment status…');
    final checking = status == null;
    final paid = status == 'Paid';
    final invoiceNeeded = status == 'Invoice needed';
    final color = checking
        ? const Color(0xFF697586)
        : paid
            ? const Color(0xFF169B62)
            : invoiceNeeded
                ? const Color(0xFFC62828)
                : const Color(0xFFE58A00);
    final icon = checking
        ? Icons.info_outline
        : paid
            ? Icons.check_circle_outline
            : invoiceNeeded
                ? Icons.receipt_long_outlined
                : Icons.hourglass_bottom_outlined;

    // Same height in loading, saved-offline and resolved states. Otherwise
    // the tiles below jump after an async jobDocuments/payment refresh.
    return SizedBox(
      height: 96,
      child: Card(
        margin: EdgeInsets.zero,
        color: color.withValues(alpha: 0.08),
        child: ListTile(
          leading: Icon(icon, color: color),
          title: const Text(
            'Financial status',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
