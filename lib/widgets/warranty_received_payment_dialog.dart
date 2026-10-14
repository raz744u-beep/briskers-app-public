import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/warranty_payment_amounts.dart';

/// Confirms the amount actually received, not a calculator's suggested net.
/// Only returns a value; the caller retains all durable capture safeguards.
class WarrantyReceivedPaymentDialog extends StatefulWidget {
  const WarrantyReceivedPaymentDialog({super.key, this.initialGross,
    required this.processorFee, required this.remaining, required this.check});
  final num? initialGross;
  final num processorFee;
  final num remaining;
  final bool check;

  @override
  State<WarrantyReceivedPaymentDialog> createState() => _WarrantyReceivedPaymentDialogState();
}

class _WarrantyReceivedPaymentDialogState extends State<WarrantyReceivedPaymentDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialGross?.toStringAsFixed(2) ?? '');
  @override
  void dispose() { _amount.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final gross = num.tryParse(_amount.text.replaceAll(',', '').trim());
    final breakdown = WarrantyPaymentAmounts.fromReceipt(gross: gross,
      processorFee: widget.check ? 0 : widget.processorFee);
    final valid = breakdown != null && breakdown.grossCents > 0 &&
      breakdown.grossCents <= (widget.remaining * 100).round();
    String money(num value) => NumberFormat.currency(symbol: r'$').format(value);
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      scrollable: true,
      title: Text(tr('recordWarrantyReceipt')),
      content: SizedBox(width: 560, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('warrantyActualReceiptHelp')),
          const SizedBox(height: 16),
          TextField(controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('actualGrossReceived'),
              prefixText: r'$ ', border: const OutlineInputBorder())),
          const SizedBox(height: 16),
          Text('${tr('processorPassThrough')}: ${money(widget.check ? 0 : widget.processorFee)}'),
          Text('${tr('retainedReceipt')}: ${breakdown == null ? "—" : money(breakdown.retained)}'),
          const SizedBox(height: 8),
          Text(tr('warrantyFeeNoDoubleCharge')),
          if (!valid) Text(tr('warrantyReceiptInvalid'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: BriskersColors.invoices),
          onPressed: valid ? () {
            if (breakdown != null) Navigator.pop(context, breakdown.gross);
          } : null,
          child: Text(tr('recordReceivedPayment'))),
      ],
    );
  }
}
