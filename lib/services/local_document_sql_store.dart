import 'dart:convert';
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
    await db.customStatement('CREATE TABLE IF NOT EXISTS local_estimate_conversion_evidence '
      '(business_id TEXT NOT NULL,estimate_id TEXT NOT NULL,invoice_id TEXT NOT NULL, '
      'PRIMARY KEY(business_id,estimate_id,invoice_id))');
    await db.customStatement('CREATE TRIGGER IF NOT EXISTS local_detail_no_resurrection '
      'BEFORE INSERT ON local_document_details WHEN EXISTS '
      '(SELECT 1 FROM local_document_detail_deleted WHERE cache_key=NEW.cache_key) '
      "BEGIN SELECT RAISE(ABORT,'Document was deleted locally'); END");
  }
  /// Upgrade-era conversion proof may still live only in preferences. Copy
  /// explicit, scope-checked evidence once at startup so reverse-link queries
  /// do not depend on opening the target invoice first. Never overwrite SQL.
  static Future<void> importLegacyConversionEvidence(BriskersLocalDatabase db) async {
    await ensure(db);
    final prefs=await SharedPreferences.getInstance();
    final businesses=(await db.customSelect('SELECT DISTINCT business_id FROM local_documents').get())
        .map((r)=>r.read<String>('business_id')).toSet();
    final occupied=(await db.customSelect('SELECT cache_key FROM local_document_details '
      'UNION SELECT cache_key FROM local_document_detail_deleted').get())
        .map((r)=>r.read<String>('cache_key')).toSet();
    final imports=<String,String>{};
    for(final business in businesses){
      final prefix='briskers_document_detail_${business}_';
      for(final key in prefs.getKeys().where((key)=>key.startsWith(prefix))){
        final raw=prefs.get(key);
        if(raw is! String)continue;
        try{
          final value=jsonDecode(raw);
          if(value is! Map || (value['business_id']!=null && value['business_id']!=business))continue;
          final id=key.substring(prefix.length);
          final validAlias=id.startsWith('local-estimate-') &&
              value['_server_document_id']!=null && value['id']==value['_server_document_id'];
          if(value['id']!=id && !validAlias){continue;}
          final kind=value['kind'];
          final evidence=kind=='invoice'
              ? ((value['converted_from_estimate_id'] ?? value['source_estimate_id'])?.toString().isNotEmpty ?? false)
              : kind=='estimate' && (value['converted']==true ||
                (value['converted_invoice_id']?.toString().isNotEmpty ?? false));
          if(evidence) {
            if (!occupied.contains(key)) imports[key]=raw;
            final invoice = kind=='invoice' ? value['id']?.toString() ?? '' :
                value['converted_invoice_id']?.toString() ?? '';
            final estimate = kind=='invoice' ?
                (value['converted_from_estimate_id'] ?? value['source_estimate_id'])?.toString() ?? '' :
                (value['_server_document_id'] ?? value['id'])?.toString() ?? '';
            if (invoice.isEmpty || estimate.isEmpty) continue;
            if (await deleted(db,key)) continue;
            // A current explicit backlink beats contradictory legacy proof.
            final current=(await db.customSelect('SELECT payload_json FROM local_document_details WHERE cache_key=?',
                variables:[Variable(key)]).getSingleOrNull())?.readNullable<String>('payload_json');
            if (current!=null) {
              final latest=jsonDecode(current);
              if (latest is! Map || latest['id']!=value['id'] || latest['kind']!=kind ||
                  (latest['business_id']!=null && latest['business_id']!=business)) { continue; }
              final known=kind=='invoice' ? latest['converted_from_estimate_id'] ?? latest['source_estimate_id'] :
                  latest['converted_invoice_id'];
              if (known!=null && known.toString().isNotEmpty && known!=(kind=='invoice' ? estimate : invoice)) continue;
            }
            await db.customStatement('INSERT OR IGNORE INTO local_estimate_conversion_evidence VALUES(?,?,?)',
                [business,estimate,invoice]);
          }
        }on FormatException{
          // Leave unreadable legacy evidence untouched for review.
        }
      }
    }
    if(imports.isEmpty)return;
    await db.transaction(()async{
      for(final entry in imports.entries){
        await db.customStatement('INSERT INTO local_document_details(cache_key,payload_json) '
          'SELECT ?,? WHERE NOT EXISTS(SELECT 1 FROM local_document_detail_deleted WHERE cache_key=?) '
          'ON CONFLICT(cache_key) DO NOTHING',[entry.key,entry.value,entry.key]);
      }
    });
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
