import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import 'local_document_sql_store.dart';

/// Number ownership survives an incomplete server index refresh. Read raw
/// snapshots without projecting tasks, changing payments, or repairing numbers.
class LocalNumberEvidence {
  static Future<List<Map<String, dynamic>>> documents(
    BriskersLocalDatabase db, String business,
  ) async {
    await LocalDocumentSqlStore.ensure(db);
    final prefix = 'briskers_document_detail_${business}_';
    final prefs = await SharedPreferences.getInstance();
    final raw = <String, String?>{
      for (final key in prefs.getKeys())
        if (key.startsWith(prefix)) key.substring(prefix.length): prefs.getString(key),
    };
    final durable = await db.customSelect(
      'SELECT cache_key,payload_json FROM local_document_details '
      'WHERE substr(cache_key,1,?)=?',
      variables: [Variable(prefix.length), Variable(prefix)],
    ).get();
    for (final row in durable) {
      raw[row.read<String>('cache_key').substring(prefix.length)] =
          row.readNullable<String>('payload_json');
    }
    final tables = (await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
      "('recovery_document_cache','local_job_retirement_entities')",
    ).get()).map((r) => r.read<String>('name')).toSet();
    if (tables.contains('recovery_document_cache')) {
      final recovery = await db.customSelect(
        'SELECT document_id,payload_json FROM recovery_document_cache WHERE business_id=?',
        variables: [Variable(business)],
      ).get();
      for (final row in recovery) {
        raw[row.read<String>('document_id')] = row.readNullable<String>('payload_json');
      }
    }
    final deleted = (await db.customSelect(
      'SELECT cache_key FROM local_document_detail_deleted WHERE substr(cache_key,1,?)=?',
      variables: [Variable(prefix.length), Variable(prefix)],
    ).get()).map((r) => r.read<String>('cache_key').substring(prefix.length)).toSet();
    final retiredInvoices = <String>{};
    final retiredJobs = <String>{};
    final indexedIds = (await db.customSelect(
      'SELECT id FROM local_documents WHERE business_id=?',
      variables: [Variable(business)],
    ).get()).map((r) => r.read<String>('id')).toSet();
    if (tables.contains('local_job_retirement_entities')) {
      final retired = await db.customSelect(
        'SELECT entity_kind,entity_id FROM local_job_retirement_entities '
        "WHERE business_id=? AND state IN ('pending','accepted','locally_cancelled')",
        variables: [Variable(business)],
      ).get();
      for (final row in retired) {
        if (row.read<String>('entity_kind') == 'invoice') {
          retiredInvoices.add(row.read<String>('entity_id'));
        } else if (row.read<String>('entity_kind') == 'job') {
          retiredJobs.add(row.read<String>('entity_id'));
        }
      }
    }
    final result = <Map<String, dynamic>>[];
    for (final entry in raw.entries) {
      if (deleted.contains(entry.key) || entry.value == null) continue;
      Object? decoded;
      try { decoded = jsonDecode(entry.value!); } on FormatException { continue; }
      if (decoded is! Map) continue;
      final detail = Map<String, dynamic>.from(decoded);
      final serverId = detail['_server_document_id']?.toString() ?? '';
      final id = indexedIds.contains(entry.key) || serverId.isEmpty
          ? entry.key : serverId;
      if (deleted.contains(id)) continue;
      if (detail['kind'] == 'invoice' &&
          (retiredInvoices.contains(entry.key) || retiredInvoices.contains(id) ||
           retiredJobs.contains(detail['job_id']?.toString()))) continue;
      result.add({...detail, 'id': id});
    }
    return result;
  }
}
