import 'dart:convert';
import 'offline_invoice_finalization.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../core/connection_mode.dart';
import '../core/document_presentation.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'verified_invoice_close_events.dart';
import 'sync_replay_fence.dart';

/// Durable owner lifecycle decisions. This table contains no payment writes.
class LocalInvoiceClosureStore {
  LocalInvoiceClosureStore(this.db);
  final BriskersLocalDatabase db;
  Future<void> prepare() async {
    await db.customStatement('''CREATE TABLE IF NOT EXISTS
      local_invoice_closures(business_id TEXT NOT NULL,invoice_id TEXT NOT NULL,
      closed_at TEXT NOT NULL,operation_id TEXT NOT NULL,payload TEXT NOT NULL,sync_state TEXT NOT NULL DEFAULT 'pending',error TEXT,retry_after INTEGER NOT NULL DEFAULT 0,reopened_at TEXT,
      PRIMARY KEY(business_id,invoice_id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS
      local_invoice_closed_receipts(business_id TEXT NOT NULL, invoice_id TEXT NOT NULL,
      receipt_id TEXT NOT NULL, amount_cents INTEGER NOT NULL,
      PRIMARY KEY(business_id,invoice_id,receipt_id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS
      local_invoice_reopen_audit(operation_id TEXT PRIMARY KEY, business_id TEXT NOT NULL,
      invoice_id TEXT NOT NULL, reason TEXT NOT NULL, reopened_at TEXT NOT NULL,
      expected_version INTEGER, sync_state TEXT NOT NULL)''');
  }

  Future<void> prepareIncome() => db.customStatement('''
    CREATE TABLE IF NOT EXISTS local_finalized_invoice_income (
      business_id TEXT NOT NULL, invoice_id TEXT NOT NULL,
      receipt_id TEXT NOT NULL, payload TEXT NOT NULL,
      PRIMARY KEY (business_id, invoice_id, receipt_id)
    )
  ''');

  Future<List<Map<String, dynamic>>> finalizedIncome(String business, {String? invoice}) async {
    await prepareIncome();
    final rows = await db.customSelect(
      'SELECT invoice_id,payload FROM local_finalized_invoice_income WHERE business_id=?'
      '${invoice == null ? '' : ' AND invoice_id=?'}',
      variables: [Variable(business), if (invoice != null) Variable(invoice)],
    ).get();
    return [
      for (final row in rows)
        {
          ...Map<String, dynamic>.from(jsonDecode(row.read<String>('payload')) as Map),
          'invoice_id': row.read<String>('invoice_id'),
        },
    ];
  }

  Future<void> acknowledgeIncomeReceipt(
    String business, String invoice, String operation, String serverPayment,
  ) async {
    await prepareIncome();
    final row = await db.customSelect(
      'SELECT payload FROM local_finalized_invoice_income '
      'WHERE business_id=? AND invoice_id=? AND receipt_id=?',
      variables: [Variable(business), Variable(invoice), Variable(operation)],
    ).getSingleOrNull();
    if (row == null) return;
    final payload = jsonDecode(row.read<String>('payload')) as Map;
    await db.customStatement(
      'UPDATE local_finalized_invoice_income SET payload=? '
      'WHERE business_id=? AND invoice_id=? AND receipt_id=?',
      [jsonEncode({...payload, 'server_payment_id': serverPayment}),
        business, invoice, operation],
    );
  }

  static String receiptKey(Map payment) =>
      (payment['operation_id'] ?? payment['client_operation_id'] ?? payment['id'])
          ?.toString().trim() ?? '';

  static Map<String, int>? verifiedPendingReceipts(Map<String, dynamic> detail) {
    final pending = DocumentPresentation(detail).pendingCents;
    final receipts = <String, int>{};
    for (final payment in (detail['payments'] as List? ?? []).whereType<Map>()) {
      if (payment['state'] != 'pending') continue;
      final id = receiptKey(payment);
      final amount = num.tryParse(payment['amount']?.toString() ?? '');
      if (id.isEmpty || receipts.containsKey(id) ||
          amount == null || !amount.isFinite || amount <= 0 ||
          !(amount * 100).isFinite || payment['reconciliation_required'] == true) {
        return null;
      }
      receipts[id] = (amount * 100).round();
    }
    return receipts.values.fold<int>(0, (sum, amount) => sum + amount) == pending
        ? receipts : null;
  }

