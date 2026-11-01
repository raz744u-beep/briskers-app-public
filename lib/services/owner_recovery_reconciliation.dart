import 'dart:convert';

import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// A read-only, fail-closed verification of an existing, held local recovery.
/// The server proof must be obtained independently; this method never uploads.
class OwnerRecoveryReconciliation {
  OwnerRecoveryReconciliation({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  Future<bool> verify({
    required bool isOwner,
    required String businessId,
    required String localInvoiceId,
    required String serverInvoiceId,
    required String serverJobId,
    required String invoiceNumber,
    required String jobNumber,
    required int totalCents,
    required int paymentCents,
    required String serverPaymentOperationId,
    required String serverPaymentDate,
    required int serverLineCount,
    required int serverPaymentCount,
  }) async {
    if (!isOwner) throw StateError('Owner authorization required');
    if (serverPaymentOperationId.isEmpty || serverPaymentDate.isEmpty ||
        serverInvoiceId.isEmpty || serverJobId.isEmpty ||
        localInvoiceId.isEmpty || totalCents <= 0 || paymentCents <= 0 ||
        serverLineCount <= 0 || serverPaymentCount != 1) {
      throw StateError('Incomplete or ambiguous server proof');
    }
    final invoices = await _db.customSelect(
      """SELECT d.id,d.job_id,d.document_number,d.total,d.sync_state,
                j.job_number,j.sync_state AS job_sync_state
         FROM local_documents d JOIN local_jobs j
           ON j.business_id=d.business_id AND j.id=d.job_id
         WHERE d.business_id=? AND d.id=? AND d.kind='invoice'""",
      variables:[Variable<String>(businessId),Variable<String>(localInvoiceId)],
    ).get();
    if (invoices.length != 1) throw StateError('Local invoice not unique');
    final invoice = invoices.single;
    final cents=((invoice.read<double>('total'))*100).round();
    if (invoice.readNullable<String>('document_number') != invoiceNumber ||
        invoice.readNullable<String>('job_number') != jobNumber ||
        invoice.read<String>('sync_state') != 'pending' ||
        invoice.read<String>('job_sync_state') != 'pending' ||
        cents != totalCents) {
      throw StateError('Local and server invoice identity or total mismatch');
    }
    final ops = await _db.customSelect(
      """SELECT payload_json,last_error FROM sync_outbox
         WHERE business_id=? AND entity_type='invoice_payment_received'
           AND entity_id=? AND state='conflict'""",
      variables:[Variable<String>(businessId),Variable<String>(localInvoiceId)],
    ).get();
    if (ops.length != 1 ||
        ops.single.readNullable<String>('last_error') !=
          'Owner recovery payment preserved; sync disabled') {
      throw StateError('Original held payment is missing or ambiguous');
    }
    final raw=jsonDecode(ops.single.read<String>('payload_json'));
    if (raw is! Map ||
        raw['invoice_id'] != localInvoiceId ||
        raw['operation_id']?.toString().isNotEmpty != true ||
        raw['amount_cents'] != paymentCents ||
        raw['operation_id'] != serverPaymentOperationId ||
        raw['payment_date'] != serverPaymentDate) {
      throw StateError('Original payment identity or amount mismatch');
    }
    // A verified match is recorded as an alias, never as a replayable upload.
    // Keep the original held receipt and all phone-side keys intact.
    return true;
  }

  /// Stores an Owner-approved identity match. This has no network effects,
  /// makes no payment, and deliberately does not unblock ordinary sync.
  Future<void> recordVerifiedAlias({
    required bool isOwner,
    required String businessId,
    required String localInvoiceId,
    required String serverInvoiceId,
    required String serverJobId,
    required String invoiceNumber,
    required String jobNumber,
    required int totalCents,
    required int paymentCents,
    required String serverPaymentOperationId,
    required String serverPaymentDate,
    required int serverLineCount,
    required int serverPaymentCount,
  }) async {
    await _db.transaction(() async {
      await verify(
        isOwner:isOwner,businessId:businessId,localInvoiceId:localInvoiceId,
        serverInvoiceId:serverInvoiceId,serverJobId:serverJobId,
        invoiceNumber:invoiceNumber,jobNumber:jobNumber,
        totalCents:totalCents,paymentCents:paymentCents,
        serverPaymentOperationId:serverPaymentOperationId,
        serverPaymentDate:serverPaymentDate,
        serverLineCount:serverLineCount,serverPaymentCount:serverPaymentCount,
      );
      await _db.customStatement(
        """CREATE TABLE IF NOT EXISTS owner_recovery_aliases (
          business_id TEXT NOT NULL,
          local_invoice_id TEXT NOT NULL,
          server_invoice_id TEXT NOT NULL,
          server_job_id TEXT NOT NULL,
          payment_operation_id TEXT NOT NULL,
          invoice_number TEXT NOT NULL,
          job_number TEXT NOT NULL,
          total_cents INTEGER NOT NULL,
          payment_cents INTEGER NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (business_id,local_invoice_id),
          UNIQUE (business_id,server_invoice_id),
          UNIQUE (business_id,payment_operation_id)
        )""",
      );
      final prior = await _db.customSelect(
        """SELECT server_invoice_id,server_job_id,payment_operation_id
           FROM owner_recovery_aliases
           WHERE business_id=? AND local_invoice_id=?""",
        variables:[Variable<String>(businessId),Variable<String>(localInvoiceId)],
      ).get();
      if (prior.isNotEmpty) {
        final match=prior.single;
        if (match.read<String>('server_invoice_id') != serverInvoiceId ||
            match.read<String>('server_job_id') != serverJobId ||
            match.read<String>('payment_operation_id') != serverPaymentOperationId) {
          throw StateError('Existing recovery identity cannot be overwritten');
        }
        return;
      }
      await _db.customStatement(
        """INSERT INTO owner_recovery_aliases
           (business_id,local_invoice_id,server_invoice_id,server_job_id,
            payment_operation_id,invoice_number,job_number,total_cents,payment_cents)
           VALUES (?,?,?,?,?,?,?,?,?)""",
        [businessId,localInvoiceId,serverInvoiceId,serverJobId,
         serverPaymentOperationId,invoiceNumber,jobNumber,totalCents,paymentCents],
      );
    });
  }
}
