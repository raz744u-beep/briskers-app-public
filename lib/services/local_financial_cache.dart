import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

class LocalFinancialCache {
  LocalFinancialCache({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  static const _transactionsKey = 'transactions_snapshot';
  static const _optionsKey = 'transaction_options';
  static const _invoiceReceiptsKey = 'invoice_receipts_v1';
  static const _serverTransactionProofKey = 'server_transaction_proof_v1';
  static const _proofTtl = Duration(days: 7);

  /// A read-only provenance fingerprint for server-returned transaction rows.
  /// An edited local amount/date/direction cannot reuse an old green cloud.
  static String serverTransactionSignature(Map<String, dynamic> row) =>
      jsonEncode([
        row['id']?.toString(),
        row['direction']?.toString(),
        row['amount']?.toString(),
        row['transaction_date']?.toString(),
      ]);

  /// Restores *historical* server evidence, not a fresh sync acknowledgement.
  /// Business-scoped and short lived. Missing/corrupt/expired proof is unknown.
  Future<Map<String, String>> loadServerConfirmedTransactions(
    String businessId,
  ) async {
    final raw = await _load(businessId, _serverTransactionProofKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final root = jsonDecode(raw);
      if (root is! Map) return const {};
      final records = root['entries'];
      if (records is! Map) return const {};
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final restored = <String, String>{};
      for (final record in records.entries) {
        if (record.key is! String || record.value is! Map) continue;
        final stamp = record.value['verified_at'];
        final signature = record.value['signature'];
        if (stamp is! int || signature is! String ||
            signature.isEmpty || stamp > now ||
            now - stamp > _proofTtl.inMilliseconds) {
          continue;
        }
        restored[record.key as String] = signature;
      }
      return restored;
    } catch (_) {
      return const {};
    }
  }

  /// Persist proofs only from a successful authenticated server result,
  /// never from previously cached/offline rows or a pending local outbox.
  Future<void> saveServerConfirmedTransactions(
    String businessId,
    List<Map<String, dynamic>> serverRows,
  ) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final records = <String, dynamic>{};
    final raw = await _load(businessId, _serverTransactionProofKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        final old = decoded is Map ? decoded['entries'] : null;
        if (old is Map) {
          for (final entry in old.entries) {
            if (entry.key is! String || entry.value is! Map) continue;
            final stamp = entry.value['verified_at'];
            if (stamp is int && stamp <= now &&
                now - stamp <= _proofTtl.inMilliseconds) {
              records[entry.key as String] = entry.value;
            }
          }
        }
      } catch (_) {
        // Corrupt old proof does not stop new authoritative evidence.
      }
    }
    for (final row in serverRows) {
      final id = row['id']?.toString() ?? '';
      final state = row['sync_state']?.toString().toLowerCase() ?? '';
      if (id.isEmpty || row['direction'] == null ||
          row['amount'] == null ||
          const {'pending', 'pending_sync', 'queued', 'failed', 'error',
                 'conflict'}.contains(state)) {
        continue;
      }
      records[id] = {
        'signature': serverTransactionSignature(row),
        'verified_at': now,
      };
    }
    // Bound local storage for shops with very large historical archives.
    final newest = records.entries.toList()
      ..sort((a, b) =>
        ((b.value as Map)['verified_at'] as int).compareTo(
          (a.value as Map)['verified_at'] as int));
    await _save(
      businessId,
      _serverTransactionProofKey,
      jsonEncode({
        'entries': {
          for (final entry in newest.take(2500)) entry.key: entry.value,
        },
      }),
    );
  }

  Future<void> saveInvoiceReceipts(String businessId, List<Map<String,dynamic>> rows) =>
      _save(businessId, _invoiceReceiptsKey, jsonEncode(rows));

  /// Distinguish "RPC cache never populated" from "server has no receipts".
  Future<bool> hasServerInvoiceReceipts(String businessId) async =>
      await _load(businessId, _invoiceReceiptsKey) != null;

  Future<List<Map<String,dynamic>>> loadInvoiceReceipts(String businessId) async {
    final raw = await _load(businessId, _invoiceReceiptsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>()
          .map((row) => Map<String,dynamic>.from(row)).toList();
    } catch (_) { return const []; }
  }


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

  /// Refresh the server's limited list without erasing locally committed
  /// transactions/edits that are still queued for synchronization. Both the
  /// overlay read and persisted result share a single SQLite transaction.
  Future<void> mergeServerTransactions(
    String businessId, List<Map<String, dynamic>> serverRows,
  ) async {
    await _database.transaction(() async {
      final saved = await loadTransactions(businessId);
      final pending = <String, Map<String, dynamic>>{
        for (final row in saved)
          if (row['sync_state']?.toString() == 'pending' &&
              (row['id']?.toString() ?? '').isNotEmpty)
            row['id'].toString(): row,
      };
      final seen = <String>{};
      final merged = <Map<String, dynamic>>[
        for (final row in serverRows)
          if (seen.add(row['id']?.toString() ?? ''))
            pending[row['id']?.toString()] ?? row,
        for (final entry in pending.entries)
          if (!seen.contains(entry.key)) entry.value,
      ];
      merged.sort((a, b) =>
        (b['transaction_date']?.toString() ?? '').compareTo(
        a['transaction_date']?.toString() ?? ''));
      await saveTransactions(businessId, merged);
    });
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

    if (raw == null && rows.isEmpty) return null;
    return rows.where((row) =>
        (jobId == null || row['job_id']?.toString() == jobId) &&
        (documentId == null ||
            row['document_id']?.toString() == documentId)).toList();
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