  /// Apply this after the durable receipt queue so synchronization metadata and
  /// the original accounting rows remain independent of local finalization.
  Future<Map<String, dynamic>> projectFinalized(
    String business, Map<String, dynamic> detail,
  ) async {
    final financial = DocumentPresentation(detail);
    final pending = verifiedPendingReceipts(detail);
    if (!financial.paymentDetailsKnown || pending == null || pending.isEmpty) {
      return detail;
    }
    final invoice = detail['id']?.toString() ?? '';
    final hasClosures = await db.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_invoice_closures'",
    ).getSingleOrNull();
    if (hasClosures == null) return detail;
    final receipts = await db.transaction(() async {
      await prepare();
      await prepareIncome();
      final stored = await db.customSelect(
        'SELECT receipt_id,amount_cents FROM local_invoice_closed_receipts '
        'WHERE business_id=? AND invoice_id=?',
        variables: [Variable(business), Variable(invoice)],
      ).get();
      if (stored.isNotEmpty) {
        final aliases = await db.customSelect(
          'SELECT receipt_id,payload FROM local_finalized_invoice_income '
          'WHERE business_id=? AND invoice_id=?',
          variables: [Variable(business), Variable(invoice)],
        ).get();
        final amounts = {
          for (final row in stored) row.read<String>('receipt_id'): row.read<int>('amount_cents'),
        };
        for (final row in aliases) {
          final receipt = jsonDecode(row.read<String>('payload')) as Map;
          final receiptId = row.read<String>('receipt_id');
          final alias = receipt['server_payment_id']?.toString() ?? '';
          if (alias.isNotEmpty && amounts.containsKey(receiptId)) {
            amounts.putIfAbsent(alias, () => amounts[receiptId]!);
          }
        }
        return amounts;
      }
      // Upgrade a 4668 local closure only when its recorded amount still
      // agrees with a complete, unambiguous saved receipt snapshot.
      final old = await db.customSelect(
        'SELECT payload FROM local_invoice_closures '
        'WHERE business_id=? AND invoice_id=? AND reopened_at IS NULL',
        variables: [Variable(business), Variable(invoice)],
      ).getSingleOrNull();
      if (old == null) return <String, int>{};
      final payload = jsonDecode(old.read<String>('payload')) as Map;
      if (payload['total_cents'] != financial.totalCents ||
          payload['paid_cents'] != financial.finalizedCents! + financial.pendingCents!) {
        return <String, int>{};
      }
      await saveFinalized(business, invoice, pending);
      return pending;
    });
    final finalized = pending.keys.where((id) => receipts[id] == pending[id]).toSet();
    if (finalized.isEmpty) return detail;
    final cents = finalized.fold<int>(0, (sum, id) => sum + receipts[id]!);
    return {
      ...detail,
      'paid_amount': (financial.finalizedCents! + cents) / 100,
      'pending_payment': (financial.pendingCents! - cents) / 100,
      'payments': [
        for (final payment in (detail['payments'] as List).whereType<Map>())
          if (payment['state'] == 'pending' && finalized.contains(receiptKey(payment)))
            {...payment, 'state': 'posted', '_finalized_locally': true}
          else payment,
      ],
    };
  }

  Future<void> saveFinalized(
    String business, String invoice, Map<String, int> receipts,
  ) async {
    for (final receipt in receipts.entries) {
      await db.customStatement(
        'INSERT OR IGNORE INTO local_invoice_closed_receipts '
        '(business_id,invoice_id,receipt_id,amount_cents) VALUES(?,?,?,?)',
        [business, invoice, receipt.key, receipt.value],
      );
    }
  }

  Future<void> serverReopened(String business,String invoice) async {
    await prepare();
    await db.customStatement("UPDATE local_invoice_closures SET reopened_at=?,sync_state='reopened' WHERE business_id=? AND invoice_id=?",
      [DateTime.now().toUtc().toIso8601String(),business,invoice]);
  }

  Future<List<Map<String,dynamic>>> projectRows(String business,List<Map<String,dynamic>> documents) async {
    final exists=await db.customSelect("SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_invoice_closures'").getSingleOrNull();
    if(exists==null) return documents;
    final rows=await db.customSelect('SELECT invoice_id,closed_at,reopened_at,sync_state FROM local_invoice_closures WHERE business_id=?',variables:[Variable(business)]).get();
    final overlays={for(final r in rows) r.read<String>('invoice_id'):r.data};
    return [for (final document in documents) _applyLifecycle(document, overlays[document['id']])];
  }

  Future<Map<String,dynamic>> project(String business, Map<String,dynamic> detail) async {
    final exists=await db.customSelect("SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_invoice_closures'").getSingleOrNull();
    if(exists==null) return detail;
    final rows = await db.customSelect('SELECT closed_at,reopened_at,sync_state FROM local_invoice_closures WHERE business_id=? AND invoice_id=?',
      variables:[Variable(business),Variable(detail['id']?.toString() ?? '')]).get();
    return _applyLifecycle(detail, rows.singleOrNull?.data);
  }

  static Map<String, dynamic> _applyLifecycle(
    Map<String, dynamic> detail, Map<String, dynamic>? lifecycle,
  ) {
    if (lifecycle == null) return detail;
    if (lifecycle['reopened_at'] == null) {
      return {...detail, 'status': 'closed', 'display_status_code': 'closed',
        'display_status': 'Closed', 'closed_at': lifecycle['closed_at']};
    }
    final state = lifecycle['sync_state'];
    if (state != 'reopen_pending' && state != 'reopen_review') return detail;
    final projection = {...detail, 'status': 'issued', 'closed_at': null,
      'display_status_code': 'open', 'legacy_read_only': false};
    final wasFullyPaid = DocumentPresentation(detail).fullyCovered;
    final code = wasFullyPaid ? 'paid' : 'open';
    return {...projection, 'display_status_code': code, 'display_status': wasFullyPaid ? 'Paid' : 'Open'};
  }
}

