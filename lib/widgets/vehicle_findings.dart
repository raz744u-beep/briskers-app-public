import 'package:flutter/material.dart';

typedef FindingAction = Future<void> Function(Map<String, dynamic> finding);

/// The same vehicle-level findings surface in Customer Profile and Job Detail.
/// Identity is always the finding ID, never its body or its originating job.
class VehicleFindings extends StatelessWidget {
  const VehicleFindings({
    super.key,
    required this.findings,
    required this.onEdit,
    required this.onAddPhotos,
    required this.onAddToJob,
    required this.onResolve,
    required this.onReopen,
    required this.onInvoiceChanged,
    this.onRemoveFromJob,
    this.onDelete,
    this.photoBuilder,
    this.jobId,
    this.busy = false,
    this.canEdit = true,
    this.canManage = true,
    this.canIncludeOnInvoice = true,
    this.showVehicle = false,
  });

  final List<Map<String, dynamic>> findings;
  final FindingAction onEdit, onAddPhotos, onAddToJob, onResolve, onReopen;
  final FindingAction? onRemoveFromJob, onDelete;
  final Future<void> Function(Map<String, dynamic>, bool) onInvoiceChanged;
  final Widget Function(Map<String, dynamic>, Map<String, dynamic>)?
  photoBuilder;
  final String? jobId;
  final bool busy, canEdit, canManage, canIncludeOnInvoice, showVehicle;

  static List<Map<String, dynamic>> unique(List<Map<String, dynamic>> rows) => {
    for (final row in rows)
      if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
  }.values.toList();

  static String statusLabel(Map<String, dynamic> finding) =>
      switch (finding['status']?.toString()) {
        'resolved' => 'Resolved',
        'in_job' => 'In Job',
        _ => 'Open',
      };

