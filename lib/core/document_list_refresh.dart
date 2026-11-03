import 'dart:async';

/// Shares an in-flight read when no newer freshness boundary is requested.
/// Re-entry or a local action queues one more pass, so a pre-action response
/// cannot be the final result. All callers wait for that pass too.
class DocumentListRefresh {
  Future<void>? _active;
  bool _again = false;

  Future<void> run(
    Future<void> Function() refresh, {
    bool afterCurrent = false,
  }) {
    final active = _active;
    if (active != null) {
      _again |= afterCurrent;
      return active;
    }

    final completion = Completer<void>();
    _active = completion.future;
    unawaited(() async {
      try {
        do {
          _again = false;
          await refresh();
        } while (_again);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _active = null;
      }
    }());
    return completion.future;
  }
}

/// Compares JSON-shaped API data without allocating serialized copies.
/// Map insertion order is irrelevant; list order and every financial/status
/// field remain significant.
bool documentListDataEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!documentListDataEquals(left[i], right[i])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) ||
          !documentListDataEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

/// Sort once per changed snapshot, not again for every search keystroke or
/// payment-total repaint. Parse each number once rather than in the comparator.
List<Map<String, dynamic>> orderDocumentListRows(
  List<Map<String, dynamic>> rows, {
  required bool estimate,
}) {
  final digits = RegExp(r'[0-9]+');
  final keyed = rows.map((row) {
    final matches = digits
        .allMatches(row['document_number']?.toString() ?? '')
        .toList();
    return (
      row: row,
      number: matches.isEmpty ? null : int.tryParse(matches.last.group(0)!),
    );
  }).toList();
  keyed.sort((a, b) {
    final aNumber = a.number;
    final bNumber = b.number;
    if (aNumber != null && bNumber != null) {
      final order = bNumber.compareTo(aNumber);
      if (order != 0) return order;
    } else if (aNumber != null) {
      // Retain existing invoice behavior: unnumbered working drafts first.
      return estimate ? -1 : 1;
    } else if (bNumber != null) {
      return estimate ? 1 : -1;
    }
    if (estimate) {
      final dateOrder = (b.row['document_date']?.toString() ?? '').compareTo(
        a.row['document_date']?.toString() ?? '',
      );
      if (dateOrder != 0) return dateOrder;
    }
    return (b.row['created_at']?.toString() ?? '').compareTo(
      a.row['created_at']?.toString() ?? '',
    );
  });
  return keyed.map((item) => item.row).toList();
}
