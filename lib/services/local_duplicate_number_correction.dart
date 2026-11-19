import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import 'local_customer_vehicle_identity.dart';
import 'local_document_sql_store.dart';
import 'local_number_allocator.dart';
import 'local_owner_authorization.dart';

class DuplicateNumberCorrectionPlan {
  DuplicateNumberCorrectionPlan(this.business, this.operation,
    Map<String, dynamic> evidence, this.invoiceNumber, this.jobNumber)
      : evidence = Map.unmodifiable(evidence);
  final String business;
  final String operation;
  final Map<String, dynamic> evidence;
  final int invoiceNumber;
  final int jobNumber;
  String get invoiceId => evidence['invoice_id'] as String;
  String get jobId => evidence['job_id'] as String;
  String get customer => evidence['customer_name'] as String;
  String get keepCustomer => evidence['keep_customer_name'] as String;
  Map<String, dynamic> get payload => {'evidence': evidence,
    'invoice_number': invoiceNumber, 'job_number': jobNumber};
}

/// Correct only a never-uploaded, closed local invoice and its local Job.
/// The other customer's numbered record, all identities and finances stay put.
class LocalDuplicateNumberCorrection {
  LocalDuplicateNumberCorrection(this.db, {bool Function()? forceOffline})
      : _forceOffline = forceOffline ??
          (() => BriskersConnectionModeController.instance.forceOffline);
  final BriskersLocalDatabase db;
  final bool Function() _forceOffline;

