import 'local_invoice_closure.dart';
import 'local_financial_totals_journal.dart';
import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import '../core/connection_mode.dart';
import '../core/document_presentation.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'offline_invoice_payment_ledger.dart';
import 'offline_invoice_tax_service.dart';
import 'offline_document_edit_service.dart';
import 'local_job_quarantine.dart';
import 'local_job_retirement.dart';

/// Owner-confirmed intents, separate from received payments and server posting.
/// A queued intent never fabricates a posted payment or a server-confirmed close.
class OfflineInvoiceFinalization {
  OfflineInvoiceFinalization({BriskersLocalDatabase? database,
    this.api = const BriskersApi()})
      : db = database ?? localDatabase;
  // The former RPC is paused. Existing durable intents remain available for
  // reconciliation and must only be replayed by a verified replacement.
  static const remoteReplayEnabled = false;

  final BriskersLocalDatabase db;
  final BriskersApi api;

  Future<void> prepare() async {
    await db.customStatement('''CREATE TABLE IF NOT EXISTS
    invoice_finalization_intents_v1(business_id TEXT NOT NULL,invoice_id TEXT NOT NULL,
    operation_id TEXT NOT NULL,payload TEXT NOT NULL,state TEXT NOT NULL,
    error TEXT,PRIMARY KEY(business_id,invoice_id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS invoice_finalization_close_followups_v1(
      business_id TEXT NOT NULL,invoice_id TEXT NOT NULL,operation_id TEXT NOT NULL,payload TEXT NOT NULL,
      PRIMARY KEY(business_id,invoice_id))''');
  }

  static int money(Object? value) {
    final n = num.tryParse(value?.toString() ?? '');
    if (n == null || !n.isFinite || n < 0) {
      throw StateError('Saved invoice payment details need review.');
    }
    return (n * 100).round();
  }

  static String? _localReceiptDate(Map payment) {
    for (final value in [payment['payment_date'], payment['entered_at']]) {
      final source = value?.toString().trim() ?? '';
      if (source.isEmpty) continue;
      final match = RegExp(r'^\d{4}-\d{2}-\d{2}(?=$|[T ])').firstMatch(source);
      final day = match?.group(0);
      final parsed = DateTime.tryParse(day ?? '');
      if (parsed != null && parsed.toIso8601String().split('T').first == day) {
        return day;
      }
      return null;
    }
    return null;
  }

  static Map<String,dynamic> snapshot(
    Map<String,dynamic> detail, bool close, {bool local = false}
  ) {
    if (detail['kind'] != 'invoice' || (!local && detail['legacy_read_only'] == true) ||
        detail['_payment_reconciliation_required'] == true ||
        const {'void','cancelled'}.contains(detail['status'])) {
      throw StateError('This invoice needs review before finalization.');
    }
    final total = money(detail['total_amount']);
    final paid = money(detail['paid_amount']);
    final pending = money(detail['pending_payment']);
    final receipts = <Map<String,dynamic>>[];
    for (final p in (detail['payments'] as List? ?? []).whereType<Map>()) {
      if (p['state'] != 'pending') continue;
      final op = p['operation_id']?.toString();
      final id = p['id']?.toString();
      if ((op == null || op.isEmpty) && (id == null || id.isEmpty)) {
        throw StateError('A saved payment identity is missing. Review this invoice.');
      }
      receipts.add({
        'id': op == null || op.isEmpty ? id : null,
        'operation_id': op,
        'amount_cents': money(p['amount']),
        'method_id': p['payment_method_id'],
        if (local) 'method_name': p['payment_method_name']?.toString().trim(),
        'payment_date': local ? _localReceiptDate(p) :
            (p['payment_date'] ?? p['entered_at']?.toString().split('T').first),
      });
    }
    receipts.sort((a,b) => '${a['operation_id'] ?? a['id']}'.compareTo('${b['operation_id'] ?? b['id']}'));
    if (receipts.fold<int>(0,(s,r)=>s+(r['amount_cents'] as int)) != pending ||
        receipts.any((r) => r['payment_date'] == null ||
            (local ? (r['method_name'] as String? ?? '').isEmpty : r['method_id'] == null))) {
      throw StateError('Saved receipt details are incomplete. Your payments are preserved.');
    }
    if (close && (total != paid + pending || total <= 0)) {
      throw StateError('Every selected invoice must be fully covered by recorded payments.');
    }
    if (!close && pending <= 0) {
      throw StateError('There is no recorded payment awaiting finalization.');
    }
    return {'total_cents':total,'paid_cents':paid,'receipts':receipts,'close':close};
  }

