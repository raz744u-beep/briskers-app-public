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

/// Owner-confirmed intents, separate from received payments and server posting.
/// A queued intent never fabricates a posted payment or a server-confirmed close.
class OfflineInvoiceFinalization {
  OfflineInvoiceFinalization({BriskersLocalDatabase? database,
    this.api = const BriskersApi()})
      : db = database ?? localDatabase;
  final BriskersLocalDatabase db;
  final BriskersApi api;

  Future<void> prepare() => db.customStatement('''CREATE TABLE IF NOT EXISTS
    invoice_finalization_intents_v1(business_id TEXT NOT NULL,invoice_id TEXT NOT NULL,
    operation_id TEXT NOT NULL,payload TEXT NOT NULL,state TEXT NOT NULL,
    error TEXT,PRIMARY KEY(business_id,invoice_id))''');

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
        final previous = await db.customSelect('SELECT payload,state FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id=?',
          variables:[Variable(business),Variable(id)]).get();
        if (previous.isNotEmpty) {
          if (previous.single.read<String>('state') == 'confirmed' && previous.single.read<String>('payload') != payload) {
            await db.customStatement('DELETE FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id=?',[business,id]);
          } else {
          if (previous.single.read<String>('payload') != payload) {
            throw StateError('This invoice has a different finalization awaiting reconciliation.');
          }
          continue;
          }
        }
        final random = Random.secure();
        final bytes=List.generate(16,(_)=>random.nextInt(256));
        bytes[6]=(bytes[6]&15)|64; bytes[8]=(bytes[8]&63)|128;
        final h=bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
        final op='${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
        await db.customStatement('INSERT INTO invoice_finalization_intents_v1 VALUES(?,?,?,?,?,NULL)',
          [business,id,op,payload,'pending']);
      }
    });
  }

  Future<String?> state(String business,String invoice) async {
    await prepare();
    final rows=await db.customSelect('SELECT state FROM invoice_finalization_intents_v1 WHERE business_id=? AND invoice_id=?',
      variables:[Variable(business),Variable(invoice)]).get();
    return rows.firstOrNull?.read<String>('state');
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
    await db.customStatement('UPDATE invoice_finalization_intents_v1 SET invoice_id=? WHERE business_id=? AND invoice_id=?',[server,business,local]);
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
      if(await LocalJobQuarantine.isEntityBlocked(db,business,[invoice])) continue;
      final unresolved=await db.customSelect("SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type IN ('invoice_payment_received','invoice_pending_payment_edit','invoice_tax_edit','document_edit')",
        variables:[Variable(business),Variable(invoice)]).get();
      if(unresolved.isNotEmpty) continue;
      final operation=row.read<String>('operation_id');
      await db.customStatement("UPDATE invoice_finalization_intents_v1 SET state='inflight' WHERE business_id=? AND invoice_id=?",[business,invoice]);
      try {
        final response=await api.finalizeInvoiceOnce(business,invoice,operation,
          Map<String,dynamic>.from(jsonDecode(row.read<String>('payload')) as Map));
        if(response['operation_id']!=operation || response['invoice_id']!=invoice || response['finalized']!=true) {
          throw StateError('Finalization response requires review.');
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