class LocalInvoiceClosure {
  LocalInvoiceClosure({BriskersLocalDatabase? database, BriskersApi? api,
    bool enableLegacyReplay = false,
  }) : db = database ?? localDatabase, api = api ?? const BriskersApi(),
       _enableLegacyReplay = enableLegacyReplay;
  final BriskersLocalDatabase db;
  final BriskersApi api;
  final bool _enableLegacyReplay;

  Future<Map<String, Map<String, dynamic>>> preview(String business, Iterable<String> invoices, {required bool isOwner}) async {
    if (!isOwner || business.isEmpty) throw StateError('Owner access required.');
    final result = <String, Map<String, dynamic>>{};
    final store = LocalInvoiceClosureStore(db);
    await store.prepare();
    for (final id in invoices.toSet()) {
      final saved = await LocalDocumentDetailCache(database: db).loadReadOnly(business, id);
      if (saved == null) throw StateError('Open the invoice to verify saved payment details.');
      if (DocumentPresentation(saved).isClosed) continue;
      final corrected = await OfflineInvoiceFinalization(database: db)
          .verifyLocalFinancialDetail(business, id, saved, forClosing: true);
      result[id] = OfflineInvoiceFinalization.snapshot(
        await store.projectFinalized(business, corrected), true, local: true);
    }
    return result;
  }

