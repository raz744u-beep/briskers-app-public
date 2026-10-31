import 'package:flutter/material.dart';

import '../../services/owner_job_deletion_v3_contract.dart';

Future<bool> showOwnerJobDeleteV3Confirmation(BuildContext context,
    {required JobDeletionV3Preview preview}) async {
  final snapshot = preview.snapshot;
  final canDelete = preview.canDelete;
  final requiresFinancialConsent = snapshot['requires_synthetic_consent'] == true;
  var noRealMoneyConfirmed = false;
  final number = snapshot['job_number']?.toString().trim() ?? '';
  final jobLabel = number.isEmpty ? 'Unnumbered Job' : 'Job $number';
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
      title: Text('Permanently delete $jobLabel?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('These records will be permanently deleted:'),
          Text(jobLabel),
          for (final category in ['invoices', 'estimates', 'payments', 'related_records']) ...[
            const SizedBox(height: 8),
            Text('${_heading(category)} (${(snapshot[category] as List).length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final raw in snapshot[category] as List)
              if (raw is Map)
                Text(category == 'payments'
                    ? '${raw['display_label']} · ${raw['currency']} ${raw['amount']} · ${raw['method_label']}'
                    : category == 'invoices' || category == 'estimates'
                        ? raw['number'] == null
                            ? '${raw['display_label']}'
                            : '${category == 'invoices' ? 'Invoice' : 'Estimate'} ${raw['number']} · ${raw['status'] ?? ''}'
                        : '${raw['display_label']}'),
          ],
          const SizedBox(height: 12),
          const Text('There is no undo or saved recovery copy in the app. Job, estimate and invoice numbers become available for reuse after deletion finishes. Old record IDs stay blocked so another phone cannot bring them back.'),
          const SizedBox(height: 8),
          const Text('Deleting payment records does not refund or reverse bank or card transactions. Previously sent or exported copies are not recalled.'),
          if (canDelete && requiresFinancialConsent) ...[
            const SizedBox(height: 12),
            const Text('Financial deletion requires a separate verified synthetic-record review. This does not refund money or undo a card or bank payment.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I have verified these are test-only records. No real money was received or paid.'),
              value: noRealMoneyConfirmed,
              onChanged: (checked) => setDialogState(() => noRealMoneyConfirmed = checked == true),
            ),
          ],
          if (preview.fromCache) ...[
            const SizedBox(height: 8),
            const Text('This is the last verified selection. Your request will wait for a connection. If any linked record changed, you must review and confirm again.'),
          ],
          if (!canDelete) ...[
            const SizedBox(height: 8),
            const Text('This selection needs review before deletion. Nothing has been deleted.'),
            for (final reason in snapshot['blocked_reasons'] as List)
              Text(reason is Map
                  ? '${reason['display_message'] ?? 'A shared or unverified linked record needs review.'}'
                  : 'A linked record needs review.'),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(canDelete ? 'Cancel' : 'Close')),
        if (canDelete)
          FilledButton(
            onPressed: requiresFinancialConsent && !noRealMoneyConfirmed
                ? null : () => Navigator.pop(dialogContext, true),
            child: Text(preview.fromCache ? 'Confirm permanent deletion when online' : 'Permanently delete these records')),
      ],
    )),
  );
  return result == true;
}

String _heading(String category) => switch (category) {
  'invoices' => 'Invoices', 'estimates' => 'Estimates',
  'payments' => 'Payments', _ => 'Other linked records',
};
