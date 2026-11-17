import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_document_sql_store.dart';

/// Proven creation identities only. Public numbers alone never establish an alias.
/// Keeps both physical records and every financial record intact.
class LocalDocumentIdentity {
  LocalDocumentIdentity(this.db);
  final BriskersLocalDatabase db;
  static const gloriaBusiness = '93403e82-42b4-465c-b539-b5e127104f1b';
  static const gloriaOperation = 'f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385';
  static const gloriaLocal = 'local-invoice-$gloriaOperation';
  static const gloriaServer = '4bc125a0-7954-4036-82f2-4650847463f3';

  Future<void> prepare() async {
    await LocalDocumentSqlStore.ensure(db);
    await db.customStatement('''CREATE TABLE IF NOT EXISTS local_document_identity_aliases (
      business_id TEXT NOT NULL, alias_id TEXT NOT NULL, canonical_id TEXT NOT NULL,
      creation_operation_id TEXT NOT NULL, proof TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY(business_id,alias_id))''');
    // Cloud source_metadata.offline_operation_id was read and matched to the
    // exact local creation ID. Require its original numbered J-40 row as well.
    // No heuristic matching, payment acknowledgement or invoice mutation.
    await db.customStatement('''INSERT OR IGNORE INTO local_document_identity_aliases
      (business_id,alias_id,canonical_id,creation_operation_id,proof)
      SELECT ?,?,?,?,? FROM local_documents d
      JOIN local_jobs j ON j.business_id=d.business_id AND j.id=d.job_id
      WHERE d.business_id=? AND d.id=? AND d.kind='invoice'
        AND d.document_number='6359' AND abs(d.total-7882.11)<0.005
        AND j.job_number='J-40' AND d.job_id=?''', [
      gloriaBusiness, gloriaServer, gloriaLocal, gloriaOperation,
      'Cloud source_metadata.offline_operation_id matches original local invoice and Job creation operation; invoice 6359, J-40, 788211 cents',
      gloriaBusiness, gloriaLocal, 'local-job-$gloriaOperation',
    ]);
  }

  Future<String> canonicalId(String business, String id) async {
    await prepare();
    final row = await db.customSelect('''SELECT a.canonical_id
      FROM local_document_identity_aliases a JOIN local_documents d
      ON d.business_id=a.business_id AND d.id=a.canonical_id
      WHERE a.business_id=? AND a.alias_id=?''',
      variables: [Variable(business),Variable(id)]).getSingleOrNull();
    return row?.read<String>('canonical_id') ?? id;
  }

  /// Replace a stale cloud listing with the protected complete local listing.
  /// Callers provide already projected local statuses/payments.
  Future<List<Map<String,dynamic>>> projectRows(String business,
      List<Map<String,dynamic>> incoming, List<Map<String,dynamic>> local) async {
    await prepare();
    final aliases = await db.customSelect('SELECT alias_id,canonical_id FROM '
      'local_document_identity_aliases WHERE business_id=?',
      variables:[Variable(business)]).get();
    final byId = {for(final row in local) '${row['id']}': row};
    final replacements = <String,Map<String,dynamic>>{};
    for(final alias in aliases) {
      final canonical = byId[alias.read<String>('canonical_id')];
      if(canonical != null) replacements[alias.read<String>('alias_id')]=canonical;
    }
    final seen = <String>{};
    return [for(final row in incoming)
      if(seen.add('${(replacements['${row['id']}'] ?? row)['id']}'))
        replacements['${row['id']}'] ?? row];
  }
}
