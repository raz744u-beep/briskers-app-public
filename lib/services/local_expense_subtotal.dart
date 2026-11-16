import 'expenses_period_totals.dart';

/// An on-device subtotal, NOT evidence that all historical shop transactions
/// have been downloaded. Never mix invoice payment previews into this list:
/// they may represent the same financial movement as an existing transaction.
class LocalExpenseSubtotal {
  static Future<ExpensesPeriodTotals?> calculate(
    List<Map<String, dynamic>> rows, {
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    String? direction,
    String? accountId,
    String? categoryId,
    String? counterpartyId,
  }) async {
    final needle = search?.trim().toLowerCase() ?? '';
    final byId = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue; // Never fabricate financial identities.
      if (direction != null && row['direction']?.toString() != direction) continue;
      if (accountId != null && row['account_id']?.toString() != accountId) continue;
      if (categoryId != null && row['category_id']?.toString() != categoryId) continue;
      if (counterpartyId != null && row['counterparty_id']?.toString() != counterpartyId) continue;
      final parsed = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
      // An undated row cannot safely be included in a date-range subtotal.
      if (parsed == null) continue;
      final day = DateTime(parsed.year,parsed.month,parsed.day);
      if (startDate != null && day.isBefore(startDate)) continue;
      if (endDate != null && day.isAfter(endDate)) continue;
      if (needle.isNotEmpty) {
        final haystack = [
          row['counterparty'],row['category'],row['account'],row['remarks'],
          row['job_number'],row['job_title'],row['job_customer_name'],
          row['document_number'],row['amount'],row['transaction_date'],
        ].map((value)=>value?.toString().toLowerCase() ?? '').join(' ');
        if (!haystack.contains(needle)) continue;
      }
      byId[id] = row;
    }
    if (byId.isEmpty) return null;
    final entries = byId.values.toList();
    return ExpensesPeriodTotals.calculate(
      readPage: (offset, limit) async =>
        offset >= entries.length ? <Map<String, dynamic>>[] :
        entries.skip(offset).take(limit).toList(),
    );
  }
}
