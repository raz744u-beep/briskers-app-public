import '../local/briskers_local_database.dart';

/// Additive local schema. No existing document, task or payment is rewritten.
class RepairGroupSchema {
  static Future<void> ensure(BriskersLocalDatabase db) async {
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_groups_v1(
      business TEXT NOT NULL, estimate TEXT NOT NULL, id TEXT NOT NULL,
      name TEXT NOT NULL, description TEXT NOT NULL, position INTEGER NOT NULL,
      evidence_json TEXT NOT NULL,
      PRIMARY KEY(business,estimate,id))''');
    await db.customStatement('''CREATE TABLE IF NOT EXISTS repair_group_members_v1(
      business TEXT NOT NULL, estimate TEXT NOT NULL, line TEXT NOT NULL,
      group_id TEXT NOT NULL,
      PRIMARY KEY(business,estimate,line))''');
  }
}
