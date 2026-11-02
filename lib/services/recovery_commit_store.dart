import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';

/// SQLite is the single commit boundary for recovery, including its snapshot.
/// Preference snapshots are retained unchanged as original recovery evidence.
class RecoveryCommitStore {
  static Future<void> ensure(BriskersLocalDatabase db) async {
    await db.customStatement('''CREATE TABLE IF NOT EXISTS recovery_commits (
      business_id TEXT NOT NULL, local_invoice_id TEXT NOT NULL,
      server_invoice_id TEXT NOT NULL, identities_json TEXT NOT NULL,
      original_json TEXT NOT NULL, proof_json TEXT NOT NULL,
      committed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY(business_id,local_invoice_id),
      UNIQUE(business_id,server_invoice_id))''');
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS recovery_document_cache (
      business_id TEXT NOT NULL, document_id TEXT NOT NULL,
      payload_json TEXT, PRIMARY KEY(business_id,document_id))''',
    );
    await db.customStatement(
      '''CREATE TRIGGER IF NOT EXISTS recovery_no_requeue
      BEFORE UPDATE OF state ON sync_outbox
      WHEN OLD.state='reconciled' AND NEW.state<>'reconciled'
      BEGIN SELECT RAISE(ABORT,'Reconciled operations cannot be replayed'); END''',
    );
  }

  static Future<bool> isOriginal(
    BriskersLocalDatabase db,
    String b,
    String id,
  ) async {
    await ensure(db);
    return (await db
            .customSelect(
              'SELECT 1 FROM recovery_commits WHERE business_id=? AND local_invoice_id=?',
              variables: [Variable<String>(b), Variable<String>(id)],
            )
            .get())
        .isNotEmpty;
  }

  static Future<QueryRow?> snapshot(
    BriskersLocalDatabase db,
    String b,
    String id,
  ) async {
    await ensure(db);
    return db
        .customSelect(
          'SELECT payload_json FROM recovery_document_cache WHERE business_id=? AND document_id=?',
          variables: [Variable<String>(b), Variable<String>(id)],
        )
        .getSingleOrNull();
  }
}
