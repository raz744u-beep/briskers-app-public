import 'package:flutter/material.dart';

/// Returns null on Cancel, false for invoice-only, true for whole-Job cleanup.
/// The server rechecks the same eligibility inside its deleting transaction.
Future<bool?> showInvoiceDeletionChoice(
  BuildContext context, {
  required String invoiceNumber,
  Map<String,dynamic>? jobPlan,
}) async {
  final jobNumber=jobPlan?['job_number']?.toString() ?? '';
  final allowed=jobPlan?['can_delete'] == true;
  final invoiceRows=(jobPlan?['invoices'] as List?) ?? const [];
  final protectedReason=jobPlan?['reason']?.toString() ?? '';

  final choice=await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete invoice?'),
      content: Text([
        'Delete invoice #$invoiceNumber?',
        if (jobNumber.isNotEmpty && allowed)
          'You can also delete Job $jobNumber and its '
          '${invoiceRows.length} unpaid invoice'
          '${invoiceRows.length == 1 ? '' : 's'}. Estimates are kept.',
        if (jobNumber.isNotEmpty && !allowed && protectedReason.isNotEmpty)
          'Job $jobNumber cannot be deleted: $protectedReason.',
      ].join('\n\n')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext,'cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext,'invoice'),
          child: const Text('Delete invoice only'),
        ),
        if (allowed)
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext,'job'),
            child: const Text('Delete invoice and Job'),
          ),
      ],
    ),
  );
  if (choice == 'invoice') return false;
  if (choice == 'job') return true;
  return null;
}
