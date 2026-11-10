/// Pure invoice-scoped projection of locally selected Vehicle Findings.
/// Never mutates the saved invoice memo or the underlying finding records.
List<Map<String, dynamic>> invoiceFindingNotesForJob({
  required String jobId,
  required Iterable<Map<String, dynamic>> findings,
}) {
  if (jobId.isEmpty) return <Map<String, dynamic>>[];
  final seen = <String>{};
  final notes = <Map<String, dynamic>>[];
  for (final finding in findings) {
    if (finding['include_on_invoice'] != true) continue;
    final foundJobId = finding['found_job_id']?.toString() ?? '';
    final repairJobId = finding['repair_job_id']?.toString() ?? '';
    final resolvedJobId = finding['resolved_job_id']?.toString() ?? '';
    if (foundJobId != jobId && repairJobId != jobId && resolvedJobId != jobId) continue;
    final id = finding['id']?.toString() ?? '';
    final body = finding['body']?.toString().trim() ?? '';
    if (id.isEmpty || body.isEmpty || !seen.add(id)) continue;
    notes.add(<String, dynamic>{
      'id': id,
      'body': '• $body',
      'resolution_group': finding['status'] == 'resolved' &&
              (repairJobId == jobId || resolvedJobId == jobId)
          ? 'resolved'
          : 'unresolved',
    });
  }
  return notes;
}
