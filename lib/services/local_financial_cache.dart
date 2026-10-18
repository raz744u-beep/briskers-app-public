import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_deletion_v3.dart';

class LocalFinancialCache {
  LocalFinancialCache({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  static const _transactionsKey = 'transactions_snapshot';
  static const _optionsKey = 'transaction_options';
  static const _invoiceReceiptsKey = 'invoice_receipts_v1';

  // Preserve the current receipt-aware payments/invoices screen while applying
  // the same authenticated visibility/tombstone protections as other caches.
  Future<void> saveInvoiceReceipts(String businessId,
      List<Map<String, dynamic>> rows, {int? visibilityGeneration}) =>
      _save(businessId, _invoiceReceiptsKey, rows,
          visibilityGeneration: visibilityGeneration);

  Future<bool> hasServerInvoiceReceipts(String businessId) async =>
      await _load(businessId, _invoiceReceiptsKey) != null;

  Future<List<Map<String, dynamic>>> loadInvoiceReceipts(String businessId) async {
    final raw = await _load(businessId, _invoiceReceiptsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      return const [];
    }
  }

  final BriskersLocalDatabase _database;

  Future<void> saveTransactions(
    String businessId,
    List<Map<String, dynamic>> rows, {
    int? visibilityGeneration,
  }) async {
    await _save(
      businessId,
      _transactionsKey,
      rows,
      visibilityGeneration: visibilityGeneration,
    );
  }

  Future<List<Map<String, dynamic>>> loadTransactions(
    String businessId, {
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    String? direction,
    String? accountId,
    String? categoryId,
    String? counterpartyId,
  }) async {
    final raw = await _load(businessId, _transactionsKey);
    if (raw == null || raw.isEmpty) { return const []; }

    List<Map<String, dynamic>> rows;
    try {
      rows = List<dynamic>.from(jsonDecode(raw) as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return const [];
    }

    final needle = search?.trim().toLowerCase() ?? '';
    bool matches(Map<String, dynamic> row) {
      if (direction != null &&
          row['direction']?.toString() != direction) {
        return false;
      }
      if (accountId != null &&
          row['account_id']?.toString() != accountId) {
        return false;
      }
      if (categoryId != null &&
          row['category_id']?.toString() != categoryId) {
        return false;
      }
      if (counterpartyId != null &&
          row['counterparty_id']?.toString() != counterpartyId) {
        return false;
      }

      final date = DateTime.tryParse(
        row['transaction_date']?.toString() ?? '',
      );
      if (date != null) {
        final day = DateTime(date.year, date.month, date.day);
        if (startDate != null && day.isBefore(startDate)) { return false; }
        if (endDate != null && day.isAfter(endDate)) { return false; }
      }

      if (needle.isNotEmpty) {
        final haystack = <Object?>[
          row['counterparty'],
          row['category'],
          row['account'],
          row['remarks'],
          row['job_number'],
          row['job_title'],
          row['job_customer_name'],
          row['document_number'],
          row['amount'],
          row['transaction_date'],
        ].whereType<Object>().map((v) => v.toString().toLowerCase()).join(' ');
        if (!haystack.contains(needle)) { return false; }
      }

      return true;
    }

    return rows.where(matches).toList();
  }

  static const _linkedExpensesKey = 'linked_expenses_complete_v1';

  Future<void> saveLinkedExpenses(
    String businessId,
    List<Map<String, dynamic>> rows, {
    int? visibilityGeneration,
  }) async {
    await _save(businessId, _linkedExpensesKey, rows, visibilityGeneration: visibilityGeneration);
  }

  Future<List<Map<String, dynamic>>?> loadLinkedExpenses(
    String businessId, {
    String? jobId,
    String? documentId,
  }) async {
    final raw = await _load(businessId, _linkedExpensesKey);
    List<Map<String, dynamic>> rows;
    if (raw == null) {
      rows = <Map<String, dynamic>>[];
    } else {
      try {
        rows = (jsonDecode(raw) as List<dynamic>)
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
      } catch (_) {
        return null;
      }
    }

    // Preserve newly created offline expenses alongside the last full
    // server snapshot. Do not replace pending outbox records during sync.
    final pending = await loadTransactions(businessId, direction: 'expense');
    rows.addAll(pending.where((row) =>
        row['sync_state']?.toString() == 'pending' &&
        (row['id']?.toString().startsWith('local-') ?? false) &&
        (row['job_id'] != null || row['document_id'] != null)));

    if (raw == null && rows.isEmpty) { return null; }
    return rows.where((row) =>
        (jobId == null || row['job_id']?.toString() == jobId) &&
        (documentId == null ||
            row['document_id']?.toString() == documentId)).toList();
  }

  Future<void> saveTransactionDetail(
    String businessId,
    String transactionId,
    Map<String, dynamic> detail, {
    int? visibilityGeneration,
  }) async {
    await _save(
      businessId,
      'transaction_detail_$transactionId',
      detail,
      visibilityGeneration: visibilityGeneration,
    );
  }

  Future<Map<String, dynamic>?> loadTransactionDetail(
    String businessId,
    String transactionId,
  ) async {
    final raw = await _load(
      businessId,
      'transaction_detail_$transactionId',
    );
    if (raw == null || raw.isEmpty) { return null; }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOptions(
    String businessId,
    Map<String, dynamic> options, {
    int? visibilityGeneration,
  }) async {
    await _save(businessId, _optionsKey, options, visibilityGeneration: visibilityGeneration);
  }

  Future<Map<String, dynamic>> loadOptions(String businessId) async {
    final raw = await _load(businessId, _optionsKey);
    if (raw == null || raw.isEmpty) { return const {}; }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _save(
    String businessId,
    String key,
    Object value, {
    int? visibilityGeneration,
  }) => _database.transaction(() async {
    await LocalJobDeletionV3.ensureSchema(_database);
    final scopeKey = 'financial:$key';
    final generation = await LocalJobDeletionV3.validateVisibilityCacheWrite(
        _database, businessId, scopeKey, value, visibilityGeneration: visibilityGeneration);
    if (generation == null) {
          if (visibilityGeneration != null) { throw StateError('Cache scope changed or retained work requires reconciliation'); }
          return;
        }
    final decoded = LocalJobDeletionV3.stripVisibilityMetadata(value);
    final ids = {...await LocalJobDeletionV3.blockedIds(_database, businessId, includeVisibilityScope: false),
      ...await LocalJobDeletionV3.scopeDirtyIds(_database, businessId)};
    String payload;
    if (decoded is List) {
      payload = jsonEncode(decoded.where((row) => !LocalJobDeletionV3.referencesAny(row, ids)).toList());
    } else if (LocalJobDeletionV3.referencesAny(decoded, ids)) {
      return;
    } else { payload = jsonEncode(decoded); }
    if (key.startsWith('transaction_detail_') &&
        ids.contains(key.substring('transaction_detail_'.length))) { return; }
    await _database.customStatement(
      '''INSERT INTO local_financial_cache (
        business_id, cache_key, payload_json, updated_at
      ) VALUES (?, ?, ?, ?)
      ON CONFLICT(business_id, cache_key) DO UPDATE SET
        payload_json=excluded.payload_json,
        updated_at=excluded.updated_at''',
      [businessId, key, payload, DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000],
    );
    await LocalJobDeletionV3.markVisibilityCacheWritten(_database, businessId, scopeKey, generation);
  });

  Future<String?> _load(String businessId, String key) => _database.transaction(() async {
    final generation = await LocalJobDeletionV3.captureVisibilityGeneration(_database, businessId);
    if (!await LocalJobDeletionV3.visibilityCacheReadable(_database, businessId, 'financial:$key')) { return null; }
    final rows = await _database.customSelect(
      '''
      SELECT payload_json
      FROM local_financial_cache
      WHERE business_id = ? AND cache_key = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(key),
      ],
    ).get();
    if (rows.isEmpty) { return null; }
    final raw = rows.first.read<String>('payload_json');
    final ids = {...await LocalJobDeletionV3.blockedIds(_database, businessId, includeVisibilityScope: false),
      ...await LocalJobDeletionV3.scopeDirtyIds(_database, businessId)};
    if (key.startsWith('transaction_detail_') &&
        ids.contains(key.substring('transaction_detail_'.length))) { return null; }
    await LocalJobDeletionV3.assertVisibilityGeneration(_database, businessId, generation);
    try {
      final decoded = jsonDecode(raw);
      Object? stamp(Object? item) => generation > 0 && item is Map
          ? {...item, '_local_visibility_generation': generation} : item;
      if (decoded is List) {
        return jsonEncode(decoded.where((row) => !LocalJobDeletionV3.referencesAny(row, ids)).map(stamp).toList());
      }
      return LocalJobDeletionV3.referencesAny(decoded, ids) ? null : jsonEncode(stamp(decoded));
    } catch (_) { return null; }
  });
}

