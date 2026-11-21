import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../core/module_modal_theme.dart';

/// One confirmation for the exact authoritative graph. The service and server
/// independently validate this snapshot again; presentation is not permission.
Future<bool> showOwnerJobDeleteConfirmation(
  BuildContext context, {
  required Map<String, dynamic> snapshot,
  required bool canRetire,
  required List<String> blockedReasons,
  required bool offline,
}) async {
  final invoices = (snapshot['invoices'] as List?) ?? const [];
  final estimates = (snapshot['estimates_preserved'] as List?) ?? const [];
  final number = '${snapshot['job_number'] ?? ''}';
  final inventory = (snapshot['inventory'] as List?) ?? const [];
  final recordCount = inventory.fold<int>(0, (total, entry) {
    final count = entry is Map ? entry['count'] : null;
    return total + (count is int && count > 0 ? count : 0);
  });
  final result = await showModuleDialog<bool>(
    context: context,
    accent: BriskersColors.jobs,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete Job${number.isEmpty ? '' : ' $number'}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${invoices.length} linked invoice(s) to remove'),
            for (final raw in invoices)
              if (raw is Map)
                Text(
                  'Invoice ${raw['number'] ?? raw['document_number'] ?? raw['id']} · ${raw['status'] ?? ''}',
                ),
            if (estimates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${estimates.length} estimate(s) will be kept'),
              for (final raw in estimates)
                if (raw is Map)
                  Text(
                    'Estimate ${raw['number'] ?? raw['document_number'] ?? raw['id']}',
                  ),
            ],
            if (recordCount > 0)
              Text('$recordCount total record(s) in the confirmed selection'),
            const SizedBox(height: 12),
            if (canRetire) ...[
              const Text(
                'Remove this Job and its eligible linked records from active lists. An audit and recovery record will be kept; recovery requires an administrator. Document numbers will not be reused.',
              ),
              if (offline) ...[
                const SizedBox(height: 8),
                const Text(
                  'This uses the last verified preview. Deletion will be queued on this device and checked again when you reconnect. If the records changed, deletion will be refused and the Job will return for review.',
                ),
              ],
            ] else ...[
              const Text('This Job cannot be deleted safely.'),
              for (final reason in blockedReasons) Text(reason),
              const SizedBox(height: 8),
              const Text(
                'Payments and protected accounting history must be retained. Nothing has been deleted.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(canRetire ? 'Cancel' : 'Close'),
        ),
        if (canRetire)
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(offline ? 'Queue deletion' : 'Delete Job'),
          ),
      ],
    ),
  );
  return result == true;
}
