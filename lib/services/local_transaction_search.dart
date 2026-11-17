import 'package:intl/intl.dart';

/// Search the same saved fields in posted transactions and invoice receipts.
class LocalTransactionSearch {
  static bool matches(Map<String, dynamic> row, String? query) {
    final text = query?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return true;
    final haystack = fields(row);
    return haystack.contains(text) ||
        text.split(RegExp(r'\s+')).every(haystack.contains);
  }

  static final _currency = NumberFormat.currency(locale: 'en_US', symbol: '\$');
  static final _dates = [
    for (final pattern in [
      'M/d/yyyy',
      'MM/dd/yyyy',
      'MMM d, yyyy',
      'MMMM d, yyyy',
    ])
      DateFormat(pattern, 'en_US'),
  ];

  static String fields(Map<String, dynamic> row) {
    final number = row['document_number']?.toString() ?? '';
    final amount = num.tryParse(row['amount']?.toString() ?? '');
    final rawDate = row['transaction_date']?.toString() ?? '';
    final date = DateTime.tryParse(rawDate);
    return [
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
            _currency.format(amount),
          ],
          rawDate,
          if (date != null)
            for (final format in _dates) format.format(date),
        ]
        .whereType<Object>()
        .map((field) => field.toString().toLowerCase())
        .join(' ');
  }
}