  Future<void> save(String business, Iterable<String> ids,
      {required bool isOwner, required bool close}) async {
    if (!isOwner || business.isEmpty || ids.isEmpty) {
      throw StateError('Owner access and a saved invoice are required.');
    }
    await prepare();
    await db.transaction(() async {
      for (final id in ids.toSet()) {
        final detail = await LocalDocumentDetailCache(database:db).loadReadOnly(business,id);
        if (detail == null || detail['id'] != id) {
          throw StateError('Open each selected invoice once to verify its saved receipts.');
        }
        final edits = await db.customSelect("SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type IN ('invoice_pending_payment_edit','invoice_tax_edit','document_edit')",
          variables:[Variable(business),Variable(id)]).get();
        if (edits.isNotEmpty) throw StateError('Save and reconcile invoice corrections before finalization.');
        final projected = OfflineInvoicePaymentLedger.projectPendingPayments(detail,
          await OfflineInvoicePaymentLedger(database:db).pendingForInvoice(business,id));
        final payload = jsonEncode(snapshot(projected,close));
        final previous = await db.customSelect('SELECT payload,state,operation_id FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id=?',
          variables:[Variable(business),Variable(id)]).get();
        if (previous.isNotEmpty) {
          final old=Map<String,dynamic>.from(jsonDecode(previous.single.read<String>('payload')) as Map);
          final current=Map<String,dynamic>.from(jsonDecode(payload) as Map);
          final oldPaid=(old['paid_cents'] as int)+(old['receipts'] as List).fold<int>(0,(n,r)=>n+(r['amount_cents'] as int));
          final same=old['total_cents']==current['total_cents'] &&
            ((old['paid_cents']==current['paid_cents'] && jsonEncode(old['receipts'])==jsonEncode(current['receipts'])) ||
             ((current['receipts'] as List).isEmpty && current['paid_cents']==oldPaid));
          if(same) {
            if(close && old['close']!=true) {
              // Preserve the first operation and its immutable request even
              // after an ambiguous network result. Closing is a second durable
              // operation with NO receipts, after the first is acknowledged.
              await db.customStatement('INSERT OR IGNORE INTO invoice_finalization_close_followups_v1 VALUES(?,?,?,?)',
                [business,id,operationId(),jsonEncode({'total_cents':old['total_cents'],
                  'paid_cents':oldPaid,'receipts':<dynamic>[],'close':true})]);
              if(const {'confirmed','review'}.contains(previous.single.read<String>('state'))) {
                await db.customStatement("UPDATE invoice_finalization_intents_v1 SET state='pending' WHERE business_id=? AND invoice_id=?",[business,id]);
              }
            }
            continue;
          }
          final oldReceipts=(old['receipts'] as List)
              .map((r)=>r['operation_id'] ?? r['id']).toSet();
          final overlaps=(current['receipts'] as List)
              .any((r)=>oldReceipts.contains(r['operation_id'] ?? r['id']));
          if (overlaps) {
            throw StateError('Previously finalized receipts are still present in the saved details. Refresh their status before finalizing newer receipts. Original payments and the saved request are preserved.');
          }
          if(previous.single.read<String>('state')!='confirmed') {
            throw StateError('The earlier saved request must finish before changed payments can be finalized. Your payments are safe. Use Retry saved finalization when connected; do not enter them again.');
          }
          await db.customStatement('DELETE FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id=?',[business,id]);
          await db.customStatement('DELETE FROM invoice_finalization_close_followups_v1 WHERE business_id=? AND invoice_id=?',[business,id]);
        }
        final op=operationId();
        await db.customStatement('INSERT INTO invoice_finalization_intents_v1 VALUES(?,?,?,?,?,NULL)',
          [business,id,op,payload,'pending']);
      }
    });
  }

