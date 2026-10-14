import 'package:flutter/material.dart';

import '../core/briskers_i18n.dart';

/// Review-only UI. The caller retains all conversion permissions and guards.
class EstimateMergeConfirmationDialog extends StatelessWidget {
  const EstimateMergeConfirmationDialog({
    super.key,
    required this.estimateTotal,
    required this.invoiceTotal,
    required this.combinedTotal,
  });
  final String estimateTotal;
  final String invoiceTotal;
  final String combinedTotal;
  @override
  Widget build(BuildContext context) {
    final es = BriskersLanguageController.instance.isSpanish;
    Widget amount(String label, String value, {bool total = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: total ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: total ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return AlertDialog(
      scrollable: true,
      title: Text(
        es ? 'Agregar presupuesto a factura' : 'Add Estimate to Invoice',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          amount(
            es ? 'Total del presupuesto' : 'Estimate total',
            estimateTotal,
          ),
          amount(
            es ? 'Total actual de la factura' : 'Current invoice total',
            invoiceTotal,
          ),
          const Divider(),
          amount(
            es ? 'Nuevo total de la factura' : 'New invoice total',
            combinedTotal,
            total: true,
          ),
          const SizedBox(height: 8),
          Text(
            es
                ? 'El presupuesto se cerrará y será de solo lectura después de agregarlo.'
                : 'The estimate will be closed and become read-only after it is added.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(es ? 'Cancelar' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(es ? 'Agregar a factura' : 'Add to Invoice'),
        ),
      ],
    );
  }
}
