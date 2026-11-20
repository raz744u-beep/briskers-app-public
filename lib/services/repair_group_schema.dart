import '../local/briskers_local_database.dart';

/// Additive local schema. No existing document, task or payment is rewritten.
class RepairGroupSchema {
  static Future<void> ensure(BriskersLocalDatabase db) async {
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_group_documents_v1(
      business TEXT NOT NULL, estimate TEXT NOT NULL,
      PRIMARY KEY(business,estimate))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_group_invoice_content_v1(
      business TEXT NOT NULL, document TEXT NOT NULL, content_json TEXT NOT NULL,
      PRIMARY KEY(business,document))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_groups_v1(
      business TEXT NOT NULL, estimate TEXT NOT NULL, id TEXT NOT NULL,
      name TEXT NOT NULL, description TEXT NOT NULL, position INTEGER NOT NULL,
      evidence_json TEXT NOT NULL,
      PRIMARY KEY(business,estimate,id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_group_members_v1(
      business TEXT NOT NULL, estimate TEXT NOT NULL, line TEXT NOT NULL,
      group_id TEXT NOT NULL,
      PRIMARY KEY(business,estimate,line))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_authorizations_v1(
      business TEXT NOT NULL, estimate TEXT NOT NULL, event_id TEXT NOT NULL,
      revision TEXT NOT NULL, payload_json TEXT NOT NULL,
      PRIMARY KEY(business,event_id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_group_scope_v1(
      business TEXT NOT NULL, estimate TEXT NOT NULL, group_id TEXT NOT NULL,
      fingerprint TEXT NOT NULL, generation INTEGER NOT NULL,
      PRIMARY KEY(business,estimate,group_id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_signatures_v1(
      business TEXT NOT NULL, signature_id TEXT NOT NULL, image_bytes BLOB NOT NULL,
      PRIMARY KEY(business,signature_id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_authorization_media_v1(
      business TEXT NOT NULL, media_id TEXT NOT NULL, image_bytes BLOB NOT NULL,
      PRIMARY KEY(business,media_id))''');
    await db.customStatement('''CREATE INDEX IF NOT EXISTS repair_authorizations_estimate_v1
      ON repair_authorizations_v1(business,estimate)''');
    for (final table in ['repair_authorizations_v1', 'repair_signatures_v1', 'repair_authorization_media_v1']) {
      for (final operation in ['UPDATE', 'DELETE']) {
        await db.customStatement('''CREATE TRIGGER IF NOT EXISTS ${table}_no_${operation.toLowerCase()}
        BEFORE $operation ON $table
        BEGIN SELECT RAISE(ABORT,'Repair authorization history is immutable'); END''');
      }
    }
  }
}
