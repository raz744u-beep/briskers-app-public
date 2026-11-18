import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_document_identity.dart';

/// One visible Job for an independently verified invoice creation identity.
/// Both physical Jobs and their work, payroll and attachments are retained.
class LocalJobIdentity {
  LocalJobIdentity(this.db);
  final BriskersLocalDatabase db;

  Future<void> prepare() async {
    await LocalDocumentIdentity(db).prepare();
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_job_identity_aliases (
      business_id TEXT NOT NULL, alias_id TEXT NOT NULL, canonical_id TEXT NOT NULL,
      alias_invoice_id TEXT NOT NULL, canonical_invoice_id TEXT NOT NULL,
      proof TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY(business_id,alias_id))''',
    );
    // A public Job/invoice number is only a consistency check. The registered
    // invoice alias proves the shared creation operation. Require the complete
    // Closed original and refuse to hide a Job owning another document.
    final inserted = await db.customUpdate(
      '''INSERT OR IGNORE INTO local_job_identity_aliases
      (business_id,alias_id,canonical_id,alias_invoice_id,canonical_invoice_id,proof)
      SELECT a.business_id,remote.job_id,original.job_id,a.alias_id,a.canonical_id,a.proof
      FROM local_document_identity_aliases a
      JOIN local_documents remote ON remote.business_id=a.business_id AND remote.id=a.alias_id
      JOIN local_documents original ON original.business_id=a.business_id AND original.id=a.canonical_id
      JOIN local_jobs r ON r.business_id=a.business_id AND r.id=remote.job_id
      JOIN local_jobs c ON c.business_id=a.business_id AND c.id=original.job_id
      WHERE remote.kind='invoice' AND original.kind='invoice'
        AND remote.job_id<>original.job_id
        AND original.status='closed' AND c.status IN ('closed','completed')
        AND r.job_number=c.job_number AND trim(COALESCE(c.job_number,''))<>''
        AND NOT EXISTS (SELECT 1 FROM local_documents other
          WHERE other.business_id=a.business_id AND other.job_id=r.id AND other.id<>remote.id)
        AND NOT EXISTS (SELECT 1 FROM local_document_detail_deleted x
          WHERE x.cache_key='briskers_document_detail_' || a.business_id || '_' || original.id)''',
    );
    if (inserted > 0) {
      db.notifyUpdates({
        const TableUpdate('local_jobs', kind: UpdateKind.update),
      });
    }
  }

  static String visibleSql(String job) => '''NOT EXISTS (
    SELECT 1 FROM local_job_identity_aliases a JOIN local_jobs original
      ON original.business_id=a.business_id AND original.id=a.canonical_id
    WHERE a.business_id=$job.business_id AND a.alias_id=$job.id)''';

  static String retainedSql(String business, String id) =>
      '''EXISTS (
    SELECT 1 FROM local_job_identity_aliases a WHERE a.business_id=$business
      AND (a.alias_id=$id OR a.canonical_id=$id))''';

  Future<String> canonicalId(String business, String id) async {
    await prepare();
    final row = await db
        .customSelect(
          '''SELECT a.canonical_id
      FROM local_job_identity_aliases a JOIN local_jobs original
        ON original.business_id=a.business_id AND original.id=a.canonical_id
      WHERE a.business_id=? AND a.alias_id=?''',
          variables: [Variable(business), Variable(id)],
        )
        .getSingleOrNull();
    return row?.read<String>('canonical_id') ?? id;
  }

  Future<Set<String>> retainedJobIds(String business) async {
    await prepare();
    final rows = await db
        .customSelect(
          '''SELECT alias_id,canonical_id
      FROM local_job_identity_aliases WHERE business_id=?''',
          variables: [Variable(business)],
        )
        .get();
    return {
      for (final row in rows) ...[
        row.read<String>('alias_id'),
        row.read<String>('canonical_id'),
      ],
    };
  }
}
