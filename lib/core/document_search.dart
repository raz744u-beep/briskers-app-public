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

bool matchesDocumentSearch(Map<String, dynamic> document, String search) {
  final query = search.trim().toLowerCase();
  if (query.isEmpty) return true;

  final queryNumber = normalizedDocumentNumber(query);
  if (queryNumber != null) {
    return normalizedDocumentNumber(document['document_number']) == queryNumber;
  }

  return <Object?>[
    document['document_number'],
    document['customer_name'],
    document['vehicle'],
    document['job_number'],
  ].whereType<Object>().any(
        (value) => value.toString().toLowerCase().contains(query),
      );
}