  void _offline() {
    if (!_forceOffline()) throw StateError('Keep Force Offline enabled while correcting these numbers.');
  }
  Future<void> _prepare() => db.customStatement('''
    CREATE TABLE IF NOT EXISTS local_invoice_number_corrections (
      business_id TEXT NOT NULL, invoice_id TEXT NOT NULL, job_id TEXT NOT NULL,
      operation_id TEXT NOT NULL, actor_id TEXT NOT NULL, created_at TEXT NOT NULL,
      old_invoice_number TEXT NOT NULL, new_invoice_number TEXT NOT NULL,
      old_job_number TEXT NOT NULL, new_job_number TEXT NOT NULL,
      kept_invoice_id TEXT NOT NULL, proof_json TEXT NOT NULL,
      original_snapshot_json TEXT NOT NULL, original_create_payload_json TEXT NOT NULL,
      PRIMARY KEY(business_id,invoice_id), UNIQUE(business_id,operation_id)
    )
  ''');
  String _operation() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0,8)}-${s.substring(8,12)}-${s.substring(12,16)}-${s.substring(16,20)}-${s.substring(20)}';
  }

  Future<({Map<String,dynamic> evidence, String raw, String createRaw, int queueId})> _inspect(
    String business, String invoice, String kept,
  ) async {
    final rows = await db.customSelect('''
      SELECT d.*, j.job_number,j.customer_id AS job_customer_id,j.sync_state AS job_sync_state,
             c.display_name AS customer_name
      FROM local_documents d JOIN local_jobs j ON j.business_id=d.business_id AND j.id=d.job_id
      JOIN local_customers c ON c.business_id=d.business_id AND c.id=d.customer_id
      WHERE d.business_id=? AND d.kind='invoice' AND d.id IN (?,?)
    ''', variables: [Variable(business),Variable(invoice),Variable(kept)]).get();
    if (invoice == kept || rows.length != 2) throw StateError('Both exact invoice records must be saved locally.');
    final selected = rows.singleWhere((r) => r.read<String>('id') == invoice);
    final other = rows.singleWhere((r) => r.read<String>('id') == kept);
    final job = selected.readNullable<String>('job_id') ?? '';
    final otherJob = other.readNullable<String>('job_id') ?? '';
    final number = selected.readNullable<String>('document_number') ?? '';
    final jobNumber = selected.readNullable<String>('job_number') ?? '';
    if (!invoice.startsWith('local-invoice-') ||
        job != 'local-job-${invoice.substring('local-invoice-'.length)}' ||
        selected.read<String>('sync_state') != 'pending' ||
        selected.read<String>('job_sync_state') != 'pending' ||
        selected.readNullable<int>('closed_at') == null ||
        selected.readNullable<String>('status') != 'closed' ||
        number.isEmpty || jobNumber.isEmpty || number != other.data['document_number'] ||
        jobNumber != other.data['job_number'] || job == otherJob ||
        selected.data['customer_id'] == other.data['customer_id'] ||
        selected.data['customer_id'] != selected.data['job_customer_id'] ||
        other.data['customer_id'] != other.data['job_customer_id']) {
      throw StateError('Only the closed local duplicate can be corrected here. Its links and closure must be verified first.');
    }
    final siblings = await db.customSelect(
      "SELECT COUNT(*) AS count FROM local_documents WHERE business_id=? AND job_id=? AND kind='invoice'",
      variables: [Variable(business), Variable(job)],
    ).getSingle();
    if (siblings.read<int>('count') != 1) throw StateError('This Job has other invoices and needs separate review.');
    final key = 'briskers_document_detail_${business}_$invoice';
    final raw = await LocalDocumentSqlStore.read(db, key);
    if (raw == null) throw StateError('The original invoice detail is unavailable.');
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['id'] != invoice || decoded['kind'] != 'invoice' ||
        decoded['job_id'] != job || decoded['document_number']?.toString() != number ||
        (decoded['_server_document_id']?.toString().isNotEmpty ?? false) ||
        num.tryParse(decoded['total_amount']?.toString() ?? '') != selected.read<double>('total')) {
      throw StateError('The original invoice identity or amount needs review. No numbers were changed.');
    }
    final creates = await db.customSelect(
      "SELECT id,payload_json,state,attempt_count,last_attempt_at FROM sync_outbox "
      "WHERE business_id=? AND entity_id=? AND entity_type='document_draft_create'",
      variables: [Variable(business),Variable(invoice)],
    ).get();
    if (creates.length != 1 || !['pending','conflict'].contains(creates.single.read<String>('state')) ||
        creates.single.read<int>('attempt_count') != 0 || creates.single.data['last_attempt_at'] != null) {
      throw StateError('The original creation may have been submitted. Its number correction needs review.');
    }
    final createRaw = creates.single.read<String>('payload_json');
    final create = jsonDecode(createRaw) as Map;
    final savedCustomer = decoded['customer_id']?.toString();
    final resolvedCustomer = await LocalCustomerVehicleIdentity(db).resolve(business,savedCustomer);
    final creationCustomer = await LocalCustomerVehicleIdentity(db).resolve(business,create['customer_id']?.toString());
    final oldTemporaryCustomer = savedCustomer?.startsWith('local-customer-') == true && resolvedCustomer == savedCustomer;
    if (resolvedCustomer != selected.data['customer_id'] &&
        !(oldTemporaryCustomer && creationCustomer == selected.data['customer_id'])) {
      throw StateError('The customer identity needs review. No customer links were changed.');
    }
    if (create['operation_id'] != invoice.substring('local-invoice-'.length) ||
        create['kind'] != 'invoice' || create['provisional_job_id'] != job ||
        create['local_document_number'] != null && create['local_document_number'].toString() != number ||
        create['local_job_number'] != null && create['local_job_number'] != jobNumber) {
      throw StateError('The original creation identity does not agree with this invoice.');
    }
    return (evidence: {
      'invoice_id': invoice, 'job_id': job, 'customer_id': selected.data['customer_id'],
      'customer_name': selected.read<String>('customer_name'), 'invoice_number': number,
      'job_number': jobNumber, 'total': selected.data['total'], 'closed_at': selected.data['closed_at'],
      'status': selected.data['status'], 'document_date': selected.data['document_date'],
      'keep_invoice_id': kept, 'keep_job_id': otherJob, 'keep_customer_id': other.data['customer_id'],
      'keep_customer_name': other.read<String>('customer_name'),
      'keep_invoice_number': other.data['document_number'], 'keep_job_number': other.data['job_number'],
      'create_payload': createRaw, 'queue_id': creates.single.read<int>('id'),
    }, raw: raw, createRaw: createRaw, queueId: creates.single.read<int>('id'));
  }

  Future<DuplicateNumberCorrectionPlan> preview(String business, String invoice, String kept) async {
    _offline();
    return db.transaction(() async {
      final checked = await _inspect(business,invoice,kept);
      final numbers = LocalNumberAllocator(db);
      final invoiceNumber = await numbers.nextFreshNumber(business,'invoice');
      final jobNumber = await numbers.nextFreshNumber(business,'job');
      _offline();
      return DuplicateNumberCorrectionPlan(business,_operation(),checked.evidence,invoiceNumber,jobNumber);
    });
  }

  Future<void> apply(DuplicateNumberCorrectionPlan plan, LocalOwnerGrant grant) async {
    void check() { grant.assertValid(plan.business,grant.actorId); _offline(); }
    check();
    await db.transaction(() async {
      check();
      await _prepare();
      final previous = await db.customSelect(
        'SELECT operation_id,proof_json FROM local_invoice_number_corrections WHERE business_id=? AND invoice_id=?',
        variables: [Variable(plan.business), Variable(plan.invoiceId)],
      ).getSingleOrNull();
      if (previous != null) {
        if (previous.data['operation_id'] == plan.operation && previous.data['proof_json'] == jsonEncode(plan.payload)) return;
        throw StateError('This invoice already has a recorded number correction.');
      }
      final checked = await _inspect(plan.business,plan.invoiceId,plan.evidence['keep_invoice_id'] as String);
      if (jsonEncode(checked.evidence) != jsonEncode(plan.evidence)) throw StateError('These records changed. Inspect them again before correcting numbers.');
      final numbers = LocalNumberAllocator(db);
      await numbers.allocate(plan.business,'invoice',plan.invoiceId,requested:plan.invoiceNumber);
      await numbers.allocate(plan.business,'job',plan.jobId,requested:plan.jobNumber);
      for (final ownership in [
        ('invoice',plan.evidence['invoice_number'].toString(),plan.invoiceId,plan.evidence['keep_invoice_id']),
        ('job',plan.evidence['job_number'].toString().replaceFirst(RegExp(r'^J-?'),''),plan.jobId,plan.evidence['keep_job_id']),
      ]) {
        final oldNumber = int.tryParse(ownership.$2);
        if (oldNumber == null) continue;
        await db.customStatement('UPDATE local_number_reservations SET entity_id=?,active=1 '
          'WHERE business_id=? AND kind=? AND number=? AND entity_id=?',
          [ownership.$4,plan.business,ownership.$1,oldNumber,ownership.$3]);
      }
      await db.customStatement('UPDATE local_documents SET document_number=? WHERE business_id=? AND id=?',
        ['${plan.invoiceNumber}',plan.business,plan.invoiceId]);
      await db.customStatement('UPDATE local_jobs SET job_number=? WHERE business_id=? AND id=?',
        ['J-${plan.jobNumber}',plan.business,plan.jobId]);
      final detail = Map<String,dynamic>.from(jsonDecode(checked.raw) as Map);
      await LocalDocumentSqlStore.write(db,'briskers_document_detail_${plan.business}_${plan.invoiceId}',
        jsonEncode({...detail,'document_number':'${plan.invoiceNumber}','job_number':'J-${plan.jobNumber}'}));
      final create = Map<String,dynamic>.from(jsonDecode(checked.createRaw) as Map);
      await db.customStatement('UPDATE sync_outbox SET payload_json=? WHERE business_id=? AND id=?',
        [jsonEncode({...create,'local_document_number':'${plan.invoiceNumber}','local_job_number':'J-${plan.jobNumber}'}),plan.business,checked.queueId]);
      await db.customStatement('INSERT INTO local_invoice_number_corrections VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
        plan.business,plan.invoiceId,plan.jobId,plan.operation,grant.actorId,DateTime.now().toUtc().toIso8601String(),
        plan.evidence['invoice_number'],'${plan.invoiceNumber}',plan.evidence['job_number'],'J-${plan.jobNumber}',
        plan.evidence['keep_invoice_id'],jsonEncode(plan.payload),checked.raw,checked.createRaw,
      ]);
      check();
    });
    db.notifyUpdates({const TableUpdate('local_documents'),const TableUpdate('local_jobs')});
  }
}
