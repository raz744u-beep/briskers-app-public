import 'package:flutter/material.dart';

Future<bool> showOfflineJobPurgeConfirmation(BuildContext context, {
  required String jobLabel, required List<Map<String, dynamic>> items,
}) async {
  final result = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('Permanently delete $jobLabel?'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('These records have not been uploaded. Delete this exact selection from this device and cancel its queued uploads:'),
          const SizedBox(height: 8),
          for (final item in items) Text(offlinePurgeItemLabel(item)),
          const SizedBox(height: 12),
          const Text('This cannot be undone. No recovery copy is kept. Saved offline work belonging to other Jobs is not included.'),
          const SizedBox(height: 8),
          const Text('Old record IDs stay blocked on this device. When connected, the app registers deletion markers so another phone cannot recreate those records. If any upload has already reached the server, reconciliation is required.'),
          const SizedBox(height: 8),
          const Text('Provisional local labels are released after cleanup. Server-issued numbers require server verification. Deleting payment records does not refund or reverse bank or card transactions.'),
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Permanently delete these records')),
      ],
    ));
  return result == true;
}

String offlinePurgeItemLabel(Map<String, dynamic> item) {
  final kind = item['kind'];
  final label = item['label']?.toString() ?? 'Linked record';
  if (kind == 'payment' || kind == 'transaction') {
    final cents = item['amount_cents'];
    final amount = cents is num ? (cents / 100).toStringAsFixed(2) : item['amount']?.toString() ?? 'Amount unavailable';
    final method = item['method_name'] ?? item['method_label'] ?? item['account_name'] ?? 'Method details unavailable';
    return '$label · ${item['currency'] ?? ''} $amount · $method';
  }
  if (kind == 'local_documents') {
    final type = item['document_kind'] == 'estimate' ? 'Estimate' : item['document_kind'] == 'invoice' ? 'Invoice' : 'Document';
    return '$type $label';
  }
  return label;
}
