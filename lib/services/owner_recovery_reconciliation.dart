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
    // Do not mark outbox rows synced or change local IDs here:
    // server keys and local keys require a separate explicit alias migration.
    return true;
  }
}
