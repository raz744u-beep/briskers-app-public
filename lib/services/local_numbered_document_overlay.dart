import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Projects Owner-assigned local invoice/Job numbers onto a cached document.
/// Only reads SQLite; leaves original lines, totals and payment untouched.
class LocalNumberedDocumentOverlay {
  LocalNumberedDocumentOverlay({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  Future<Map<String, dynamic>> apply(
    String businessId, String documentId, Map<String, dynamic> cached,
  ) async {
    final rows = await _db.customSelect(
      '''SELECT d.document_number,d.status,d.display_status_code,
                j.job_number
         FROM local_documents d
         LEFT JOIN local_jobs j ON j.business_id=d.business_id AND j.id=d.job_id
         WHERE d.business_id=? AND d.id=? AND d.kind='invoice'
           AND d.sync_state='pending' LIMIT 1''',
      variables:[Variable<String>(businessId),Variable<String>(documentId)],
    ).get();
    if (rows.isEmpty) return cached;
    final row = rows.single;
    final number = row.readNullable<String>('document_number')?.trim() ?? '';
    if (number.isEmpty) return cached;
    final job = row.readNullable<String>('job_number')?.trim() ?? '';
    return <String, dynamic>{
      ...cached,
      'document_number': number,
      'status': row.readNullable<String>('status') ?? cached['status'],
      'display_status_code': row.readNullable<String>('display_status_code') ??
          cached['display_status_code'],
      'display_status': 'Open',
      if (job.isNotEmpty) 'job_number': job,
    };
  }
}