  Future<void> close(String business,Iterable<String> invoices,{required bool isOwner,
    Map<String, Map<String, dynamic>>? confirmed}) async {
    if(!isOwner || business.isEmpty || invoices.isEmpty) throw StateError('Owner access required.');
    final store=LocalInvoiceClosureStore(db);
    await store.prepare();
    final ids=invoices.toSet();
    await db.transaction(() async {
      for(final id in ids) {
        final existing=await db.customSelect('SELECT 1 FROM local_invoice_closures WHERE business_id=? AND invoice_id=? AND reopened_at IS NULL',variables:[Variable(business),Variable(id)]).get();
        final saved=await LocalDocumentDetailCache(database:db).loadReadOnly(business,id);
        if(saved==null || saved['id']!=id || saved['kind']!='invoice' || const {'void','voided','cancelled','canceled'}.contains(saved['status']?.toString().toLowerCase())) {
          throw StateError('Open this invoice once to verify its saved payment details.');
        }
        if (existing.isNotEmpty) continue;
        if (DocumentPresentation(saved).isClosed) continue;
        final corrected = await OfflineInvoiceFinalization(database: db)
            .verifyLocalFinancialDetail(business, id, saved, forClosing: true);
        final detail = await store.projectFinalized(business, corrected);
        final financial=DocumentPresentation(detail);
        if(!financial.paymentDetailsKnown || !financial.fullyCovered || financial.isVoid) {
          throw StateError('Only invoices fully covered by saved payments can be closed. Payments are unchanged.');
        }
        final receipts = LocalInvoiceClosureStore.verifiedPendingReceipts(detail);
        if (receipts == null) {
          throw StateError('Saved receipt amounts need verification before closing.');
        }
        if (confirmed != null && jsonEncode(confirmed[id]) !=
            jsonEncode(OfflineInvoiceFinalization.snapshot(detail, true, local: true))) {
          throw StateError('Payments changed. Review and confirm closure again.');
        }
        // Receipt markers, dated Income rows, totals and closure commit or roll
        // back as one transaction, including every invoice in a batch.
        await OfflineInvoiceFinalization(database: db).finalizeLocally(
          business, id, isOwner: isOwner, confirmedDetail: detail);
        final at=DateTime.now().toUtc().toIso8601String();
        await db.customStatement('INSERT OR IGNORE INTO local_invoice_closures(business_id,invoice_id,closed_at,operation_id,payload) VALUES(?,?,?,?,?) ON CONFLICT(business_id,invoice_id) DO UPDATE SET closed_at=excluded.closed_at,operation_id=excluded.operation_id,payload=excluded.payload,sync_state=excluded.sync_state,error=NULL,retry_after=0,reopened_at=NULL',[business,id,at,OfflineInvoiceFinalization.operationId(),jsonEncode({'total_cents':financial.totalCents,'paid_cents':financial.finalizedCents!+financial.pendingCents!,'receipts':<dynamic>[],'close':true})]);
        await db.customStatement("UPDATE local_documents SET status='closed',display_status_code='closed',closed_at=? WHERE business_id=? AND id=? AND kind='invoice'",[DateTime.parse(at).millisecondsSinceEpoch ~/ 1000,business,id]);
      }
    });
    for(final id in ids) {
      VerifiedInvoiceCloseEvents.locallyCommitted(VerifiedInvoiceClosed(businessId:business,invoiceId:id));
    }
  }

  Future<void> reopen(String business, String id, {
    required bool isOwner, required String reason,
  }) async {
    final note = reason.trim();
    if (!isOwner || business.isEmpty || note.length < 10) {
      throw StateError('An Owner and a reopening reason are required.');
    }
    final store = LocalInvoiceClosureStore(db);
    await store.prepare();
    await db.transaction(() async {
      final raw = await LocalDocumentDetailCache(database: db)
          .loadReadOnly(business, id, projectLifecycle: false);
      final saved = raw == null ? null : await store.project(business, raw);
      if (raw == null || saved == null || saved['id'] != id || saved['kind'] != 'invoice' ||
          const {'void', 'voided', 'cancelled', 'canceled'}.contains(saved['status']) ||
          !DocumentPresentation(saved).isClosed && saved['legacy_read_only'] != true) {
        throw StateError('The saved invoice is unavailable or already reopened.');
      }
      final remoteNeedsReopen = DocumentPresentation(raw).isClosed ||
          raw['legacy_read_only'] == true;
      final now = DateTime.now().toUtc().toIso8601String();
      final version = int.tryParse(saved['row_version']?.toString() ?? '');
      final operation = OfflineInvoiceFinalization.operationId();
      final state = !remoteNeedsReopen ? 'reopen_local'
          : version == null || id.startsWith('local-') ? 'reopen_review' : 'reopen_pending';
      await db.customStatement(
        'INSERT INTO local_invoice_reopen_audit '
        '(operation_id,business_id,invoice_id,reason,reopened_at,expected_version,sync_state) '
        'VALUES(?,?,?,?,?,?,?)',
        [operation, business, id, note, now, version, state],
      );
      await db.customStatement(
        'INSERT INTO local_invoice_closures '
        '(business_id,invoice_id,closed_at,operation_id,payload,sync_state,reopened_at) '
        "VALUES(?,?,?,?,?,?,?) ON CONFLICT(business_id,invoice_id) DO UPDATE SET "
        'operation_id=excluded.operation_id,sync_state=excluded.sync_state,reopened_at=excluded.reopened_at',
        [business, id, saved['closed_at']?.toString() ?? now, operation, '{}', state, now],
      );
      await _clearClosedIndex(business, id);
    });
  }

