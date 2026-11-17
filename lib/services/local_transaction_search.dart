import 'package:intl/intl.dart';

/// Search the same saved fields in posted transactions and invoice receipts.
class LocalTransactionSearch {
  static bool matches(Map<String, dynamic> row, String? query) {
    final text = query?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return true;
    final number = row['document_number']?.toString() ?? '';
    final amount = num.tryParse(row['amount']?.toString() ?? '');
    final rawDate = row['transaction_date']?.toString() ?? '';
    final date = DateTime.tryParse(rawDate);
    final fields =
        [
              row['counterparty'],
              row['customer_name'],
              row['vendor_name'],
              row['job_customer_name'],
              row['job_number'],
              row['job_title'],
              row['category'],
              row['account'],
              row['remarks'],
              row['payment_method'],
              row['payment_method_name'],
              number,
              if (number.isNotEmpty) 'invoice #$number',
              row['amount'],
              if (amount != null) ...[
                amount.toStringAsFixed(2),
                NumberFormat.currency(
                  locale: 'en_US',
                  symbol: '\$',
                ).format(amount),
              ],
              rawDate,
              if (date != null) ...[
                DateFormat('M/d/yyyy', 'en_US').format(date),
                DateFormat('MM/dd/yyyy', 'en_US').format(date),
                DateFormat('MMM d, yyyy', 'en_US').format(date),
                DateFormat('MMMM d, yyyy', 'en_US').format(date),
              ],
            ]
            .whereType<Object>()
            .map((field) => field.toString().toLowerCase())
            .join(' ');
    return fields.contains(text) ||
        text.split(RegExp(r'\s+')).every(fields.contains);
  }
}
