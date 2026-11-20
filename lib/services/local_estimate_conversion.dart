import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_document_sql_store.dart';
import 'local_estimate_number.dart';
import 'recovery_commit_store.dart';

/// Projects explicit saved conversion evidence. Customer, amount and public
/// number matches alone never establish an estimate/invoice relationship.
class LocalEstimateConversion {
  const LocalEstimateConversion(this.db);
  final BriskersLocalDatabase db;

  Future<Map<String, Map<String, dynamic>>> _legacyConversions(String business, Set<String> estimates) async {
    final prefix = 'briskers_document_detail_${business}_local-estimate-';
    final rows = await db.customSelect(
      'SELECT c.cache_key,c.payload_json FROM local_document_details c '
      'WHERE substr(c.cache_key,1,?)=? AND NOT EXISTS('
      'SELECT 1 FROM local_document_detail_deleted x WHERE x.cache_key=c.cache_key)',
      variables: [Variable(prefix.length), Variable(prefix)],
    ).get();
    final result = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      try {
        final value = jsonDecode(row.readNullable<String>('payload_json') ?? 'null');
        if (value is! Map || value['kind'] != 'estimate' ||
            (value['business_id'] != null && value['business_id'] != business)) {
          continue;
        }
        final localId = row.read<String>('cache_key').substring('briskers_document_detail_${business}_'.length);
        final derived = LocalEstimateNumber.identity(business, localId);
        final target = value['_server_document_id']?.toString() ??
            (estimates.contains(derived) ? derived : '');
        final invoice = value['converted_invoice_id']?.toString() ?? '';
        if (target.isEmpty || (value['converted'] != true && invoice.isEmpty)) continue;
        if (value['id'] != target && value['id'] != localId) continue;
        final prior = result[target];
        if (prior?['_ambiguous_conversion'] == true ||
            (prior != null && prior['converted_invoice_id'] != value['converted_invoice_id'])) {
          result[target] = {'converted': true, '_ambiguous_conversion': true};
        } else {
          result[target] = {...Map<String, dynamic>.from(value), 'converted': true};
        }
      } on FormatException {
        // An unreadable former cache key cannot supply identity evidence.
      }
    }
    return result;
  }

  Map<String, dynamic> _withLegacy(Map<String, dynamic> saved, Map<String, dynamic>? legacy) {
    if (legacy == null) return saved;
    return {
      ...legacy, ...saved,
      'converted': saved['converted'] == true || legacy['converted'] == true,
      'converted_invoice_id': (saved['converted_invoice_id']?.toString().isNotEmpty ?? false)
          ? saved['converted_invoice_id'] : legacy['converted_invoice_id'],
    };
  }

  Future<void> projectRows(String business, List<Map<String, dynamic>> rows) async {
    await LocalDocumentSqlStore.ensure(db);
    await RecoveryCommitStore.ensure(db);
    // Join each cache through its primary key. UNIONing complete JSON caches
    // first materialized every snapshot, including unrelated shops, on every visit.
    final records = await db.customSelect(
      "WITH scoped AS (SELECT * FROM local_documents d WHERE d.business_id=? "
      "AND NOT EXISTS(SELECT 1 FROM local_document_detail_deleted x WHERE "
      "x.cache_key='briskers_document_detail_' || d.business_id || '_' || d.id)), "
      "snapshots AS (SELECT scoped.*, 'briskers_document_detail_' || business_id || '_' || id AS snapshot_key, 0 AS snapshot_source FROM scoped "
      "UNION ALL SELECT scoped.*, NULL, 1 FROM scoped) "
      "SELECT d.id,d.kind,d.converted,d.document_number,d.document_date,"
      "CASE WHEN d.kind='estimate' AND d.id IN (SELECT value FROM json_each(?)) THEN c.payload_json END AS payload_json,"
      "CASE WHEN d.kind='invoice' AND json_valid(c.payload_json) THEN "
      "CASE WHEN json_extract(c.payload_json,'\$.id')=d.id "
      "AND json_extract(c.payload_json,'\$.kind')='invoice' "
      "AND (json_extract(c.payload_json,'\$.business_id') IS NULL OR json_extract(c.payload_json,'\$.business_id')=d.business_id) "
      "THEN COALESCE(NULLIF(json_extract(c.payload_json,'\$.converted_from_estimate_id'),''), "
      "NULLIF(json_extract(c.payload_json,'\$.source_estimate_id'),'')) END END AS source_estimate_id "
      "FROM snapshots d "
      "LEFT JOIN local_document_details c ON c.cache_key=d.snapshot_key "
      "WHERE d.snapshot_source=0 "
      "UNION ALL "
      "SELECT d.id,d.kind,d.converted,d.document_number,d.document_date,"
      "CASE WHEN d.kind='estimate' AND d.id IN (SELECT value FROM json_each(?)) THEN c.payload_json END,"
      "CASE WHEN d.kind='invoice' AND json_valid(c.payload_json) THEN "
      "CASE WHEN json_extract(c.payload_json,'\$.id')=d.id "
      "AND json_extract(c.payload_json,'\$.kind')='invoice' "
      "AND (json_extract(c.payload_json,'\$.business_id') IS NULL OR json_extract(c.payload_json,'\$.business_id')=d.business_id) "
      "THEN COALESCE(NULLIF(json_extract(c.payload_json,'\$.converted_from_estimate_id'),''), "
      "NULLIF(json_extract(c.payload_json,'\$.source_estimate_id'),'')) END END "
      "FROM snapshots d JOIN recovery_document_cache c "
      "ON c.business_id=d.business_id AND c.document_id=d.id WHERE d.snapshot_source=1",
      variables: [Variable(business),
        Variable(jsonEncode([for(final row in rows) row['id']?.toString()])),
        Variable(jsonEncode([for(final row in rows) row['id']?.toString()]))],
    ).get();
    final indexes = {for (final record in records) record.read<String>('id'): record.data};
    final estimateIds = {for (final record in records)
      if (record.data['kind'] == 'estimate') record.read<String>('id')};
    String estimateIdentity(String id) {
      if (!id.startsWith('local-estimate-')) return id;
      final canonical = LocalEstimateNumber.identity(business, id);
      return estimateIds.contains(canonical) ? canonical : id;
    }
    final legacy = await _legacyConversions(business, estimateIds);
    final saved = <String, Map<String, dynamic>>{};
    final reverse = <String, List<String>>{};
    for (final record in records) {
      final source = record.data['source_estimate_id'];
      if (source is String && source.isNotEmpty) {
        reverse.putIfAbsent(estimateIdentity(source), () => []).add(record.read<String>('id'));
      }
      final raw = record.readNullable<String>('payload_json');
      if (raw == null) continue;
      try {
        final value = jsonDecode(raw);
        final id = record.read<String>('id');
        if (value is! Map || value['id'] != id || value['kind'] != record.data['kind'] ||
            (value['business_id'] != null && value['business_id'] != business)) {
          continue;
        }
        saved[id] = _withLegacy(Map<String, dynamic>.from(value), saved[id]);
      } on FormatException {
        // Invalid snapshots never establish a link.
      }
    }
    final receipts = await db.customSelect(
      'SELECT estimate_id,invoice_id FROM local_estimate_conversion_evidence WHERE business_id=? '
      'AND NOT EXISTS(SELECT 1 FROM local_document_detail_deleted x WHERE '
      "x.cache_key='briskers_document_detail_' || ? || '_' || invoice_id)",
      variables:[Variable(business),Variable(business)],
    ).get();
    for (final receipt in receipts) {
      reverse.putIfAbsent(estimateIdentity(receipt.read<String>('estimate_id')), () => [])
          .add(receipt.read<String>('invoice_id'));
    }
    for (final row in rows) {
      if (row['kind'] != 'estimate') continue;
      final id = row['id']?.toString() ?? '';
      final prior = _withLegacy(saved[id] ?? const <String, dynamic>{}, legacy[id]);
      final links = (reverse[id] ?? const <String>[]).toSet().toList();
      var target = (row['converted_invoice_id'] ?? prior['converted_invoice_id'])?.toString() ?? '';
      if (target.isEmpty && links.length == 1) target = links.single;
      if (row['converted'] != true && prior['converted'] != true &&
          indexes[id]?['converted'] != 1 && target.isEmpty && links.isEmpty) {
        continue;
      }
      row['converted'] = true;
      row['display_status'] = 'Converted';
      if (target.isNotEmpty) {
        row['converted_invoice_id'] = target;
        row['converted_invoice_number'] = indexes[target]?['document_number'] ?? row['converted_invoice_number'] ?? prior['converted_invoice_number'];
        row['converted_invoice_date'] = indexes[target]?['document_date'] ?? row['converted_invoice_date'] ?? prior['converted_invoice_date'];
      }
    }
  }

  Future<void> recordAcknowledged(String business, String estimate, String invoice) async {
    if (business.isEmpty || estimate.isEmpty || invoice.isEmpty) {
      throw ArgumentError('An acknowledged conversion requires exact identities.');
    }
    await LocalDocumentSqlStore.ensure(db);
    await db.customStatement('INSERT OR IGNORE INTO local_estimate_conversion_evidence VALUES(?,?,?)',
      [business,estimate,invoice]);
  }

  Future<Map<String, dynamic>> project(
    String business, Map<String, dynamic> detail, {
    Map<String, dynamic>? previous,
  }) async {
    if (detail['kind'] != 'estimate' || (detail['id']?.toString() ?? '').isEmpty) return detail;
    final row = _withLegacy({...detail}, previous);
    await projectRows(business, [row]);
    return row;
  }
}
