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
    // Some local graph previews already supply a human-readable label
    // containing amount and payment method. Do not append invented
    // "unavailable" values or duplicate those details.
    final cents = item['amount_cents'];
    final rawAmount = item['amount'];
    final amount = cents is num
        ? (cents / 100).toStringAsFixed(2)
        : rawAmount is num ? rawAmount.toStringAsFixed(2) : null;
    final rawMethod = item['method_name'] ??
        item['method_label'] ?? item['account_name'];
    final method = rawMethod?.toString().trim();
    if (amount == null && (method == null || method.isEmpty)) {
      return label;
    }
    final currency = item['currency']?.toString().trim();
    final alreadyShowsAmount = amount != null && label.contains(amount);
    final alreadyShowsMethod = method != null &&
        method.isNotEmpty &&
        label.toLowerCase().contains(method.toLowerCase());
    final pieces = <String>[
      label,
      if (amount != null && !alreadyShowsAmount)
        '${currency == null || currency.isEmpty ? '' : '$currency '}$amount',
      if (method != null && method.isNotEmpty && !alreadyShowsMethod) method,
    ];
    return pieces.join(' · ');
  }
  if (kind == 'local_documents') {
    final type = item['document_kind'] == 'estimate' ? 'Estimate' : item['document_kind'] == 'invoice' ? 'Invoice' : 'Document';
    return '$type $label';
  }
  return label;
}
