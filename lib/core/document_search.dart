import 'package:intl/intl.dart';

/// Consistent filtering for online and locally cached estimate/invoice lists.
/// A search containing only digits identifies the document number, not dates,
/// job numbers, telephone fragments or vehicle descriptions.
BigInt? normalizedDocumentNumber(Object? source) {
  final text = source?.toString().trim() ?? '';
  final match = RegExp(
    r'^(?:(?:invoice|estimate|inv|est|mb|i|e)[\s#:-]*)?([0-9]+)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  return BigInt.tryParse(match.group(1)!);
}

bool matchesDocumentSearch(
  Map<String, dynamic> document,
  String search, {
  bool includeDate = false,
}) {
  final query = search.trim().toLowerCase();
  if (query.isEmpty) return true;

  final queryNumber = normalizedDocumentNumber(query);
  if (queryNumber != null) {
    return normalizedDocumentNumber(document['document_number']) == queryNumber;
  }

  final date = includeDate
      ? DateTime.tryParse(document['document_date']?.toString() ?? '')
      : null;
  return <Object?>[
    document['document_number'],
    document['customer_name'],
    document['vehicle'],
    document['job_number'],
    if (date != null) ...[
      date.toIso8601String().split('T').first,
      DateFormat('M/d/yyyy', 'en_US').format(date),
      DateFormat('MMM d, yyyy', 'en_US').format(date),
    ],
  ].whereType<Object>().any(
        (value) => value.toString().toLowerCase().contains(query),
      );
}