  Future<void> _clearClosedIndex(String business, String id) async {
    await db.customStatement(
      "UPDATE local_documents SET status='issued',display_status_code=NULL,closed_at=NULL "
      "WHERE business_id=? AND id=? AND kind='invoice'",
      [business, id],
    );
  }

  static final _reopenFlushes = Expando<Set<String>>();

  Future<void> _flushReopens(String business) async {
    final active = _reopenFlushes[db] ??= <String>{};
    if (!active.add(business)) return;
    try {
      final rows = await db.customSelect(
        "SELECT a.* FROM local_invoice_reopen_audit a JOIN local_invoice_closures c "
        "ON a.operation_id=c.operation_id AND a.business_id=c.business_id AND a.invoice_id=c.invoice_id "
        "WHERE a.business_id=? AND a.sync_state='reopen_pending' AND c.sync_state='reopen_pending'",
        variables: [Variable(business)],
      ).get();
      for (final row in rows) {
        if (BriskersConnectionModeController.instance.forceOffline) return;
        final id = row.read<String>('invoice_id');
        final operation = row.read<String>('operation_id');
        final version = row.read<int>('expected_version');
        var state = 'reopen_review';
        try {
          final cached = await LocalDocumentDetailCache(database: db)
              .loadReadOnly(business, id, projectLifecycle: false);
          if (cached == null) continue;
          final current = await api.documentDetail(business, id);
          if (current['id'] != id || current['kind'] != 'invoice' ||
              int.tryParse(current['row_version']?.toString() ?? '') != version ||
              current['status'] == 'void' ||
              !DocumentPresentation(current).isClosed && current['legacy_read_only'] != true) {
            throw StateError('The server invoice has changed. Review the saved reopening.');
          }
          final stillCurrent = await db.customSelect(
            "SELECT 1 FROM local_invoice_closures WHERE business_id=? AND invoice_id=? "
            "AND operation_id=? AND sync_state='reopen_pending'",
            variables: [Variable(business), Variable(id), Variable(operation)],
          ).getSingleOrNull();
          if (stillCurrent == null) continue;
          if (BriskersConnectionModeController.instance.forceOffline) return;
          await api.ownerForceReopenInvoice(
            business, id, expectedVersion: version, reason: row.read<String>('reason'),
          );
          if (BriskersConnectionModeController.instance.forceOffline) return;
          final confirmed = await api.documentDetail(business, id);
          if (confirmed['id'] == id && confirmed['kind'] == 'invoice' &&
              !DocumentPresentation(confirmed).isClosed && confirmed['legacy_read_only'] == false &&
              (int.tryParse(confirmed['row_version']?.toString() ?? '') ?? 0) > version) {
            await LocalDocumentDetailCache(database: db).save(business, id, confirmed);
            state = 'reopened';
          }
        } catch (_) {
          if (BriskersConnectionModeController.instance.forceOffline) return;
          // A changed version, rejected unlock, or unknown response is held
          // for review. A retry must never replay a stale Owner authorization.
        }
        await db.transaction(() async {
          await db.customStatement(
            'UPDATE local_invoice_reopen_audit SET sync_state=? WHERE operation_id=?',
            [state, operation],
          );
          await db.customStatement(
            'UPDATE local_invoice_closures SET sync_state=? WHERE business_id=? AND invoice_id=? AND operation_id=?',
            [state, business, id, operation],
          );
        });
      }
    } finally {
      active.remove(business);
    }
  }

  /// An immutable close-only request is idempotent and cannot post receipts.
  /// Unposted receipts may delay server closure, but cannot undo local closure.
  Future<void> flush(String business) async {
    if (BriskersConnectionModeController.instance.forceOffline) return;
    await LocalInvoiceClosureStore(db).prepare();
    await _flushReopens(business);
    if (!_enableLegacyReplay) return;
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
        final review = isSyncVersionConflict(error) ||
            error is PostgrestException &&
                const {'42501', '55000', '22023', 'PGRST202'}.contains(error.code);
        await db.customStatement(
          'UPDATE local_invoice_closures SET sync_state=?,error=?,retry_after=? '
          'WHERE business_id=? AND invoice_id=? AND reopened_at IS NULL',
          [review ? 'review' : 'pending', error.toString(),
            DateTime.now().millisecondsSinceEpoch + 60000, business, id],
        );
      }
    }
  }
}