  /// Read the same durable payment and tax corrections shown on the invoice.
  Future<Map<String, dynamic>> projectLocalFinancialDetail(
    String business, String invoice, Map<String, dynamic> saved,
  ) async {
    final ledger = OfflineInvoicePaymentLedger(database: db);
    final taxed = await OfflineInvoiceTaxService(database: db)
        .projectPending(business, invoice, saved);
    return OfflineInvoicePaymentLedger.projectPendingEdits(
      OfflineInvoicePaymentLedger.projectPendingPayments(
        taxed, await ledger.pendingForInvoice(business, invoice),
      ),
      await ledger.pendingEditsForInvoice(business, invoice),
    );
  }

  /// Validate that saved corrections match this invoice and apply them
  /// locally. Ordinary synchronization can still send the preserved edits.
  Future<Map<String, dynamic>> verifyLocalFinancialDetail(
    String business, String invoice, Map<String, dynamic> saved, {
    List<Map<String, dynamic>>? queuedReceipts,
    bool forClosing = false,
  }) async {
    final ledger = OfflineInvoicePaymentLedger(database: db);
    final action = forClosing ? 'closing' : 'posting';
    try {
      await OfflineDocumentEditService(database: db)
          .verifySavedLineCorrections(business, invoice, saved, action: action);
      final taxed = await OfflineInvoiceTaxService(database: db)
          .verifySavedTaxCorrection(business, invoice, saved, action: action);
      final original = OfflineInvoicePaymentLedger.projectPendingPayments(
        taxed, queuedReceipts ?? await ledger.pendingForInvoice(business, invoice),
      );
      final corrected = OfflineInvoicePaymentLedger.projectPendingEdits(
        original, await ledger.pendingEditsForInvoice(business, invoice),
      );
      if (corrected['_payment_reconciliation_required'] == true) {
        throw StateError(original['_payment_reconciliation_required'] == true
            ? 'The saved receipt could overlap another payment. Review Payments before $action.'
            : 'A saved payment correction does not match the original receipt. Review that payment before $action.');
      }
      return corrected;
    } on FormatException {
      throw StateError('A saved correction cannot be read. Review Items and Payments before $action.');
    }
  }

