import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'invoice_labor_work_summary.dart';
import 'local_document_detail_cache.dart';

/// Checks source records before an invoice labor line can enter payroll.
class LocalPayrollWorkSource {
  LocalPayrollWorkSource(this._database)
      : _documents = LocalDocumentDetailCache(database: _database);

  final BriskersLocalDatabase _database;
  final LocalDocumentDetailCache _documents;

  /// Returns a saved labor line only when the invoice, job and assignment
  /// agree. The caller must separately authorize the acting user's session.
  Future<Map<String, dynamic>?> resolve({
    required String businessId,
    required String jobId,
    required String invoiceId,
    required String lineId,
    required String employeeId,
  }) {
    return _database.transaction(() async {
      if ([businessId, jobId, invoiceId, lineId, employeeId]
          .any((id) => id.trim().isEmpty)) {
        return null;
      }
      final source = await _database.customSelect(
        '''
        SELECT 1 AS linked
        FROM local_documents d
        JOIN local_jobs j ON j.business_id = d.business_id AND j.id = d.job_id
        WHERE d.business_id = ? AND d.id = ? AND d.kind = 'invoice'
          AND j.id = ?
          AND EXISTS (
            SELECT 1 FROM local_job_assignments a
            WHERE a.business_id = j.business_id AND a.job_id = j.id
              AND a.employee_id = ? AND a.active = 1
          )
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(invoiceId),
          Variable<String>(jobId),
          Variable<String>(employeeId),
        ],
      ).getSingleOrNull();
      if (source == null) return null;

      final invoice = await _documents.load(businessId, invoiceId);
      if (invoice == null ||
          invoice['id'] != invoiceId ||
          invoice['job_id'] != jobId ||
          invoice['kind'] != 'invoice' ||
          (invoice['business_id'] != null &&
              invoice['business_id'] != businessId)) {
        return null;
      }
      final lines = invoice['lines'] ?? invoice['items'];
      if (lines is! List) return null;
      final matches = lines.whereType<Map>().where((row) => row['id'] == lineId);
      if (matches.length != 1) {
        return null;
      }
      if (!isInvoiceLaborLine(matches.single)) {
        final ready = await _database.customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='regular_payroll_task_sources'",
        ).get();
        if (ready.isEmpty) return null;
        final selected = await _database.customSelect(
          'SELECT task_id FROM regular_payroll_task_sources WHERE business_id=? AND invoice_id=? AND line_id=? AND active=1',
          variables:[Variable(businessId),Variable(invoiceId),Variable(lineId)],
        ).get();
        if (selected.length != 1) return null;
      }
      return Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(matches.single),
      );
    });
  }
}
