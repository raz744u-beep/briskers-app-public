import 'dart:convert';
import 'offline_invoice_finalization.dart';
import 'package:drift/drift.dart';
import '../core/connection_mode.dart';
import '../core/document_presentation.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'offline_invoice_payment_ledger.dart';
import 'verified_invoice_close_events.dart';

/// Durable owner lifecycle decisions. This table contains no payment writes.
class LocalInvoiceClosureStore {
  LocalInvoiceClosureStore(this.db);
  final BriskersLocalDatabase db;
  Future<void> prepare() => db.customStatement('''CREATE TABLE IF NOT EXISTS
    local_invoice_closures(business_id TEXT NOT NULL,invoice_id TEXT NOT NULL,
    closed_at TEXT NOT NULL,operation_id TEXT NOT NULL,payload TEXT NOT NULL,sync_state TEXT NOT NULL DEFAULT 'pending',error TEXT,retry_after INTEGER NOT NULL DEFAULT 0,reopened_at TEXT,
    PRIMARY KEY(business_id,invoice_id))''');

  Future<void> serverReopened(String business,String invoice) async {
    await prepare();
    await db.customStatement("UPDATE local_invoice_closures SET reopened_at=?,sync_state='reopened' WHERE business_id=? AND invoice_id=?",
      [DateTime.now().toUtc().toIso8601String(),business,invoice]);
  }

  Future<List<Map<String,dynamic>>> projectRows(String business,List<Map<String,dynamic>> documents) async {
    final exists=await db.customSelect("SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_invoice_closures'").getSingleOrNull();
    if(exists==null) return documents;
    final rows=await db.customSelect('SELECT invoice_id,closed_at FROM local_invoice_closures WHERE business_id=? AND reopened_at IS NULL',variables:[Variable(business)]).get();
    final closed={for(final r in rows) r.read<String>('invoice_id'):r.read<String>('closed_at')};
    return [for(final d in documents) if(closed.containsKey(d['id']))
      {...d,'status':'closed','display_status_code':'closed','display_status':'Closed','closed_at':closed[d['id']]} else d];
  }

  Future<Map<String,dynamic>> project(String business, Map<String,dynamic> detail) async {
    final exists=await db.customSelect("SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_invoice_closures'").getSingleOrNull();
    if(exists==null) return detail;
    final rows = await db.customSelect('SELECT closed_at FROM local_invoice_closures WHERE business_id=? AND invoice_id=? AND reopened_at IS NULL',
      variables:[Variable(business),Variable(detail['id']?.toString() ?? '')]).get();
    if(rows.isEmpty) return detail;
    return {...detail,'status':'closed','display_status_code':'closed',
      'display_status':'Closed','closed_at':rows.single.read<String>('closed_at')};
  }
}

class LocalInvoiceClosure {
  LocalInvoiceClosure({BriskersLocalDatabase? database,this.api=const BriskersApi()})
      : db=database ?? localDatabase;
  final BriskersLocalDatabase db;
  final BriskersApi api;

  Future<void> close(String business,Iterable<String> invoices,{required bool isOwner}) async {
    if(!isOwner || business.isEmpty || invoices.isEmpty) throw StateError('Owner access required.');
    final store=LocalInvoiceClosureStore(db);
    await store.prepare();
    final ids=invoices.toSet();
    await db.transaction(() async {
      for(final id in ids) {
        final existing=await db.customSelect('SELECT 1 FROM local_invoice_closures WHERE business_id=? AND invoice_id=? AND reopened_at IS NULL',variables:[Variable(business),Variable(id)]).get();
        if(existing.isNotEmpty) continue;
        final saved=await LocalDocumentDetailCache(database:db).loadReadOnly(business,id);
        if(saved==null || saved['id']!=id || saved['kind']!='invoice' || saved['legacy_read_only']==true) {
          throw StateError('Open this invoice once to verify its saved payment details.');
        }
        final edits=await db.customSelect("SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type IN ('invoice_pending_payment_edit','invoice_tax_edit','document_edit')",variables:[Variable(business),Variable(id)]).get();
        if(edits.isNotEmpty) throw StateError('Finish the saved invoice corrections before closing.');
        final detail=OfflineInvoicePaymentLedger.projectPendingPayments(saved,
          await OfflineInvoicePaymentLedger(database:db).pendingForInvoice(business,id));
        final financial=DocumentPresentation(detail);
        if(!financial.paymentDetailsKnown || !financial.fullyCovered || financial.isVoid) {
          throw StateError('Only invoices fully covered by saved payments can be closed. Payments are unchanged.');
        }
        final at=DateTime.now().toUtc().toIso8601String();
        await db.customStatement('INSERT OR IGNORE INTO local_invoice_closures(business_id,invoice_id,closed_at,operation_id,payload) VALUES(?,?,?,?,?) ON CONFLICT(business_id,invoice_id) DO UPDATE SET closed_at=excluded.closed_at,operation_id=excluded.operation_id,payload=excluded.payload,sync_state=excluded.sync_state,error=NULL,retry_after=0,reopened_at=NULL',[business,id,at,OfflineInvoiceFinalization.operationId(),jsonEncode({'total_cents':financial.totalCents,'paid_cents':financial.finalizedCents!+financial.pendingCents!,'receipts':<dynamic>[],'close':true})]);
        await db.customStatement("UPDATE local_documents SET status='closed',display_status_code='closed',closed_at=? WHERE business_id=? AND id=? AND kind='invoice'",[DateTime.parse(at).millisecondsSinceEpoch ~/ 1000,business,id]);
      }
    });
    for(final id in ids) {
      VerifiedInvoiceCloseEvents.locallyCommitted(VerifiedInvoiceClosed(businessId:business,invoiceId:id));
    }
  }

  /// An immutable close-only request is idempotent and cannot post receipts.
  /// Unposted receipts may delay server closure, but cannot undo local closure.
  Future<void> flush(String business) async {
    if(BriskersConnectionModeController.instance.forceOffline) return;
    await LocalInvoiceClosureStore(db).prepare();
    final rows=await db.customSelect("SELECT * FROM local_invoice_closures WHERE business_id=? AND sync_state='pending' AND reopened_at IS NULL AND retry_after<=?",variables:[Variable(business),Variable(DateTime.now().millisecondsSinceEpoch)]).get();
    for(final row in rows) {
      if(BriskersConnectionModeController.instance.forceOffline) return;
      final id=row.read<String>('invoice_id');
      if(id.startsWith('local-')) continue;
      final saved=await LocalDocumentDetailCache(database:db).loadReadOnly(business,id);
      if(saved==null) continue; // retirement fences remain authoritative
      try {
        // The legacy close RPC may post pending receipts. Use the existing
        // atomic endpoint with an EMPTY receipt set: its locked comparison
        // rejects any unposted/changed payments before it can close.
        final operation=row.read<String>('operation_id');
        final response=await api.finalizeInvoiceOnce(business,id,operation,
          Map<String,dynamic>.from(jsonDecode(row.read<String>('payload')) as Map));
        if(response['operation_id']!=operation || response['invoice_id']!=id || response['closed']!=true) {
          throw StateError('Close acknowledgment does not match the saved invoice.');
        }
        await db.customStatement("UPDATE local_invoice_closures SET sync_state='confirmed',error=NULL WHERE business_id=? AND invoice_id=?",[business,id]);
      } catch(error) {
        await db.customStatement('UPDATE local_invoice_closures SET error=?,retry_after=? WHERE business_id=? AND invoice_id=? AND reopened_at IS NULL',[error.toString(),DateTime.now().millisecondsSinceEpoch+60000,business,id]);
      }
    }
  }
}
