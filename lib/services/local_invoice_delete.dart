import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_document_identity.dart';
import 'local_document_detail_cache.dart';
import 'local_document_sql_store.dart';
import 'local_job_retirement.dart';
import 'local_owner_authorization.dart';

/// Exact-document visibility tombstone with immutable local audit evidence.
/// Job, lines, receipts and ledger rows remain available for audit/recovery.
class LocalInvoiceDelete {
  LocalInvoiceDelete(this.db);
  final BriskersLocalDatabase db;

  Future<void> remove({required String businessId, required String invoiceId,
      required LocalOwnerGrant ownerGrant}) async {
    ownerGrant.assertValid(businessId, ownerGrant.actorId);
    final canonical = await LocalDocumentIdentity(db).canonicalId(businessId, invoiceId);
    if (canonical != invoiceId) {
      throw StateError('This listing belongs to the original invoice. Refresh the invoice list.');
    }
    final key = LocalDocumentDetailCache.key(businessId, invoiceId);
    final detail = await LocalDocumentSqlStore.read(db, key);
    await db.customStatement('''CREATE TABLE IF NOT EXISTS local_invoice_delete_audit (
      business_id TEXT NOT NULL,invoice_id TEXT NOT NULL,actor_id TEXT NOT NULL,
      snapshot_json TEXT NOT NULL,deleted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY(business_id,invoice_id))''');
    await db.transaction(() async {
      ownerGrant.assertValid(businessId, ownerGrant.actorId);
      final row = await db.customSelect("SELECT * FROM local_documents WHERE business_id=? AND id=? AND kind='invoice'",
        variables:[Variable(businessId),Variable(invoiceId)]).getSingleOrNull();
      if(row == null) throw StateError('This invoice is not saved in the local index.');
      await db.customStatement('INSERT OR IGNORE INTO local_invoice_delete_audit '
        '(business_id,invoice_id,actor_id,snapshot_json) VALUES (?,?,?,?)',
        [businessId,invoiceId,ownerGrant.actorId,jsonEncode({'index':row.data,'detail':detail})]);
      await db.customStatement('INSERT OR IGNORE INTO local_document_detail_deleted(cache_key) VALUES (?)',[key]);
    });
    LocalJobRetirement.notify(db,businessId,const []);
  }
}
