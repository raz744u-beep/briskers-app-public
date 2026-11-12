import 'local_invoice_closure.dart';
import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'offline_invoice_payment_ledger.dart';
import 'local_job_quarantine.dart';
import 'local_job_retirement.dart';

/// Owner-confirmed intents, separate from received payments and server posting.
/// A queued intent never fabricates a posted payment or a server-confirmed close.
class OfflineInvoiceFinalization {
  OfflineInvoiceFinalization({BriskersLocalDatabase? database,
    this.api = const BriskersApi()})
      : db = database ?? localDatabase;
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

  static Map<String,dynamic> snapshot(Map<String,dynamic> detail, bool close) {
    if (detail['kind'] != 'invoice' || detail['legacy_read_only'] == true ||
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
        'payment_date': p['payment_date'] ?? p['entered_at']?.toString().split('T').first,
      });
    }
    receipts.sort((a,b) => '${a['operation_id'] ?? a['id']}'.compareTo('${b['operation_id'] ?? b['id']}'));
    if (receipts.fold<int>(0,(s,r)=>s+(r['amount_cents'] as int)) != pending ||
        receipts.any((r)=>r['method_id']==null || r['payment_date']==null)) {
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
    final rows=await db.customSelect('SELECT state,payload FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id=?',
      variables:[Variable(business),Variable(invoice)]).get();
    if(rows.isEmpty) return null;
    final state=rows.single.read<String>('state');
    if(state!='confirmed') return state;
    final old=jsonDecode(rows.single.read<String>('payload')) as Map;
    final identities=(old['receipts'] as List).map((r)=>r['operation_id'] ?? r['id']).toSet();
    final pending=(detail['payments'] as List? ?? []).whereType<Map>().where((p)=>p['state']=='pending');
    if(pending.every((p)=>identities.contains(p['operation_id'] ?? p['id']))) return 'confirmed';
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
    await db.customStatement('UPDATE local_invoice_closures SET invoice_id=? WHERE business_id=? AND invoice_id=?',[server,business,local]);
    await db.customStatement('UPDATE invoice_finalization_intents_v1 SET invoice_id=? WHERE business_id=? AND invoice_id=?',[server,business,local]);
    await db.customStatement('UPDATE invoice_finalization_close_followups_v1 SET invoice_id=? WHERE business_id=? AND invoice_id=?',[server,business,local]);
  }

  Future<void> flush(String business) async {
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
