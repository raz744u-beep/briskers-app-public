import 'package:flutter/material.dart';

Future<bool> showOfflineJobPurgeConfirmation(BuildContext context, {
  required String jobLabel, required List<Map<String, dynamic>> items,
}) async {
  final result = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('Permanently delete $jobLabel?'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Delete the following locally stored records from this device:'),
          const SizedBox(height: 8),
          for (final item in items) Text(offlinePurgeItemLabel(item)),
          const SizedBox(height: 12),
          const Text('This cannot be undone. No recovery copy is kept. Saved offline work belonging to other Jobs is not included.'),
          const SizedBox(height: 8),
          const Text('Deletion markers stay on this device to prevent old records from returning. Cross-device synchronization of deletions is not enabled yet.'),
          const SizedBox(height: 8),
          const Text('Record numbers can be reused only after a local conflict check. Deleting payment records does not refund or reverse bank or card transactions.'),
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
