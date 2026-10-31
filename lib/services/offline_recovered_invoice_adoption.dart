import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'offline_invoice_recovery_proof.dart';
import 'offline_customer_vehicle_admin_service.dart';
import 'local_job_repository.dart';
import 'local_document_repository.dart';
import 'offline_invoice_payment_ledger.dart';

/// Generic local-only adoption of an invoice already present on the server.
/// This does not submit documents or payments. A trusted caller must supply
/// an independently fetched invoice and payment proof.
class OfflineRecoveredInvoiceAdoption {
  OfflineRecoveredInvoiceAdoption({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  Future<void> apply({
    required bool isOwner,
    required String businessId,
    required String localCustomerId,
    required String localVehicleId,
    required String localJobId,
    required String localInvoiceId,
    required String invoiceOperationId,
    required String paymentOperationId,
    required String serverCustomerId,
    required String serverVehicleId,
    required String serverJobId,
    required String serverInvoiceId,
    required int totalCents,
    required int paymentCents,
    required int lineCount,
    required String paymentMethodId,
    required String paymentDate,
    required Map<String, dynamic> serverInvoice,
    required List<Map<String, dynamic>> serverPayments,
  }) async {
    OfflineInvoiceRecoveryProof.verify(
      owner: isOwner,
      invoice: serverInvoice,
      payments: serverPayments,
      businessId: businessId,
      invoiceId: serverInvoiceId,
      invoiceOperationId: invoiceOperationId,
      paymentOperationId: paymentOperationId,
      totalCents: totalCents,
      paymentCents: paymentCents,
      paymentMethodId: paymentMethodId,
      paymentDate: paymentDate,
      expectedLineCount: lineCount,
    );
    for (final id in [serverCustomerId,serverVehicleId,serverJobId,serverInvoiceId]) {
      if (id.isEmpty || id.startsWith('local-')) {
        throw StateError('Permanent server identities required');
      }
    }
    if (serverInvoice['customer_id'] != serverCustomerId ||
        serverInvoice['vehicle_id'] != serverVehicleId ||
        serverInvoice['job_id'] != serverJobId) {
      throw StateError('Server relationship mismatch');
    }

    await _db.transaction(() async {
      final queue = await _db.customSelect(
        '''SELECT id,entity_type,entity_id,payload_json,state
           FROM sync_outbox WHERE business_id=? AND state='pending'
             AND entity_type IN ('customer_create','vehicle_create',
               'document_draft_create','invoice_payment_received')
             AND entity_id IN (?,?,?)''',
        variables: [
          Variable<String>(businessId),Variable<String>(localCustomerId),
          Variable<String>(localVehicleId),Variable<String>(localInvoiceId),
        ],
      ).get();
      if (queue.length != 4) {
        throw StateError('Expected exactly four original pending operations');
      }
      int operation(String kind, String id, String? expectedId) {
        final matches = queue.where((r) =>
          r.read<String>('entity_type') == kind &&
          r.read<String>('entity_id') == id).toList();
        if (matches.length != 1) throw StateError('Missing original $kind');
        final payload = jsonDecode(matches.single.read<String>('payload_json'));
        if (payload is! Map) throw StateError('Invalid original operation');
        if (expectedId != null && payload['operation_id'] != expectedId) {
          throw StateError('Original $kind operation ID mismatch');
        }
        return matches.single.read<int>('id');
      }
      final customerQueue=operation('customer_create',localCustomerId,null);
      final vehicleQueue=operation('vehicle_create',localVehicleId,null);
      final invoiceQueue=operation('document_draft_create',localInvoiceId,invoiceOperationId);
      operation('invoice_payment_received',localInvoiceId,paymentOperationId);
      final local = await _db.customSelect(
        '''SELECT total,job_id,customer_id,sync_state FROM local_documents
           WHERE business_id=? AND id=?''',
        variables:[Variable<String>(businessId),Variable<String>(localInvoiceId)],
      ).get();
      if (local.length != 1 ||
          local.single.read<String>('sync_state') != 'pending' ||
          local.single.read<String>('job_id') != localJobId ||
          local.single.read<String>('customer_id') != localCustomerId ||
          (local.single.read<double>('total')*100).round() != totalCents) {
        throw StateError('Original local invoice no longer matches');
      }
      final admin=OfflineCustomerVehicleAdminService(database:_db);
      await admin.reconcileCreatedCustomerId(
          businessId,localCustomerId,serverCustomerId,customerQueue);
      await admin.reconcileCreatedVehicleId(
          businessId,localVehicleId,serverVehicleId,vehicleQueue);
      await LocalJobRepository(database:_db).remapProvisionalJob(
          businessId,localJobId,serverJobId,
          jobNumber: serverInvoice['job_number']?.toString());
      await OfflineInvoicePaymentLedger(database:_db).remapInvoice(
          businessId,localInvoiceId,serverInvoiceId);
      await LocalDocumentRepository(database:_db).upsertFromServer(
          businessId,[serverInvoice]);
      // Keep the original local invoice, payment outbox and snapshot.
      // A separate, verified acknowledgement step must retire them only
      // after the server receipt appears in the authorized detail feed.
      await _db.customStatement(
        '''UPDATE sync_outbox SET state='pending',
           last_error='Adopted server invoice; payment acknowledgement required'
           WHERE business_id=? AND entity_type='invoice_payment_received'
             AND entity_id=?''',
        [businessId,serverInvoiceId],
      );
      await _db.customStatement(
        'DELETE FROM sync_outbox WHERE business_id=? AND id=?',
        [businessId,invoiceQueue],
      );
    });
  }
}
