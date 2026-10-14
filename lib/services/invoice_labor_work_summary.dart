import 'dart:async';
import 'dart:io';

String _descriptionKey(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Only labor description text is copied. Quantities, rates, tax and totals
/// never participate, so the Work Performed draft contains no billing fields.
String invoiceLaborWorkSummary(Map<String, dynamic> invoice) {
  if (invoice['kind'] != 'invoice') return '';
  final lines = invoice['lines'];
  if (lines is! List) return '';
  final seen = <String>{};
  return lines
      .whereType<Map>()
      .where((line) => line['line_kind'] == 'labor')
      .map((line) {
        final description = line['description']?.toString().trim() ?? '';
        return description.isNotEmpty
            ? description
            : line['name']?.toString().trim() ?? '';
      })
      .where((text) => text.isNotEmpty && seen.add(_descriptionKey(text)))
      .join('\n');
}

/// Keep the manual text intact, appending only description lines not present.
String appendInvoiceLaborWorkSummary(String existing, String invoiceLabor) {
  final current = existing.trim();
  final seen = current.split('\n').map(_descriptionKey).toSet();
  final additions = invoiceLabor
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && seen.add(_descriptionKey(line)))
      .toList();
  return [if (current.isNotEmpty) current, ...additions].join('\n');
}

/// Auto mode may use a known local snapshot after transport failure only.
/// Authentication/authorization/RPC errors must never become cached access.
Future<T> readInvoiceLaborSource<T>({
  required Future<T> Function() onlineRead,
  required Future<T> Function() cachedRead,
  bool forceOffline = false,
  bool forceOnline = false,
}) async {
  if (forceOffline) return cachedRead();
  try {
    return await onlineRead();
  } on SocketException {
    if (forceOnline) rethrow;
    return cachedRead();
  } on TimeoutException {
    if (forceOnline) rethrow;
    return cachedRead();
  }
}