  /// Finalize the existing local receipts without creating another payment.
  /// The receipt markers and Income rows commit together.
  Future<void> finalizeLocally(
    String business, String invoice, {
    required bool isOwner,
    bool resumeSavedRequest = false,
    Map<String, dynamic>? confirmedDetail,
  }) async {
    if (!isOwner || business.isEmpty || invoice.isEmpty) {
      throw StateError('Owner access and a saved invoice are required.');
    }
    final store = LocalInvoiceClosureStore(db);
    await prepare();
    await store.prepare();
    await store.prepareIncome();
    await db.transaction(() async {
      final saved = await LocalDocumentDetailCache(database: db)
          .loadReadOnly(business, invoice);
      if (saved == null || saved['id'] != invoice || saved['kind'] != 'invoice' ||
          const {'void', 'voided', 'cancelled', 'canceled'}
              .contains(saved['status']?.toString().toLowerCase())) {
        if (resumeSavedRequest) return;
        throw StateError('Open the saved invoice before finalizing its receipts.');
      }
      // Loading an old saved request is never authorization to backfill Income
      // on a historical closed invoice. Explicit Owner review stays separate.
      if (resumeSavedRequest && DocumentPresentation(saved).isClosed) return;
      final ledger = OfflineInvoicePaymentLedger(database: db);
      final queued = await ledger.pendingForInvoice(business, invoice);
      late Map<String, dynamic> detail;
      try {
        detail = await verifyLocalFinancialDetail(
          business, invoice, saved, queuedReceipts: queued,
        );
      } on StateError {
        if (resumeSavedRequest) return;
        rethrow;
      }
      if (resumeSavedRequest) {
        final intent = await db.customSelect(
          "SELECT payload FROM invoice_finalization_intents_v1 "
          "WHERE business_id=? AND invoice_id=? AND state IN ('pending','inflight','review')",
          variables: [Variable(business), Variable(invoice)],
        ).getSingleOrNull();
        if (intent == null) return;
        try {
          if (jsonEncode(snapshot(detail, false)) != intent.read<String>('payload')) return;
        } on StateError {
          return;
        }
      }

      if (confirmedDetail != null) {
        final remaining = await store.projectFinalized(business, detail);
        if (money(remaining['pending_payment']) == 0) return;
        if (jsonEncode(snapshot(remaining, false, local: true)) !=
            jsonEncode(snapshot(confirmedDetail, false, local: true))) {
          throw StateError('Payments changed. Reopen the invoice and confirm again.');
        }
      }

      final pending = LocalInvoiceClosureStore.verifiedPendingReceipts(detail);
      if (pending == null) {
        if (resumeSavedRequest) return;
        throw StateError('Saved receipt amounts need verification before finalizing.');
      }
      if (pending.isEmpty) return;

      final total = money(detail['total_amount']);
      final received = money(detail['paid_amount']) + money(detail['pending_payment']);
      if (received > total) {
        if (resumeSavedRequest) return;
        throw StateError('Recorded payments exceed the saved invoice total. Review the invoice total and payment amount before posting.');
      }

      final indexed = await db.customSelect(
        'SELECT d.document_number,d.job_id,j.job_number,'
        'COALESCE(c.display_name,j.customer_name) AS customer_name '
        'FROM local_documents d '
        'LEFT JOIN local_customers c ON c.business_id=d.business_id AND c.id=d.customer_id '
        'LEFT JOIN local_jobs j ON j.business_id=d.business_id AND j.id=d.job_id '
         "WHERE d.business_id=? AND d.id=? AND d.kind='invoice'",
        variables: [Variable(business), Variable(invoice)],
      ).getSingleOrNull();
      final queuedById = {for (final row in queued) row['operation_id']: row};
      final existing = await store.finalizedIncome(business, invoice: invoice);
      final receiptsById = <String, Map<String, dynamic>>{
        for (final row in existing)
          for (final key in ['receipt_id', 'server_payment_id', 'operation_id'])
            if (row[key]?.toString().isNotEmpty == true) row[key].toString(): row,
      };
      final rows = <String, Map<String, dynamic>>{};
      for (final payment in (detail['payments'] as List).whereType<Map>()) {
        if (payment['state'] != 'pending') continue;
        final id = LocalInvoiceClosureStore.receiptKey(payment);
        final stored = receiptsById[id] ?? receiptsById[payment['id']?.toString()];
        if (stored != null) {
          if (money(stored['amount']) != pending[id] && !resumeSavedRequest) {
            throw StateError('A locally posted receipt changed and requires review.');
          }
          continue;
        }
        final date = _localReceiptDate(payment);
        final method = payment['payment_method_name']?.toString().trim() ?? '';
        if (date == null || method.isEmpty) {
          if (resumeSavedRequest) return;
          throw StateError('The original payment date or method is missing.');
        }
        final isQueued = payment['_local_pending_payment'] == true;
        final acceptedId = queuedById[id]?['server_payment_id'];
        rows[id] = {
          'receipt_id': id,
          'operation_id': payment['operation_id'] ?? payment['client_operation_id'],
          'server_payment_id': isQueued
              ? acceptedId : payment['id'],
          'document_number': detail['document_number'] ?? indexed?.data['document_number'],
          'customer_name': detail['customer_name'] ?? indexed?.data['customer_name'],
          'job_id': detail['job_id'] ?? indexed?.data['job_id'],
          'job_number': detail['job_number'] ?? indexed?.data['job_number'],
          'payment_method': method,
          'payment_method_id': payment['payment_method_id'],
          'amount': pending[id]! / 100,
          'invoice_total': detail['total_amount'],
          'transaction_date': date,
          'received_at': payment['entered_at'],
          'receipt_state': 'local_finalized',
        };
      }
      await store.saveFinalized(business, invoice, {
        for (final id in rows.keys) id: pending[id]!,
      });
      final journal = LocalFinancialTotalsJournal(database: db);
      for (final entry in rows.entries) {
        await db.customStatement(
          'INSERT OR IGNORE INTO local_finalized_invoice_income '
          '(business_id,invoice_id,receipt_id,payload) VALUES(?,?,?,?)',
          [business, invoice, entry.key, jsonEncode(entry.value)],
        );
        final key = 'invoice-payment:${entry.key}';
        await journal.record(business, key, after: {
          'id': key,
          'document_id': invoice,
          'invoice_total': entry.value['invoice_total'],
          'amount': entry.value['amount'],
          'direction': 'income',
          'transaction_date': entry.value['transaction_date'],
          'locally_finalized_invoice_receipt': true,
          'sync_state': 'pending',
        });
      }
    });
  }

