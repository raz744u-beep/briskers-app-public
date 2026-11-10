import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/invoice_finding_notes_projection.dart';

void main() {
  test('selected findings are included only for the invoice job', () {
    final rows = invoiceFindingNotesForJob(jobId: 'job-50', findings: [
      {'id': 'a', 'found_job_id': 'job-50', 'body': 'Strut mounts are broken', 'include_on_invoice': true},
      {'id': 'b', 'found_job_id': 'job-49', 'body': 'Old issue', 'include_on_invoice': true},
      {'id': 'c', 'repair_job_id': 'job-50', 'body': 'Oil leak', 'include_on_invoice': true},
      {'id': 'd', 'found_job_id': 'job-50', 'body': 'Unchecked', 'include_on_invoice': false},
    ]);
    expect(rows.map((row) => row['body']).toList(), [
      '• Strut mounts are broken', '• Oil leak',
    ]);
  });

  test('resolved findings remain independently eligible for invoice notes', () {
    final notes = invoiceFindingNotesForJob(jobId: 'job-50', findings: [
      {
        'id': 'resolved-1',
        'found_job_id': 'job-50',
        'repair_job_id': 'job-50',
        'status': 'resolved',
        'body': 'Strut mounts are broken',
        'include_on_invoice': true,
      },
      {
        'id': 'resolved-2',
        'found_job_id': 'job-50',
        'status': 'resolved',
        'body': 'Do not print',
        'include_on_invoice': false,
      },
    ]);
    expect(notes, [
      {'id': 'resolved-1', 'body': '• Strut mounts are broken'},
    ]);
  });

  test('does not duplicate or include blank findings', () {
    final rows = invoiceFindingNotesForJob(jobId: 'j', findings: [
      {'id': 'a', 'found_job_id': 'j', 'body': 'First', 'include_on_invoice': true},
      {'id': 'a', 'found_job_id': 'j', 'body': 'First', 'include_on_invoice': true},
      {'id': 'b', 'found_job_id': 'j', 'body': '  ', 'include_on_invoice': true},
    ]);
    expect(rows, [{'id': 'a', 'body': '• First'}]);
    expect(invoiceFindingNotesForJob(jobId: '', findings: const []), isEmpty);
  });
}
