/// Day-level totals retain the EXACT net processor-fee reporting that was
/// used to verify the full period, in integer cents. They can be reused after
/// midnight without re-reading historical transaction pages.
class ExpensesDayTotals {
  const ExpensesDayTotals({
    required this.incomeCents,
    required this.expensesCents,
    required this.transactions,
    required this.unverifiedIncomeReceipts,
  });
  final int incomeCents;
  final int expensesCents;
  final int transactions;
  final int unverifiedIncomeReceipts;
}

class _DayAccumulator {
  int incomeCents = 0;
  int expensesCents = 0;
  int transactions = 0;
  int unverifiedIncomeReceipts = 0;

  ExpensesDayTotals freeze() => ExpensesDayTotals(
    incomeCents: incomeCents,
    expensesCents: expensesCents,
    transactions: transactions,
    unverifiedIncomeReceipts: unverifiedIncomeReceipts,
  );
}

/// Complete, read-only financial transaction totals over a selected scope.
///
/// The list UI displays a page of transactions, not an accounting total.
/// Never produce a figure until ALL pages have been fetched. Do not add
/// invoice-receipt projections here: they can duplicate canonical entries.
class ExpensesPeriodTotals {
  const ExpensesPeriodTotals({
    required this.income,
    required this.expenses,
    required this.transactions,
    required this.feesUnverified,
    this.unverifiedIncomeReceipts,
    this.dailyBreakdown,
  });

  final double income;
  final double expenses;
  final int transactions;
  // Unknown on older snapshots. Not every unverified receipt has a card fee.
  final int? unverifiedIncomeReceipts;
  final bool feesUnverified;

  /// Present only for a complete scan with trustworthy dates on EVERY row.
  /// The existence of this map doesn't mean a future day has been verified.
  final Map<String, ExpensesDayTotals>? dailyBreakdown;

  static String? _dayKey(Object? raw) {
    final key = raw?.toString().split('T').first ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return null;
    final parsed = DateTime.tryParse(key);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != key) {
      return null;
    }
    return key;
  }

  static double _money(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '');
    if (value == null || !value.isFinite || value < 0) {
      throw StateError('A posted transaction has an invalid amount.');
    }
    return value.toDouble();
  }

  /// Offset pages must be the exact same filter/date scope. A changed filter
  /// cancels the calculation instead of publishing a stale number.
  static Future<ExpensesPeriodTotals> calculate({
    required Future<List<Map<String, dynamic>>> Function(int offset, int limit)
        readPage,
    Future<List<Map<String, dynamic>>> Function(List<Map<String, dynamic>>)
        ? enrichPage,
    bool Function()? isCurrent,
    int pageSize = 200,
    int maxPages = 250,
  }) async {
    if (pageSize <= 0 || maxPages <= 0) {
      throw ArgumentError('Page size and maximum pages must be positive.');
    }
    final byIdentity = <String, Map<String, dynamic>>{};
    var complete = false;
    // A single page is cheapest for 30-day views. When that page is full,
    // request up to three subsequent pages concurrently. Preserve page order
    // and require an actual short/empty terminal page before totaling.
    var nextPage = 0;
    while (nextPage < maxPages && !complete) {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Period changed while totals were loading.');
      }
      final batchSize = nextPage == 0
          ? 1
          : (maxPages - nextPage < 3 ? maxPages - nextPage : 3);
      final pages = await Future.wait([
        for (var index = 0; index < batchSize; index++)
          readPage((nextPage + index) * pageSize, pageSize),
      ]);
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Period changed while totals were loading.');
      }
      for (final fetched in pages) {
        if (fetched.length > pageSize) {
          throw StateError('Transaction endpoint exceeded its page size.');
        }
        for (final row in fetched) {
          final id = row['id']?.toString() ?? '';
          if (id.isEmpty) {
            throw StateError('Cannot total a transaction without a stable ID.');
          }
          byIdentity[id] = row;
        }
        if (fetched.length < pageSize) {
          complete = true;
          break;
        }
      }
      nextPage += batchSize;
    }
    if (!complete) {
      throw StateError('Could not verify all transactions in this period.');
    }

    var incomeCents = 0;
    var expenseCents = 0;
    var unverifiedIncomeCount = 0;
    var dailyComplete = true;
    final days = <String, _DayAccumulator>{};
    final rows = byIdentity.values.toList();
    // Reusing one fee-evidence snapshot across up to 1,000 transactions
    // avoids scanning the same local invoice cache for every small page.
    const enrichmentBatch = 1000;
    for (var i = 0; i < rows.length; i += enrichmentBatch) {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Period changed while totals were loading.');
      }
      final last = i + enrichmentBatch < rows.length
          ? i + enrichmentBatch : rows.length;
      final chunk = rows.sublist(i, last);
      final enriched = enrichPage == null ? chunk : await enrichPage(chunk);
      if (enriched.length != chunk.length) {
        throw StateError('Transaction reporting returned an incomplete batch.');
      }
      for (final row in enriched) {
        final dayKey = _dayKey(row['transaction_date']);
        if (dayKey == null) dailyComplete = false;
        final day = dayKey == null
            ? null : days.putIfAbsent(dayKey, _DayAccumulator.new);
        if (day != null) day.transactions++;
        final direction = row['direction']?.toString();
        if (direction == 'income') {
          final verified = row['reporting_status'] == 'verified';
          final value = verified && row['reporting_amount'] != null
              ? row['reporting_amount'] : row['amount'];
          final cents = (_money(value) * 100).round();
          incomeCents += cents;
          if (day != null) day.incomeCents += cents;
          if (!verified) {
            unverifiedIncomeCount++;
            if (day != null) day.unverifiedIncomeReceipts++;
          }
        } else if (direction == 'expense') {
          final cents = (_money(row['amount']) * 100).round();
          expenseCents += cents;
          if (day != null) day.expensesCents += cents;
        } else {
          throw StateError('Unexpected posted transaction direction.');
        }
      }
    }
    if (isCurrent != null && !isCurrent()) {
      throw StateError('Period changed while totals were loading.');
    }
    return ExpensesPeriodTotals(
      income: incomeCents / 100,
      expenses: expenseCents / 100,
      transactions: rows.length,
      feesUnverified: unverifiedIncomeCount > 0,
      unverifiedIncomeReceipts: unverifiedIncomeCount,
      dailyBreakdown: dailyComplete
          ? {for (final entry in days.entries) entry.key: entry.value.freeze()}
          : null,
    );
  }
}