  @override
  Widget build(BuildContext context) {
    final rows = unique(findings);
    final open = rows.where((row) => statusLabel(row) == 'Open').toList();
    final inJob = rows.where((row) => statusLabel(row) == 'In Job').toList();
    final resolved = rows
        .where((row) => statusLabel(row) == 'Resolved')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Open ${open.length} • In Job ${inJob.length} • Resolved ${resolved.length}',
            key: const ValueKey('vehicle-findings-counts'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (open.isEmpty && inJob.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No unresolved findings for this vehicle.'),
          ),
        for (final row in [...open, ...inJob])
          _maybeCollapsedRow(context, row,
              collapsed: open.length + inJob.length > 1),
        if (resolved.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('vehicle-findings-resolved'),
            title: Text(
              '${resolved.length} resolved finding${resolved.length == 1 ? '' : 's'}',
            ),
            leading: const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
            ),
            children: [for (final row in resolved)
              _maybeCollapsedRow(context, row,
                  collapsed: resolved.length > 1)],
          ),
      ],
    );
  }

  // Keep a single issue readable, but prevent multiple long photo-rich
  // findings from pushing unrelated issues off-screen. Expanding a summary
  // never invokes an edit/resolve action or changes the underlying finding.
  Widget _maybeCollapsedRow(
    BuildContext context,
    Map<String, dynamic> finding, {
    required bool collapsed,
  }) {
    if (!collapsed) return _row(context, finding);
    final id = finding['id']?.toString() ?? '';
    final status = statusLabel(finding);
    final description = finding['body']?.toString().trim() ?? '';
    return ExpansionTile(
      key: ValueKey('finding-collapsed-$id'),
      initiallyExpanded: false,
      title: Text(description.isEmpty ? 'Vehicle finding' : description,
        maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(status),
      leading: Icon(status == 'Resolved' ? Icons.check_circle_outline
          : status == 'In Job' ? Icons.handyman_outlined
          : Icons.warning_amber_rounded),
      children: [_row(context, finding)],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> finding) {
    final id = finding['id'].toString();
    final status = statusLabel(finding);
    final conflict = finding['sync_state'] == 'conflict';
    final enabled = !busy && !conflict;
    final repairJobId = finding['repair_job_id']?.toString() ?? '';
    final inThisJob = jobId == null || jobId == repairJobId;
    final attachments = (finding['attachments'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final color = status == 'Resolved'
        ? Colors.green
        : status == 'In Job'
        ? Colors.blue
        : Colors.deepOrange;
    return Container(
      key: ValueKey('vehicle-finding-$id'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                status == 'Resolved'
                    ? Icons.check_circle_outline
                    : status == 'In Job'
                    ? Icons.handyman_outlined
                    : Icons.warning_amber_rounded,
                color: color,
                size: 21,
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              if (status == 'In Job' &&
                  (finding['repair_job_number']?.toString() ?? '').isNotEmpty)
                Text(' • ${finding['repair_job_number']}'),
              if (status == 'Resolved' &&
                  (finding['resolved_job_number']?.toString() ?? '').isNotEmpty)
                Text(' • Job ${finding['resolved_job_number']}'),
              if (status == 'Resolved' &&
                  (finding['resolved_job_number']?.toString() ?? '').isEmpty &&
                  (finding['resolved_job_id']?.toString() ?? '').isNotEmpty &&
                  finding['sync_state'] == 'pending')
                const Text(' • Job link pending sync'),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            finding['body']?.toString() ?? '',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (showVehicle &&
              (finding['_vehicle_label']?.toString() ?? '').isNotEmpty)
            Text(finding['_vehicle_label'].toString()),
          if (conflict)
            const Text(
              'Sync conflict • local finding is preserved',
              style: TextStyle(color: Colors.orange),
            )
          else if ((finding['_finding_action_error']?.toString() ?? '')
              .isNotEmpty)
            const Text(
              'Needs verification • saved on this device',
              key: ValueKey('finding-needs-verification'),
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (finding['sync_state'] == 'pending' ||
              attachments.any((a) => a['upload_state'] == 'pending'))
            const Text(
              'Saved locally • waiting to sync',
              style: TextStyle(fontSize: 12),
            ),
          if (attachments.isNotEmpty && photoBuilder != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final photo in attachments) photoBuilder!(finding, photo),
              ],
            ),
          ],
          Wrap(
            spacing: 4,
            children: [
              if (canEdit && finding['can_edit'] != false)
                TextButton.icon(
                  onPressed: enabled ? () => onEdit(finding) : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              if (canEdit)
                TextButton.icon(
                  onPressed: enabled ? () => onAddPhotos(finding) : null,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add photos'),
                ),
              if (onDelete != null &&
                  finding['can_delete'] == true &&
                  !id.startsWith('local-finding-') &&
                  finding['row_version'] != null)
                TextButton.icon(
                  onPressed: enabled ? () => onDelete!(finding) : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
            ],
          ),
          if (canManage && status == 'Open')
            OutlinedButton.icon(
              key: ValueKey('finding-add-job-$id'),
              onPressed: enabled ? () => onAddToJob(finding) : null,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Add to Job'),
            ),
          if (canManage &&
              status == 'In Job' &&
              inThisJob &&
              onRemoveFromJob != null)
            TextButton(
              onPressed: enabled ? () => onRemoveFromJob!(finding) : null,
              child: const Text('Remove from Job'),
            ),
          if (canIncludeOnInvoice)
            CheckboxListTile(
              key: ValueKey('finding-invoice-$id'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Include in Invoice Notes'),
              subtitle:
                  finding['include_on_invoice'] == true &&
                      (finding['repair_job_id'] ?? finding['found_job_id']) ==
                          null
                  ? const Text(
                      'Selection saved. Add to Job to include it on that Job’s invoice.',
                    )
                  : null,
              value: finding['include_on_invoice'] == true,
              onChanged: enabled
                  ? (value) => onInvoiceChanged(finding, value == true)
                  : null,
            ),
          if (canManage && (status != 'In Job' || inThisJob))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: ValueKey('finding-resolve-$id'),
                onPressed: enabled
                    ? () => status == 'Resolved'
                          ? onReopen(finding)
                          : onResolve(finding)
                    : null,
                icon: Icon(
                  status == 'Resolved'
                      ? Icons.replay_outlined
                      : Icons.check_circle_outline,
                ),
                label: Text(status == 'Resolved' ? 'Reopen' : 'Resolve'),
              ),
            ),
        ],
      ),
    );
  }
}
