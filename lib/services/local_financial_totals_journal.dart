import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'expenses_period_totals.dart';

/// Locally committed financial changes, independent of the network.
///
/// Entries are keyed by their stable local operation, not by amount or
/// customer name. Call record/remove inside the SAME Drift transaction as
/// the financial outbox write. This journal is a delta against the most recent
/// completely verified server period (not against the visible first 50 rows).
///
/// A local payment is included even while its sync status is pending.
class LocalFinancialTotalsJournal {
  LocalFinancialTotalsJournal({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;
  static const _cacheKey = 'financial_totals_local_delta_v1';

  Future<Map<String, dynamic>> _read(String businessId) async {
    final records = await _database.customSelect(
      'SELECT payload_json FROM local_financial_cache '
      'WHERE business_id=? AND cache_key=? LIMIT 1',
      variables: [Variable<String>(businessId), const Variable<String>(_cacheKey)],
    ).get();
    if (records.isEmpty) return {};
    try {
      final decoded = jsonDecode(records.single.read<String>('payload_json'));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      // A corrupt journal cannot justify inventing accounting totals.
      throw StateError('Local financial journal needs repair.');
    }
  }

  Future<void> _write(String businessId, Map<String, dynamic> journal) async {
    await _database.customStatement('''
      INSERT INTO local_financial_cache
        (business_id,cache_key,payload_json,updated_at) VALUES (?,?,?,?)
      ON CONFLICT(business_id,cache_key) DO UPDATE SET
        payload_json=excluded.payload_json,updated_at=excluded.updated_at
      ''', [businessId, _cacheKey, jsonEncode(journal),
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000]);
  }

  /// Preserve the ORIGINAL old value across repeated local edits. A new
  /// transaction has no old contribution. Deletes reverse its new amount.
  Future<void> record(String businessId, String key, {
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    if (key.isEmpty) throw ArgumentError('A stable financial ID is required.');
    final entries = await _read(businessId);
    final prior = entries[key];
    final first = prior is Map ? prior['before'] : before;
    if (first == null && after == null) {
      entries.remove(key);
    } else {
      entries[key] = {
        'before': first,
        'after': after,
      };
    }
    await _write(businessId, entries);
  }

  Future<void> remap(String businessId, String oldKey, String newKey,
      {String? newTransactionId}) async {
    final entries = await _read(businessId);
    final old = entries.remove(oldKey);
    if (old is! Map) return;
    if (entries.containsKey(newKey)) {
      throw StateError('Financial operation remap conflict.');
    }
    final current = old['after'];
    entries[newKey] = {
      ...old,
      'after': current is Map && newTransactionId != null
          ? {...current, 'id': newTransactionId} : current,
    };
    await _write(businessId, entries);
  }

  static DateTime? _date(Map<String, dynamic> row) =>
      DateTime.tryParse(row['transaction_date']?.toString() ?? '');

  // Reconciliation compares actual gross posted amounts. A verified
  // processor-fee reporting adjustment does not change payment identity.
  static int _rawAmountCents(Map<String, dynamic> row) {
    final amount = num.tryParse(row['amount']?.toString() ?? '');
    if (amount == null || !amount.isFinite || amount < 0) {
      throw StateError('Invalid posted transaction amount.');
    }
    return (amount * 100).round();
  }

  static int _cents(Map<String, dynamic> row) {
    final value = row['reporting_status'] == 'verified' &&
            row['direction'] == 'income' && row['reporting_amount'] != null
        ? row['reporting_amount'] : row['amount'];
    final number = num.tryParse(value?.toString() ?? '');
    if (number == null || !number.isFinite || number < 0) {
      throw StateError('Invalid saved local financial amount.');
    }
    return (number * 100).round();
  }

  static bool _within(Map<String, dynamic> row, {
    DateTime? startDate, DateTime? endDate, String? direction,
    String? search, String? accountId, String? categoryId,
    String? counterpartyId,
  }) {
    if (direction != null && row['direction']?.toString() != direction) {
      return false;
    }
    if (accountId != null && row['account_id']?.toString() != accountId) return false;
    if (categoryId != null && row['category_id']?.toString() != categoryId) return false;
    if (counterpartyId != null &&
        row['counterparty_id']?.toString() != counterpartyId) {
      return false;
    }
    final date = _date(row);
    if (date == null) throw StateError('Local financial date is missing.');
    final day = DateTime(date.year, date.month, date.day);
    if (startDate != null && day.isBefore(startDate)) return false;
    if (endDate != null && day.isAfter(endDate)) return false;
    final needle = search?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      final haystack = [
        row['counterparty'], row['category'], row['account'],
        row['remarks'], row['job_number'], row['document_number'],
        row['amount'], row['transaction_date'],
      ].map((x) => x?.toString().toLowerCase() ?? '').join(' ');
      if (!haystack.contains(needle)) return false;
    }
    return true;
  }

  /// Adds the locally committed changes to an already complete, saved
  /// accounting baseline. Never upgrades a partial server page to 'verified'.
  static ExpensesPeriodTotals project(
    ExpensesPeriodTotals base, Map<String, dynamic> entries, {
    DateTime? startDate, DateTime? endDate, String? direction,
    String? search, String? accountId, String? categoryId,
    String? counterpartyId,
  }) {
    var income = (base.income * 100).round();
    var expenses = (base.expenses * 100).round();
    int deltaCount = 0;
    for (final raw in entries.values) {
      if (raw is! Map) continue;
      for (final (value, sign) in [(raw['before'], -1), (raw['after'], 1)]) {
        if (value is! Map) continue;
        final row = Map<String, dynamic>.from(value);
        if (!_within(row, startDate: startDate, endDate: endDate,
            direction: direction, search: search, accountId: accountId,
            categoryId: categoryId, counterpartyId: counterpartyId)) {
          continue;
        }
        final amount = _cents(row) * sign;
        if (row['direction'] == 'income') {
          income += amount;
        } else if (row['direction'] == 'expense') {
          expenses += amount;
        } else {
          throw StateError('Unexpected financial direction.');
        }
        deltaCount += sign;
      }
    }
    if (income < 0 || expenses < 0) {
      throw StateError('Local totals conflict with the verified baseline.');
    }
    return ExpensesPeriodTotals(
      income: income / 100, expenses: expenses / 100,
      transactions: base.transactions + deltaCount,
      feesUnverified: base.feesUnverified,
      unverifiedIncomeReceipts: base.unverifiedIncomeReceipts,
    );
  }

  Future<ExpensesPeriodTotals> apply(String businessId,
      ExpensesPeriodTotals baseline, {
    DateTime? startDate, DateTime? endDate, String? direction,
    String? search, String? accountId, String? categoryId,
    String? counterpartyId,
  }) async => project(baseline, await _read(businessId),
      startDate: startDate, endDate: endDate, direction: direction,
      search: search, accountId: accountId, categoryId: categoryId,
      counterpartyId: counterpartyId);

  Future<int> pendingCount(String businessId) async =>
      (await _read(businessId)).length;

  /// Only full authenticated period reads may retire a delta. Never match on
  /// amount alone: server identity, direction, date and amount must all agree.
  /// For an invoice payment the server receipt must carry the exact operation
  /// ID and point to a posted transaction in this complete page.
  Future<void> reconcile(String businessId,
      List<Map<String, dynamic>> canonicalRows, {
    List<Map<String, dynamic>> receipts = const [],
  }) async {
    final entries = await _read(businessId);
    if (entries.isEmpty) return;
    final canonical = {
      for (final row in canonicalRows)
        if ((row['id']?.toString() ?? '').isNotEmpty)
          row['id'].toString(): row,
    };
    final linkedOperations = <String, String>{};
    for (final receipt in receipts) {
      if (receipt['receipt_state'] != 'posted') continue;
      final op = receipt['operation_id']?.toString() ?? '';
      final transaction = receipt['transaction_id']?.toString() ?? '';
      if (op.isNotEmpty && canonical.containsKey(transaction)) {
        linkedOperations[op] = transaction;
      }
    }
    var changed = false;
    for (final key in entries.keys.toList()) {
      final raw = entries[key];
      if (raw is! Map || raw['after'] is! Map) continue;
      final value = Map<String, dynamic>.from(raw['after'] as Map);
      final id = value['id']?.toString() ?? '';
      final posted = canonical[id] ??
          (key.startsWith('invoice-payment:')
              ? canonical[linkedOperations[key.substring('invoice-payment:'.length)]]
              : null);
      if (posted == null) continue;
      if (posted['direction'] == value['direction'] &&
          posted['transaction_date']?.toString().split('T').first ==
              value['transaction_date']?.toString().split('T').first &&
          _rawAmountCents(posted) == _rawAmountCents(value)) {
        entries.remove(key);
        changed = true;
      }
    }
    if (changed) await _write(businessId, entries);
  }
}
