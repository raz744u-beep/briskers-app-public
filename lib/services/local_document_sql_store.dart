import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local/briskers_local_database.dart';

/// Normal invoice details join SQLite's commit boundary. Original preference
/// recovery evidence is left untouched; durable deletion markers fence reads.
class LocalDocumentSqlStore {
  static Future<void> ensure(BriskersLocalDatabase db) async {
    await db.customStatement('CREATE TABLE IF NOT EXISTS local_document_details '
      '(cache_key TEXT PRIMARY KEY NOT NULL,payload_json TEXT)');
    await db.customStatement('CREATE TABLE IF NOT EXISTS local_document_detail_deleted '
      '(cache_key TEXT PRIMARY KEY NOT NULL)');
    await db.customStatement('CREATE TRIGGER IF NOT EXISTS local_detail_no_resurrection '
      'BEFORE INSERT ON local_document_details WHEN EXISTS '
      '(SELECT 1 FROM local_document_detail_deleted WHERE cache_key=NEW.cache_key) '
      "BEGIN SELECT RAISE(ABORT,'Document was deleted locally'); END");
  }
  static Future<bool> deleted(BriskersLocalDatabase db,String key) async {
    await ensure(db);
    return (await db.customSelect('SELECT 1 FROM local_document_detail_deleted WHERE cache_key=?',
      variables:[Variable<String>(key)]).get()).isNotEmpty;
  }
  static Future<String?> read(BriskersLocalDatabase db,String key) async {
    await ensure(db);
    if(await deleted(db,key)) return null;
    final rows=await db.customSelect('SELECT payload_json FROM local_document_details WHERE cache_key=?',
      variables:[Variable<String>(key)]).get();
    if(rows.isNotEmpty) return rows.single.readNullable<String>('payload_json');
    final legacy=(await SharedPreferences.getInstance()).getString(key);
    if(legacy!=null) await write(db,key,legacy);
    return legacy;
  }
  static Future<void> write(BriskersLocalDatabase db,String key,String? raw) async {
    await ensure(db);
    await db.customStatement('INSERT INTO local_document_details VALUES (?,?) '
      'ON CONFLICT(cache_key) DO UPDATE SET payload_json=excluded.payload_json',[key,raw]);
  }
}
