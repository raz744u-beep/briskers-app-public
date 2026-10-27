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


  /// Same business/role/search/classification filters across a date rollover.
  String? _rollingKey(String scope) {
    final fields = scope.split('|');
    if (fields.length != 9 || fields[0].isEmpty || fields[1].isEmpty) {
      return null;
    }
    final start = DateTime.tryParse(fields[2]);
    final end = DateTime.tryParse(fields[3]);
    if (start == null || end == null || end.isBefore(start)) return null;
    // A custom 1-day or year-to-date verification must not replace the
    // 30-day complete snapshot that keeps that window fast tomorrow.
    final startDay = DateTime.utc(start.year, start.month, start.day);
    final endDay = DateTime.utc(end.year, end.month, end.day);
    final periodDays = endDay.difference(startDay).inDays + 1;
    return 'financial_verified_daily_v1_${fields[0]}|${fields[1]}|'
        '${fields[4]}|${fields[5]}|${fields[6]}|${fields[7]}|${fields[8]}|$periodDays';
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Reconstruct a shifted date window from days known to be complete.
  /// The newly arrived day is NOT server-verified; UI must mark sync pending.
  Future<({ExpensesPeriodTotals totals, DateTime at, DateTime verifiedThrough})?>
      loadRollingBaseline(
    String businessId, String scope, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final key = _rollingKey(scope);
    if (key == null || !scope.startsWith('$businessId|')) return null;
    final requestStart = _dateKey(startDate);
    final requestEnd = _dateKey(endDate);
    if (requestStart.compareTo(requestEnd) > 0) return null;
    final records = await _database.customSelect(
      'SELECT payload_json FROM local_financial_cache '
      'WHERE business_id=? AND cache_key=? LIMIT 1',
      variables: [Variable<String>(businessId), Variable<String>(key)],
    ).get();
    if (records.isEmpty) return null;
    try {
      final saved = Map<String, dynamic>.from(
        jsonDecode(records.single.read<String>('payload_json')) as Map,
      );
      final verifiedStart = saved['rangeStart']?.toString() ?? '';
      final verifiedEnd = saved['rangeEnd']?.toString() ?? '';
      if (requestStart.compareTo(verifiedStart) < 0 ||
          requestStart.compareTo(verifiedEnd) > 0) {
        return null;
      }
      final verifiedAt = DateTime.parse(saved['verifiedAt'] as String).toLocal();
      final lastVerifiedDay = DateTime.parse(verifiedEnd);
      final requestedEnd = DateTime.parse(requestEnd);
      final missingDays = DateTime.utc(
        requestedEnd.year, requestedEnd.month, requestedEnd.day,
      ).difference(DateTime.utc(
        lastVerifiedDay.year, lastVerifiedDay.month, lastVerifiedDay.day,
      )).inDays;
      if (verifiedAt.isAfter(DateTime.now()) ||
          missingDays > 7 || missingDays < 0) {
        return null;
      }
      final daily = Map<String, dynamic>.from(saved['days'] as Map);
      var incomeCents = 0;
      var expenseCents = 0;
      var count = 0;
      var unknown = 0;
      for (final item in daily.entries) {
        if (item.key.compareTo(requestStart) < 0 ||
            item.key.compareTo(requestEnd) > 0) {
          continue;
        }
        if (item.key.compareTo(verifiedEnd) > 0 ||
            item.key.compareTo(verifiedStart) < 0) {
          return null;
        }
        final raw = Map<String, dynamic>.from(item.value as Map);
        final income = raw['incomeCents'];
        final expense = raw['expensesCents'];
        final transactions = raw['transactions'];
        final unverified = raw['unverifiedIncomeReceipts'];
        if (income is! int || expense is! int ||
            transactions is! int || unverified is! int ||
            income < 0 || expense < 0 ||
            transactions < 0 || unverified < 0) {
          return null;
        }
        incomeCents += income;
        expenseCents += expense;
        count += transactions;
        unknown += unverified;
      }
      return (
        totals: ExpensesPeriodTotals(
          income: incomeCents / 100,
          expenses: expenseCents / 100,
          transactions: count,
          feesUnverified: unknown > 0,
          unverifiedIncomeReceipts: unknown,
        ),
        at: verifiedAt,
        verifiedThrough: lastVerifiedDay,
      );
    } catch (_) {
      // A malformed historic snapshot cannot authorize a guessed total.
      return null;
    }
  }

  /// Complete authenticated scans only. Preserve scope and processor-fee
  /// reporting, and never save a partial list as verified daily totals.
  Future<void> _saveRollingBuckets(
    String businessId, String scope,
    ExpensesPeriodTotals totals, DateTime verifiedAt,
  ) async {
    final fields = scope.split('|');
    final key = _rollingKey(scope);
    final daily = totals.dailyBreakdown;
    if (key == null || daily == null ||
        fields[0] != businessId ||
        fields[2].isEmpty || fields[3].isEmpty) {
      return;
    }
    final start = fields[2].split('T').first;
    final end = fields[3].split('T').first;
    final days = <String, dynamic>{};
    var incomeCents = 0;
    var expenseCents = 0;
    var count = 0;
    var unknown = 0;
    for (final item in daily.entries) {
      if (item.key.compareTo(start) < 0 ||
          item.key.compareTo(end) > 0) {
        return;
      }
      final day = item.value;
      incomeCents += day.incomeCents;
      expenseCents += day.expensesCents;
      count += day.transactions;
      unknown += day.unverifiedIncomeReceipts;
      days[item.key] = {
        'incomeCents': day.incomeCents,
        'expensesCents': day.expensesCents,
        'transactions': day.transactions,
        'unverifiedIncomeReceipts': day.unverifiedIncomeReceipts,
      };
    }
    if (incomeCents != (totals.income * 100).round() ||
        expenseCents != (totals.expenses * 100).round() ||
        count != totals.transactions ||
        unknown != totals.unverifiedIncomeReceipts) {
      return;
    }
    await _database.customStatement('''
      INSERT INTO local_financial_cache
        (business_id,cache_key,payload_json,updated_at) VALUES (?,?,?,?)
      ON CONFLICT(business_id,cache_key) DO UPDATE SET
        payload_json=excluded.payload_json,updated_at=excluded.updated_at
      ''', [
      businessId, key,
      jsonEncode({
        'rangeStart': start,
        'rangeEnd': end,
        'verifiedAt': verifiedAt.toUtc().toIso8601String(),
        'days': days,
      }), DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    ]);
  }

  String _baselineKey(String scope) => 'financial_baseline_v1_$scope';

  /// Durable, full-scope last-verified baseline in the SAME local SQLite
  /// database as the pending financial journal.
  Future<({ExpensesPeriodTotals totals, DateTime at})?> loadBaseline(
      String businessId, String scope) async {
    final rows = await _database.customSelect(
      'SELECT payload_json FROM local_financial_cache '
      'WHERE business_id=? AND cache_key=? LIMIT 1',
      variables: [Variable<String>(businessId),
        Variable<String>(_baselineKey(scope))],
    ).get();
    if (rows.isEmpty) return null;
    try {
      final saved = Map<String, dynamic>.from(
        jsonDecode(rows.single.read<String>('payload_json')) as Map);
      final income = (saved['income'] as num).toDouble();
      final expenses = (saved['expenses'] as num).toDouble();
      final transactions = saved['transactions'] as int;
      final at = DateTime.parse(saved['verifiedAt'] as String).toLocal();
      if (!income.isFinite || income < 0 ||
          !expenses.isFinite || expenses < 0 ||
          transactions < 0 || at.isAfter(DateTime.now())) {
        throw StateError('Invalid saved verified baseline.');
      }
      return (totals: ExpensesPeriodTotals(
        income: income, expenses: expenses, transactions: transactions,
        feesUnverified: saved['feesUnverified'] == true,
        unverifiedIncomeReceipts: saved['unverifiedIncomeReceipts'] is int
            ? saved['unverifiedIncomeReceipts'] as int : null,
      ), at: at);
    } catch (_) {
      // Never publish a corrupted local accounting snapshot as verified.
      throw StateError('Local verified financial baseline needs repair.');
    }
  }

  Future<void> _writeBaseline(String businessId, String scope,
      ExpensesPeriodTotals totals, DateTime at) async {
    await _database.customStatement('''
      INSERT INTO local_financial_cache
        (business_id,cache_key,payload_json,updated_at) VALUES (?,?,?,?)
      ON CONFLICT(business_id,cache_key) DO UPDATE SET
        payload_json=excluded.payload_json,updated_at=excluded.updated_at
      ''', [
      businessId, _baselineKey(scope),
      jsonEncode({
        'income': totals.income, 'expenses': totals.expenses,
        'transactions': totals.transactions,
        'feesUnverified': totals.feesUnverified,
        'unverifiedIncomeReceipts': totals.unverifiedIncomeReceipts,
        'verifiedAt': at.toUtc().toIso8601String(),
      }), DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    ]);
  }

  Future<void> saveBaseline(String businessId, String scope,
      ExpensesPeriodTotals totals, DateTime at) async {
    await _database.transaction(
      () async => _writeBaseline(businessId, scope, totals, at),
    );
  }

  /// Server proof + journal retirement + the replacement baseline succeed
  /// or roll back as ONE local transaction. A crash never drops a delta while
  /// leaving the old server total behind.
  Future<void> reconcileAndSaveBaseline(
    String businessId, String scope, ExpensesPeriodTotals totals, DateTime at,
    List<Map<String, dynamic>> canonicalRows, {
    List<Map<String, dynamic>> receipts = const [],
  }) async {
    await _database.transaction(() async {
      await reconcile(businessId, canonicalRows, receipts: receipts);
      await _writeBaseline(businessId, scope, totals, at);
      await _saveRollingBuckets(businessId, scope, totals, at);
    });
  }

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
