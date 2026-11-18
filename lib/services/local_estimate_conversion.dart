import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_document_sql_store.dart';

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
            (value['business_id'] != null && value['business_id'] != business)) continue;
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
    final records = await db.customSelect(
      "SELECT d.id,d.kind,d.converted,d.document_number,d.document_date,c.payload_json "
      "FROM local_documents d LEFT JOIN local_document_details c "
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
      final raw = record.readNullable<String>('payload_json');
      if (raw == null) continue;
      try {
        final value = jsonDecode(raw);
        final id = record.read<String>('id');
        if (value is! Map || value['id'] != id || value['kind'] != record.data['kind'] ||
            (value['business_id'] != null && value['business_id'] != business)) continue;
        saved[id] = Map<String, dynamic>.from(value);
        if (value['kind'] == 'invoice' && value['converted_from_estimate_id'] is String) {
          reverse.putIfAbsent(value['converted_from_estimate_id'] as String, () => []).add(id);
        }
      } on FormatException {
        // Invalid snapshots never establish a link.
      }
    }
    for (final row in rows) {
      if (row['kind'] != 'estimate') continue;
      final id = row['id']?.toString() ?? '';
      final prior = _withLegacy(saved[id] ?? const <String, dynamic>{}, legacy[id]);
      final links = reverse[id] ?? const <String>[];
      var target = (row['converted_invoice_id'] ?? prior['converted_invoice_id'])?.toString() ?? '';
      if (target.isEmpty && links.length == 1) target = links.single;
      if (row['converted'] != true && prior['converted'] != true &&
          indexes[id]?['converted'] != 1 && target.isEmpty && links.isEmpty) continue;
      row['converted'] = true;
      row['display_status'] = 'Converted';
      if (target.isNotEmpty) {
        row['converted_invoice_id'] = target;
        row['converted_invoice_number'] = indexes[target]?['document_number'] ?? prior['converted_invoice_number'];
        row['converted_invoice_date'] = indexes[target]?['document_date'] ?? prior['converted_invoice_date'];
      }
    }
  }

  Future<Map<String, dynamic>> project(
    String business,
    Map<String, dynamic> detail, {
    Map<String, dynamic>? previous,
  }) async {
    if (detail['kind'] != 'estimate') return detail;
    final id = detail['id']?.toString() ?? '';
    if (id.isEmpty) return detail;
    await LocalDocumentSqlStore.ensure(db);
    final raw = await LocalDocumentSqlStore.read(
      db, 'briskers_document_detail_${business}_$id',
    );
    Map<String, dynamic> saved = previous ?? const {};
    if (previous == null && raw != null) {
      try {
        final value = jsonDecode(raw);
        if (value is Map && value['id'] == id &&
            value['kind'] == 'estimate' &&
            (value['business_id'] == null || value['business_id'] == business)) {
          saved = Map<String, dynamic>.from(value);
        }
      } on FormatException {
        // An unreadable cache cannot supply conversion evidence.
      }
    }
    final index = await db.customSelect(
      "SELECT converted FROM local_documents WHERE business_id=? AND id=? AND kind='estimate'",
      variables: [Variable(business), Variable(id)],
    ).getSingleOrNull();
    if (index != null) saved = _withLegacy(saved, (await _legacyConversions(business))[id]);
    var converted = detail['converted'] == true || saved['converted'] == true ||
        index?.data['converted'] == 1;
    var invoiceId = (detail['converted_invoice_id'] ??
        saved['converted_invoice_id'])?.toString() ?? '';
    // Reverse links survive a stale estimate cache/index. Require an exact
    // internal source ID in a saved invoice belonging to this business.
    if (invoiceId.isEmpty) {
      const snapshot = "CASE WHEN json_valid(c.payload_json) THEN c.payload_json ELSE '{}' END";
      final links = await db.customSelect(
        "SELECT d.id FROM local_documents d JOIN local_document_details c "
        "ON c.cache_key='briskers_document_detail_' || d.business_id || '_' || d.id "
        "WHERE d.business_id=? AND d.kind='invoice' AND json_valid(c.payload_json) "
        "AND json_extract($snapshot,'\$.id')=d.id "
        "AND json_extract($snapshot,'\$.kind')='invoice' "
        "AND (json_extract($snapshot,'\$.business_id') IS NULL OR json_extract($snapshot,'\$.business_id')=d.business_id) "
        "AND json_extract($snapshot,'\$.converted_from_estimate_id')=? "
        "AND NOT EXISTS(SELECT 1 FROM local_document_detail_deleted x WHERE x.cache_key=c.cache_key)",
        variables: [Variable(business), Variable(id)],
      ).get();
      if (links.length == 1) invoiceId = links.single.read<String>('id');
      if (links.isNotEmpty) converted = true;
    }
    if (invoiceId.isNotEmpty) converted = true;
    if (!converted) return detail;
    final invoice = invoiceId.isEmpty ? null : await db.customSelect(
      "SELECT document_number,document_date FROM local_documents "
      "WHERE business_id=? AND id=? AND kind='invoice'",
      variables: [Variable(business), Variable(invoiceId)],
    ).getSingleOrNull();
    return {
      ...detail,
      'converted': true,
      if (invoiceId.isNotEmpty) 'converted_invoice_id': invoiceId,
      'converted_invoice_number': invoice?.data['document_number'] ??
          detail['converted_invoice_number'] ?? saved['converted_invoice_number'],
      'converted_invoice_date': invoice?.data['document_date'] ??
          detail['converted_invoice_date'] ?? saved['converted_invoice_date'],
    };
  }
}
