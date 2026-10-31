import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Owner-only, completely offline numbering for an existing local invoice
/// and its existing provisional Job. No new record, RPC or server approval.
class LocalOwnerInvoiceNumbering {
  LocalOwnerInvoiceNumbering({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  static String _number(String value, String field) {
    final result = value.trim();
    if (result.isEmpty || result.length > 32 ||
        result.toUpperCase().startsWith('TEMP-')) {
      throw ArgumentError('Invalid $field');
    }
    return result;
  }

  Future<void> assign({
    required bool isOwner,
    required String businessId,
    required String invoiceId,
    required String jobId,
    required String invoiceNumber,
    required String jobNumber,
  }) async {
    if (!isOwner) throw StateError('Owner authorization required');
    final number = _number(invoiceNumber, 'invoice number');
    final job = _number(jobNumber, 'job number');
    await _db.transaction(() async {
      final invoices = await _db.customSelect(
        '''SELECT id,job_id,kind,sync_state
           FROM local_documents WHERE business_id=? AND id=?''',
        variables:[Variable<String>(businessId),Variable<String>(invoiceId)],
      ).get();
      final jobs = await _db.customSelect(
        'SELECT id,sync_state FROM local_jobs WHERE business_id=? AND id=?',
        variables:[Variable<String>(businessId),Variable<String>(jobId)],
      ).get();
      if (invoices.length != 1 || jobs.length != 1 ||
          invoices.single.readNullable<String>('job_id') != jobId ||
          invoices.single.read<String>('kind') != 'invoice' ||
          invoices.single.read<String>('sync_state') != 'pending' ||
          jobs.single.read<String>('sync_state') != 'pending') {
        throw StateError('Original pending invoice and Job must exist');
      }
      final invoiceConflicts = await _db.customSelect(
        '''SELECT id FROM local_documents
           WHERE business_id=? AND kind='invoice'
             AND document_number=? COLLATE NOCASE AND id<>? LIMIT 1''',
        variables:[Variable<String>(businessId),Variable<String>(number),
          Variable<String>(invoiceId)],
      ).get();
      final jobConflicts = await _db.customSelect(
        '''SELECT id FROM local_jobs
           WHERE business_id=? AND job_number=? COLLATE NOCASE
             AND id<>? LIMIT 1''',
        variables:[Variable<String>(businessId),Variable<String>(job),
          Variable<String>(jobId)],
      ).get();
      if (invoiceConflicts.isNotEmpty || jobConflicts.isNotEmpty) {
        throw StateError('Invoice or Job number already exists locally');
      }

      // The original unsent create operation must never automatically replay
      // with a different number. Hold it with all original payload bytes.
      await _db.customStatement(
        '''UPDATE sync_outbox SET state='conflict',
             last_error='Owner assigned authoritative local number; sync disabled'
           WHERE business_id=? AND entity_type='document_draft_create'
             AND entity_id=? AND state='pending' ''',
        [businessId,invoiceId],
      );
      await _db.customStatement(
        '''UPDATE sync_outbox SET state='conflict',
             last_error='Owner recovery payment preserved; sync disabled'
           WHERE business_id=? AND entity_type='invoice_payment_received'
             AND entity_id=? AND state='pending' ''',
        [businessId,invoiceId],
      );
      // Keep the customer and vehicle create records intact, but prevent
      // any of the original recovery chain from auto-uploading later.
      await _db.customStatement(
        '''UPDATE sync_outbox SET state='conflict',
             last_error='Owner local recovery is authoritative; sync disabled'
           WHERE business_id=? AND state='pending'
             AND ((entity_type='customer_create' AND entity_id IN (
                  SELECT customer_id FROM local_documents
                  WHERE business_id=? AND id=?))
               OR (entity_type='vehicle_create' AND entity_id IN (
                  SELECT vehicle_id FROM local_jobs
                  WHERE business_id=? AND id=?)))''',
        [businessId,businessId,invoiceId,businessId,jobId],
      );
      await _db.customStatement(
        '''UPDATE local_documents SET document_number=?,status='issued',
            display_status_code='open'
           WHERE business_id=? AND id=? AND sync_state='pending' ''',
        [number,businessId,invoiceId],
      );
      await _db.customStatement(
        '''UPDATE local_jobs SET job_number=?
           WHERE business_id=? AND id=? AND sync_state='pending' ''',
        [job,businessId,jobId],
      );
    });
  }
}
