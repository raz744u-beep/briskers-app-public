import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import 'local_document_detail_cache.dart';
import 'local_document_sql_store.dart';
import 'local_estimate_number.dart';
import 'local_job_retirement.dart';
import 'local_owner_authorization.dart';

/// Repairs only the conversion matched by the Owner's local audit and the
/// original issued estimate independently verified on the server.
class VerifiedLocalConversionRepair {
  VerifiedLocalConversionRepair(this.db);
  final BriskersLocalDatabase db;

  static String _fingerprint(String value) => const DartSha256()
      .hashSync(utf8.encode(value))
      .bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  static bool appliesTo(String business, String invoice) =>
      _fingerprint('$business:$invoice') ==
      'd58c1222f0616628c15889dd06d52ed08724b312366fa09fc84f7a688fd2b0a2';

  Future<void> undo(String business, String invoice, LocalOwnerGrant grant) async {
    if (!appliesTo(business, invoice) ||
        !BriskersConnectionModeController.instance.forceOffline ||
        !LocalDocumentDetailCache.sqliteWritesEnabled) {
      throw StateError('Open the audited invoice in Offline mode to undo its conversion.');
    }
    grant.assertValid(business, grant.actorId);
    final operation = invoice.substring('local-invoice-'.length);
    final job = 'local-conversion-job-$operation';
    const failure = 'The saved conversion no longer matches the audit. No changes were made.';
    await db.transaction(() async {
      await LocalJobRetirement.ensureSchema(db);
      final invoiceKey = LocalDocumentDetailCache.key(business, invoice);
      final invoiceJson = await LocalDocumentSqlStore.read(db, invoiceKey);
      if (invoiceJson == null) throw StateError(failure);
      final savedInvoice = jsonDecode(invoiceJson) as Map<String, dynamic>;
      final estimate = savedInvoice['converted_from_estimate_id']?.toString() ?? '';
      if (_fingerprint(estimate) !=
          '323ff395a52dfed2efe71018bae5b727890160e0177cd437ec8a93e1a0fd1c87' ||
          savedInvoice['id'] != invoice || savedInvoice['job_id'] != job ||
          savedInvoice['_server_document_id'] != null ||
          savedInvoice['document_number']?.toString() != '6387' ||
          savedInvoice['business_id'] != null && savedInvoice['business_id'] != business ||
          savedInvoice['closed_at'] != null ||
          num.tryParse('${savedInvoice['paid_amount']}') != 0 ||
          num.tryParse('${savedInvoice['pending_payment']}') != 0 ||
          (savedInvoice['payments'] as List?)?.isNotEmpty == true) {
        throw StateError(failure);
      }
      final estimateKey = LocalDocumentDetailCache.key(business, estimate);
      final estimateJson = await LocalDocumentSqlStore.read(db, estimateKey);
      if (estimateJson == null) throw StateError(failure);
      final savedEstimate = jsonDecode(estimateJson) as Map<String, dynamic>;
      if (savedEstimate['id'] != estimate ||
          savedEstimate['kind'] != 'estimate' ||
          savedEstimate['business_id'] != null && savedEstimate['business_id'] != business ||
          savedEstimate['customer_id'] != savedInvoice['customer_id'] ||
          LocalEstimateNumber.existing(savedEstimate['document_number']) != 'E-1997' ||
          savedEstimate['converted_invoice_id'] != invoice ||
          (savedEstimate['job_id']?.toString().isNotEmpty ?? false) ||
          savedEstimate['row_version']?.toString() != '1') {
        throw StateError(failure);
      }
      final queue = await db.customSelect(
        'SELECT * FROM sync_outbox WHERE business_id=? AND '
        '(entity_id IN (?,?) OR instr(payload_json,?)>0 OR instr(payload_json,?)>0)',
        variables: [Variable(business), Variable(invoice), Variable(job),
          Variable(invoice), Variable(job)],
      ).get();
      if (queue.length != 1) throw StateError(failure);
      final row = queue.single;
      final payload = jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
      if (row.data['entity_id'] != invoice ||
          row.data['entity_type'] != 'document_draft_create' ||
          row.data['operation'] != 'convert_estimate' ||
          row.data['state'] != 'pending' || row.data['attempt_count'] != 0 ||
          row.data['last_attempt_at'] != null ||
          payload['kind'] != 'convert_invoice' || payload['estimate_id'] != estimate ||
          payload['operation_id'] != operation || payload['provisional_job_id'] != job) {
        throw StateError(failure);
      }
      final links = await db.customSelect(
        'SELECT id FROM local_documents WHERE business_id=? AND job_id=?',
        variables: [Variable(business), Variable(job)],
      ).get();
      final localJob = await db.customSelect(
        "SELECT id FROM local_jobs WHERE business_id=? AND id=? AND job_number='J-67' AND sync_state='pending'",
        variables: [Variable(business), Variable(job)],
      ).getSingleOrNull();
      if (links.length != 1 || links.single.data['id'] != invoice || localJob == null) {
        throw StateError(failure);
      }
      final original = await db.customSelect(
        "SELECT id FROM local_documents WHERE business_id=? AND id=? AND kind='estimate' AND converted=1",
        variables: [Variable(business), Variable(estimate)],
      ).getSingleOrNull();
      if (original == null) throw StateError(failure);
      final otherEvidence = await db.customSelect(
        'SELECT 1 FROM local_estimate_conversion_evidence '
        'WHERE business_id=? AND estimate_id=? AND invoice_id<>? LIMIT 1',
        variables: [Variable(business), Variable(estimate), Variable(invoice)],
      ).getSingleOrNull();
      if (otherEvidence != null) throw StateError(failure);
      grant.assertValid(business, grant.actorId);
      if (!BriskersConnectionModeController.instance.forceOffline) throw StateError(failure);

      await db.customStatement(
        'INSERT INTO local_job_retirement_requests '
        '(business_id,job_id,operation_id,actor_id,snapshot_json,state,created_at) '
        "VALUES (?,?,?,?,?,'locally_cancelled',?)",
        [business, job, operation, grant.actorId, jsonEncode({
          'queued_conversion': row.data,
          'invoice': savedInvoice,
          'estimate_before_repair': savedEstimate,
        }), DateTime.now().millisecondsSinceEpoch ~/ 1000],
      );
      await db.customStatement('DELETE FROM sync_outbox WHERE id=?', [row.read<int>('id')]);
      for (final (kind, id) in [('invoice', invoice), ('job', job)]) {
        await LocalJobRetirement.recordEntity(db, businessId: business,
          jobId: job, entityKind: kind, entityId: id,
          operationId: operation, state: 'locally_cancelled');
      }
      await db.customStatement(
        'INSERT INTO local_document_detail_deleted(cache_key) VALUES (?)', [invoiceKey]);
      await db.customStatement(
        "UPDATE local_documents SET converted=0,status='issued',display_status_code='issued',"
        "sync_state=CASE WHEN EXISTS(SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=?) "
        "THEN sync_state ELSE 'synced' END WHERE business_id=? AND id=?",
        [business, estimate, business, estimate],
      );
      final index = await db.customSelect(
        'SELECT sync_state FROM local_documents WHERE business_id=? AND id=?',
        variables: [Variable(business), Variable(estimate)],
      ).getSingle();
      final restored = {
        ...savedEstimate,
        'sync_state': index.read<String>('sync_state'),
        'converted': false,
        'status': 'issued',
        'display_status': 'Issued',
        'display_status_code': 'issued',
      }..remove('converted_invoice_id')
       ..remove('converted_invoice_number')
       ..remove('converted_invoice_date');
      await LocalDocumentSqlStore.write(db, estimateKey, jsonEncode(restored));
    });
    LocalJobRetirement.notify(db, business, [job]);
  }
}
