import 'package:flutter/material.dart';

Future<bool> showOfflineJobPurgeConfirmation(BuildContext context, {
  required String jobLabel, required List<Map<String, dynamic>> items,
}) async {
  bool technical(Map<String, dynamic> item) {
    final kind = item['kind']?.toString() ?? '';
    return kind != 'job' && kind != 'local_jobs' &&
        kind != 'invoice' && kind != 'estimate' &&
        kind != 'local_documents' && kind != 'payment' &&
        kind != 'transaction';
  }

  String section(Map<String, dynamic> item) {
    final kind = item['kind']?.toString() ?? '';
    if (kind == 'job' || kind == 'local_jobs') return 'Job';
    if (kind == 'invoice' || kind == 'estimate' ||
        kind == 'local_documents') return 'Invoices and estimates';
    if (kind == 'payment' || kind == 'transaction') return 'Payments';
    return 'Technical details';
  }

  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final item in items) {
    grouped.putIfAbsent(section(item), () => []).add(item);
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete $jobLabel?'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Review the local records before permanently deleting this test Job.'),
              const SizedBox(height: 14),
              const Row(children: [
                Icon(Icons.delete_outline, color: Colors.redAccent, size: 19),
                SizedBox(width: 8),
                Text('Will be deleted',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              for (final title in const ['Job','Invoices and estimates','Payments'])
                if (grouped[title]?.isNotEmpty == true) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  for (final item in grouped[title]!)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(offlinePurgeItemLabel(item)),
                    ),
                ],
              const SizedBox(height: 14),
              const Row(children: [
                Icon(Icons.shield_outlined, color: Colors.green, size: 19),
                SizedBox(width: 8),
                Text('Will be kept',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 6),
                child: Text('Customer, vehicle, and unrelated Jobs and invoices.'),
              ),
              const SizedBox(height: 12),
              const Text('Eligible deleted Job and invoice numbers may be reused after a local conflict check.'),
              const SizedBox(height: 8),
              ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
                leading: const Icon(Icons.data_object, size: 20),
                title: Text('Technical details (${items.where(technical).length})',
                    style: const TextStyle(fontSize: 14)),
                children: [
                  for (final item in items.where(technical))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(offlinePurgeItemLabel(item),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  if (items.where(technical).isEmpty)
                    const Text('No additional technical records.'),
                ],
              ),
              const Text(
                'This deletion affects local records only. Deleting payment records does not refund or reverse bank or card payments.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Permanently delete these records'),
        ),
      ],
    ),
  );
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
