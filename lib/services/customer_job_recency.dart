/// Newest customer jobs first, independent of status and sync refresh time.
/// Imported MobileBiz job numbers and native J- numbers are different sequences,
/// so they must not be compared numerically across those namespaces.
int compareCustomerJobRecency(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  DateTime? created(Map<String, dynamic> row) {
    final raw = row['created_at']?.toString().trim() ?? '';
    return raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  final aDate = created(a);
  final bDate = created(b);
  if (aDate != null && bDate != null) {
    final order = bDate.compareTo(aDate);
    if (order != 0) return order;
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }

  String kind(Map<String, dynamic> row) {
    final number = row['number']?.toString().trim() ?? '';
    if (number.toUpperCase().startsWith('MB-')) return 'mobilebiz';
    if (RegExp(r'^J[- ]?[0-9]+\$', caseSensitive: false).hasMatch(number)) {
      return 'native';
    }
    return 'other';
  }

  final aKind = kind(a);
  final bKind = kind(b);
  if (aKind != bKind) {
    if (aKind == 'native') return -1;
    if (bKind == 'native') return 1;
  } else {
    int? number(Map<String, dynamic> row) {
      final raw = row['number']?.toString() ?? '';
      final matches = RegExp(r'[0-9]+').allMatches(raw).toList();
      return matches.isEmpty ? null : int.tryParse(matches.last.group(0)!);
    }
    final an = number(a);
    final bn = number(b);
    if (an != null && bn != null && an != bn) return bn.compareTo(an);
  }

  return (b['id']?.toString() ?? '').compareTo(a['id']?.toString() ?? '');
}
