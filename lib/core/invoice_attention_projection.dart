/// Remove only proven closed invoice identities. A limited server list may
/// contain fewer rows than its count, so retain the unknown remainder.
Map<String, dynamic> withoutClosedAttentionInvoices(
  Map<String, dynamic> snapshot, Set<String> closed,
) {
  final raw = snapshot['pending_close_invoices'];
  if (raw is! List || closed.isEmpty) return snapshot;
  final removed = <String>{};
  final items = <dynamic>[];
  for (final item in raw) {
    final id = item is Map ? (item['id'] ?? item['invoice_id'])?.toString() ?? '' : '';
    if (id.isNotEmpty && closed.contains(id)) {
      removed.add(id);
    } else {
      items.add(item);
    }
  }
  if (removed.isEmpty) return snapshot;
  final counts = snapshot['counts'] is Map
      ? Map<String, dynamic>.from(snapshot['counts'] as Map) : <String, dynamic>{};
  final count = int.tryParse(counts['pending_close_invoices']?.toString() ?? '') ?? raw.length;
  return {...snapshot, 'pending_close_invoices': items,
    'counts': {...counts, 'pending_close_invoices': count < removed.length ? 0 : count - removed.length}};
}