  static String operationId() {
    final random=Random.secure();
    final bytes=List.generate(16,(_)=>random.nextInt(256));
    bytes[6]=(bytes[6]&15)|64; bytes[8]=(bytes[8]&63)|128;
    final h=bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<String?> state(String business,String invoice) async {
    await prepare();
    final rows=await db.customSelect('SELECT state FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id=?',
      variables:[Variable(business),Variable(invoice)]).get();
    return rows.firstOrNull?.read<String>('state');
  }
  /// Pending/review intents always block new submissions. A confirmed intent
  /// blocks only the same receipt identities; a later payment is independent.
  Future<String?> stateForDetail(String business,String invoice,Map<String,dynamic> detail) async {
    await prepare();
    // A screen opened before draft synchronization can retain its local route
    // while the durable intent has moved to the exact saved server identity.
    final server = detail['_server_document_id']?.toString().trim() ?? '';
    final identitiesToRead = <String>{invoice,
      if (server.isNotEmpty && (detail['id'] == invoice ||
          (invoice.startsWith('local-') && detail['id'] == server))) server};
    final rows=await db.customSelect(
      'SELECT state,payload FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id IN (${List.filled(identitiesToRead.length, '?').join(',')})',
      variables:[Variable(business), ...identitiesToRead.map(Variable<String>.new)]).get();
    if(rows.isEmpty) return null;
    if (rows.length != 1) return 'review';
    final state=rows.single.read<String>('state');
    if(state!='confirmed') return state;
    final old=jsonDecode(rows.single.read<String>('payload')) as Map;
    final identities=(old['receipts'] as List).map((r)=>r['operation_id'] ?? r['id']).toSet();
    final pending=(detail['payments'] as List? ?? []).whereType<Map>().where((p)=>p['state']=='pending');
    if(pending.every((p)=>identities.contains(p['operation_id'] ?? p['id']))) return 'confirmed';
    if(pending.any((p)=>identities.contains(p['operation_id'] ?? p['id']))) return 'review';
    return null;
  }

  Future<void> retry(String business,String invoice,{required bool isOwner}) async {
    if(!isOwner) throw StateError('Owner access required.');
    if(BriskersConnectionModeController.instance.forceOffline) {
      throw StateError('The saved request is safe. Retry after you choose to connect.');
    }
    await prepare();
    await db.customStatement("UPDATE invoice_finalization_intents_v1 SET state='pending' WHERE business_id=? AND invoice_id=? AND state='review'",[business,invoice]);
    await flush(business);
  }

  Future<void> remap(String business,String local,String server) async {
    await prepare();
    await LocalInvoiceClosureStore(db).prepare();
    await LocalInvoiceClosureStore(db).prepareIncome();
    for (final table in ['local_invoice_closures', 'local_invoice_closed_receipts',
      'local_invoice_reopen_audit', 'local_finalized_invoice_income']) {
      await db.customStatement(
        'UPDATE $table SET invoice_id=? WHERE business_id=? AND invoice_id=?',
        [server,business,local],
      );
    }
    await db.customStatement('UPDATE invoice_finalization_intents_v1 SET invoice_id=? WHERE business_id=? AND invoice_id=?',[server,business,local]);
    await db.customStatement('UPDATE invoice_finalization_close_followups_v1 SET invoice_id=? WHERE business_id=? AND invoice_id=?',[server,business,local]);
  }

  static final _activeFlushes = Expando<Map<String, Future<void>>>();

  Future<void> flush(String business) async {
    if (BriskersConnectionModeController.instance.forceOffline) return;
    final active = _activeFlushes[db] ??= {};
    final existing = active[business];
    if (existing != null) return existing;
    final pending = _flush(business);
    active[business] = pending;
    try {
      await pending;
    } finally {
      active.remove(business);
    }
  }

  Future<void> _flush(String business) async {
    if (BriskersConnectionModeController.instance.forceOffline) return;
    await prepare();
    final rows=await db.customSelect("SELECT * FROM invoice_finalization_intents_v1 WHERE business_id=? AND state IN ('pending','inflight')",
      variables:[Variable(business)]).get();
    for(final row in rows) {
      if (BriskersConnectionModeController.instance.forceOffline) return;
      final invoice=row.read<String>('invoice_id');
      if(invoice.startsWith('local-')) continue;
      if(await LocalJobQuarantine.isEntityBlocked(db,business,[invoice]) ||
          await LocalJobRetirement.isDocumentBlocked(db,business,invoice) ||
          await LocalDocumentDetailCache(database:db).loadReadOnly(business,invoice)==null) {
        continue;
      }
      final unresolved=await db.customSelect("SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type IN ('invoice_payment_received','invoice_pending_payment_edit','invoice_tax_edit','document_edit')",
        variables:[Variable(business),Variable(invoice)]).get();
      if(unresolved.isNotEmpty) continue;
      final operation=row.read<String>('operation_id');
      await db.customStatement("UPDATE invoice_finalization_intents_v1 SET state='inflight' WHERE business_id=? AND invoice_id=?",[business,invoice]);
      try {
        if (BriskersConnectionModeController.instance.forceOffline) return;
        final request=Map<String,dynamic>.from(jsonDecode(row.read<String>('payload')) as Map);
        final response=await api.finalizeInvoiceOnce(business,invoice,operation,request);
        if(response['operation_id']!=operation || response['invoice_id']!=invoice || response['finalized']!=true || (request['close']==true && response['closed']!=true)) {
          throw StateError('Finalization response requires review.');
        }
        final followups=await db.customSelect('SELECT operation_id,payload FROM invoice_finalization_close_followups_v1 WHERE business_id=? AND invoice_id=?',variables:[Variable(business),Variable(invoice)]).get();
        if(followups.isNotEmpty) {
          if(BriskersConnectionModeController.instance.forceOffline)return;
          final followup=followups.single;
          final key=followup.read<String>('operation_id');
          final closed=await api.finalizeInvoiceOnce(business,invoice,key,
            Map<String,dynamic>.from(jsonDecode(followup.read<String>('payload')) as Map));
          if(closed['operation_id']!=key || closed['invoice_id']!=invoice || closed['finalized']!=true || closed['closed']!=true) {
            throw StateError('Saved closure needs reconciliation. Payments remain preserved.');
          }
        }
        await db.customStatement("UPDATE invoice_finalization_intents_v1 SET state='confirmed',error=NULL WHERE business_id=? AND invoice_id=?",[business,invoice]);
      } catch(error) {
        // Hold after one attempt per sync pass. Explicit review is required;
        // never repeatedly execute an ambiguous financial operation.
        await db.customStatement("UPDATE invoice_finalization_intents_v1 SET state='review',error=? WHERE business_id=? AND invoice_id=?",[error.toString(),business,invoice]);
      }
    }
  }

}
