import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_document_sql_store.dart';
import 'recovery_commit_store.dart';

/// Projects explicit saved conversion evidence. Customer, amount and public
/// number matches alone never establish an estimate/invoice relationship.
class LocalEstimateConversion {
  const LocalEstimateConversion(this.db);
  final BriskersLocalDatabase db;

  Future<Map<String, Map<String, dynamic>>> _legacyConversions(String business) async {
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
        final target = value['_server_document_id']?.toString() ?? '';
        final invoice = value['converted_invoice_id']?.toString() ?? '';
        if (target.isEmpty || (value['converted'] != true && invoice.isEmpty)) continue;
        final fullPrefix = 'briskers_document_detail_${business}_';
        final localId = row.read<String>('cache_key').substring(fullPrefix.length);
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
    final records = await db.customSelect(
      "SELECT d.id,d.kind,d.converted,d.document_number,d.document_date,"
      "CASE WHEN d.kind='estimate' THEN c.payload_json END AS payload_json,"
      "CASE WHEN d.kind='invoice' AND json_valid(c.payload_json) THEN "
      "CASE WHEN json_extract(c.payload_json,'\$.id')=d.id "
      "AND json_extract(c.payload_json,'\$.kind')='invoice' "
      "AND (json_extract(c.payload_json,'\$.business_id') IS NULL OR json_extract(c.payload_json,'\$.business_id')=d.business_id) "
      "THEN COALESCE(NULLIF(json_extract(c.payload_json,'\$.converted_from_estimate_id'),''), "
      "NULLIF(json_extract(c.payload_json,'\$.source_estimate_id'),'')) END END AS source_estimate_id "
      "FROM local_documents d LEFT JOIN ("
      "SELECT cache_key,payload_json FROM local_document_details "
      "UNION ALL SELECT 'briskers_document_detail_' || business_id || '_' || document_id,payload_json "
      "FROM recovery_document_cache) c "
      "ON c.cache_key='briskers_document_detail_' || d.business_id || '_' || d.id "
      "WHERE d.business_id=? AND NOT EXISTS(SELECT 1 FROM local_document_detail_deleted x "
      "WHERE x.cache_key='briskers_document_detail_' || d.business_id || '_' || d.id)",
      variables: [Variable(business)],
    ).get();
    final indexes = {for (final record in records) record.read<String>('id'): record.data};
    final legacy = await _legacyConversions(business);
    final saved = <String, Map<String, dynamic>>{};
    final reverse = <String, List<String>>{};
    for (final record in records) {
      final source = record.data['source_estimate_id'];
      if (source is String && source.isNotEmpty) {
        reverse.putIfAbsent(source, () => []).add(record.read<String>('id'));
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
      reverse.putIfAbsent(receipt.read<String>('estimate_id'), () => [])
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
