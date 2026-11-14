import '../../widgets/owner_confirmation_dialog.dart';
import 'package:flutter/material.dart';

Future<bool> showOfflineJobPurgeConfirmation(BuildContext context, {
  required String jobLabel, required List<Map<String, dynamic>> items,
}) async {
  final result = await showDialog<bool>(context:context,builder:(dialog)=>OwnerConfirmationDialog(
    title:'Permanently delete $jobLabel?',confirm:'Permanently delete these records',destructive:true,sections:[
      const Text('Records affected',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),
      Text('${items.length} locally stored records will be removed from this device:'),
      const SizedBox(height:8),
      for(final item in items)Padding(padding:const EdgeInsets.only(bottom:6),child:Text('• ${offlinePurgeItemLabel(item)}')),
      const Divider(height:24),
      const Text('Consequences',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),
      const Text('• Removes this Job and the linked records listed above.\n• Keeps customers, vehicles and other Jobs.\n• Deleting payment records does not refund or reverse bank or card transactions.\n• Freed numbers are reused only after a local conflict check.\n• This local deletion cannot be undone from this dialog.'),
      const SizedBox(height:16),
    ]));
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
