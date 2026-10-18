/// Customer Overview recency uses the document's business date, not the
/// server sync/update timestamp. Refreshing an old import must not push it
/// ahead of a newly created invoice or estimate.
int compareCustomerDocumentRecency(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  DateTime? date(Map<String, dynamic> row, String field) {
    final raw = row[field]?.toString().trim() ?? '';
    return raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  DateTime recency(Map<String, dynamic> row) =>
      date(row, 'document_date') ??
      date(row, 'server_updated_at') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final byDate = recency(b).compareTo(recency(a));
  if (byDate != 0) return byDate;

  // Same type/day: use the stable document number, matching the main
  // Invoices and Estimates lists. This works for E-2002 and I-6350.
  if (a['type']?.toString() == b['type']?.toString()) {
    int? number(Map<String, dynamic> row) {
      final raw = row['number']?.toString() ?? '';
      final matches = RegExp(r'[0-9]+').allMatches(raw).toList();
      if (matches.isEmpty) return null;
      return int.tryParse(matches.last.group(0)!);
    }

    final an = number(a);
    final bn = number(b);
    if (an != null && bn != null && an != bn) {
      return bn.compareTo(an);
    }
    if (an != null && bn == null) return -1;
    if (an == null && bn != null) return 1;
  }

  final byUpdate =
      (b['server_updated_at']?.toString() ?? '').compareTo(
        a['server_updated_at']?.toString() ?? '',
      );
  if (byUpdate != 0) return byUpdate;
  return (b['id']?.toString() ?? '').compareTo(a['id']?.toString() ?? '');
}
