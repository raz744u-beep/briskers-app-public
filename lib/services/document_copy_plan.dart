/// Pure copy planning. The original document is NEVER mutated.
class DocumentCopyPlan {
  const DocumentCopyPlan._();

  /// Every estimate copy is standalone; every invoice copy requires a new Job.
  static Map<String, dynamic> prepare(
    Map<String, dynamic> original, {
    required String customerId,
    required String? vehicleId,
    bool includeOriginalNotes = false,
  }) {
    final kind = original['kind']?.toString();
    if (kind != 'invoice' && kind != 'estimate') {
      throw ArgumentError('Only estimates and invoices can be copied.');
    }
    if (customerId.trim().isEmpty) {
      throw ArgumentError('Select an existing customer.');
    }
    final sourceLines = original['lines'] is List
        ? original['lines']
        : original['items'];
    if (sourceLines is! List) {
      throw ArgumentError('Load the original items before copying.');
    }
    return <String, dynamic>{
      'kind': kind,
      'customer_id': customerId,
      'vehicle_id': vehicleId,
      'requires_new_job': kind == 'invoice',
      'job_id': null,
      'document_number': null,
      'status': 'draft',
      'paid_amount': 0,
      'pending_payment': 0,
      'closed_at': null,
      'converted': false,
      // Customer-visible notes must never be copied by default.
      // A source-reference note, if present, is copied only by opt-in.
      'memo': includeOriginalNotes ? original['memo']?.toString() : null,
      'lines': [
        for (final item in sourceLines)
          if (item is Map)
            <String, dynamic>{
              'name': item['name']?.toString() ?? '',
              'description': item['description']?.toString(),
              'item_id': item['item_id']?.toString(),
              'line_kind': item['line_kind']?.toString() ?? 'item',
              'quantity': item['quantity'],
              'unit_price': item['unit_price'],
              'tax_rate': item['tax_rate'],
            },
      ],
    };
  }
}
