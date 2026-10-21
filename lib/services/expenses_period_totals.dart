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
  });

  final double income;
  final double expenses;
  final int transactions;
  final bool feesUnverified;

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
    var unverified = false;
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
        final direction = row['direction']?.toString();
        if (direction == 'income') {
          final verified = row['reporting_status'] == 'verified';
          final value = verified && row['reporting_amount'] != null
              ? row['reporting_amount'] : row['amount'];
          incomeCents += (_money(value) * 100).round();
          if (!verified) unverified = true;
        } else if (direction == 'expense') {
          expenseCents += (_money(row['amount']) * 100).round();
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
      feesUnverified: unverified,
    );
  }
}
