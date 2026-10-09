import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

class LocalFinancialCache {
  LocalFinancialCache({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  static const _transactionsKey = 'transactions_snapshot';
  static const _optionsKey = 'transaction_options';

  final BriskersLocalDatabase _database;

  Future<void> saveTransactions(
    String businessId,
    List<Map<String, dynamic>> rows,
  ) async {
    await _save(
      businessId,
      _transactionsKey,
      jsonEncode(rows),
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
    if (raw == null || raw.isEmpty) return const [];

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
        if (startDate != null && day.isBefore(startDate)) return false;
        if (endDate != null && day.isAfter(endDate)) return false;
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
        if (!haystack.contains(needle)) return false;
      }

      return true;
    }

    return rows.where(matches).toList();
  }

  static const _linkedExpensesKey = 'linked_expenses_complete_v1';

  Future<void> saveLinkedExpenses(
    String businessId,
    List<Map<String, dynamic>> rows,
  ) async {
    await _save(businessId, _linkedExpensesKey, jsonEncode(rows));
  }

  Future<List<Map<String, dynamic>>?> loadLinkedExpenses(
    String businessId, {
    String? jobId,
    String? documentId,
  }) async {
    final raw = await _load(businessId, _linkedExpensesKey);
    if (raw == null) return null; // Not yet synchronized.
    try {
      final rows = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      return rows.where((row) =>
          (jobId == null || row['job_id']?.toString() == jobId) &&
          (documentId == null ||
              row['document_id']?.toString() == documentId)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTransactionDetail(
    String businessId,
    String transactionId,
    Map<String, dynamic> detail,
  ) async {
    await _save(
      businessId,
      'transaction_detail_$transactionId',
      jsonEncode(detail),
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
    if (raw == null || raw.isEmpty) return null;
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
    Map<String, dynamic> options,
  ) async {
    await _save(businessId, _optionsKey, jsonEncode(options));
  }

  Future<Map<String, dynamic>> loadOptions(String businessId) async {
    final raw = await _load(businessId, _optionsKey);
    if (raw == null || raw.isEmpty) return const {};
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
    String payload,
  ) async {
    await _database.customStatement(
      '''
      INSERT INTO local_financial_cache (
        business_id, cache_key, payload_json, updated_at
      ) VALUES (?, ?, ?, ?)
      ON CONFLICT(business_id, cache_key) DO UPDATE SET
        payload_json=excluded.payload_json,
        updated_at=excluded.updated_at
      ''',
      [
        businessId,
        key,
        payload,
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );
  }

  Future<String?> _load(String businessId, String key) async {
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
    if (rows.isEmpty) return null;
    return rows.first.read<String>('payload_json');
  }
}
