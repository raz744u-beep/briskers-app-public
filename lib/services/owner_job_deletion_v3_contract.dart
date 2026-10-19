import 'dart:convert';

const ownerDeletionV3Protocol = 'owner-deletion-3.0';

class JobDeletionV3Unavailable implements Exception {
  const JobDeletionV3Unavailable();
  @override
  String toString() => 'Job deletion is temporarily unavailable. Nothing has been deleted.';
}

class JobDeletionV3ReviewRequired implements Exception {
  const JobDeletionV3ReviewRequired();
  @override
  String toString() => 'The linked records changed. Review a new deletion preview. Nothing has been deleted.';
}

String deletionV3FailureMessage(Object error) {
  if (error is JobDeletionV3Unavailable || error is JobDeletionV3ReviewRequired) {
    return error.toString();
  }
  if (error is StateError) return error.message;
  if (error is FormatException) return 'The deletion details could not be verified. Refresh the Job and review again.';
  return 'Deletion could not be completed. Check the connection and try again.';
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String deletionV3Canonical(Object? value) => jsonEncode(_canonical(value));

bool isDeletionV3Id(Object? value) => value is String && RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);

const deletionV3UuidKinds = {
  'job', 'invoice', 'estimate', 'payment', 'transaction', 'job_assignment',
  'job_visit', 'pre_inspection', 'pre_inspection_photo', 'finding', 'attachment',
  'appointment', 'authorization', 'document_line', 'document_disclaimer',
  'document_revision', 'document_attachment', 'job_attachment',
  'job_assignment_request', 'job_visit_assignment', 'job_labor',
  'job_internal_note', 'job_status_event', 'payment_allocation',
  // A payment edit-audit row has its own immutable UUID and must be listed
  // separately from the payment; never silently classify it as a transaction.
  'payment_edit_audit',
  'expense_allocation', 'payroll_allocation', 'expense_attachment', 'receipt_item',
  'appointment_request', 'conversation', 'conversation_member', 'message',
  'message_attachment', 'activity_event', 'notification', 'kiosk_registration',
  'legacy_link', 'import_row', 'import_issue',
};
const _compositeKeys = {
  'finding_attachment_link': {'business_id', 'note_id', 'attachment_id'},
  'sales_estimate_link': {'business_id', 'estimate_id'},
  'sales_receipt_link': {'business_id', 'sales_document_line_id', 'receipt_item_id'},
  'receipt_detail': {'business_id', 'transaction_id'},
  'document_restore': {'business_id', 'document_id'},
};
const _operationNamespaces = {
  'quick_invoice', 'standalone_estimate', 'financial_transaction', 'kiosk_checkin', 'sync', 'invoice_payment',
  'appointment_create', 'appointment_edit', 'appointment_cancel',
  'appointment_delete', 'appointment_reassign',
};
bool validDeletionV3Entity(Object? kind, Object? id, String businessId) {
  if (deletionV3UuidKinds.contains(kind)) return isDeletionV3Id(id);
  if (id is! String) return false;
  if (kind == 'operation') {
    final split = id.indexOf('/');
    return split > 0 && _operationNamespaces.contains(id.substring(0, split)) &&
        id.length > split + 1 && id.length - split - 1 <= 160 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(id);
  }
  if (kind == 'legacy_photo_map' || kind == 'legacy_stage') {
    if (id.length > 8192) return false;
    try {
      final value = jsonDecode(id);
      final keys = kind == 'legacy_photo_map'
          ? {'business_id', 'source_record_key'}
          : {'business_id', 'batch_tag', 'source_system', 'record_type', 'source_key'};
      return value is Map && value.length == keys.length && keys.every(value.containsKey) &&
          value.values.every((v) => v is String) && value['business_id'] == businessId;
    } catch (_) {
      return false;
    }
  }
  final keys = _compositeKeys[kind];
  if (keys == null) return false;
  try {
    final value = jsonDecode(id);
    return value is Map && value.length == keys.length &&
        keys.every(value.containsKey) && value.values.every(isDeletionV3Id) &&
        value['business_id'] == businessId;
  } catch (_) {
    return false;
  }
}

/// Defensive copies bind consent to what was actually displayed.
class JobDeletionV3Preview {
  JobDeletionV3Preview(Map<String, dynamic> value, {this.fromCache = false})
      : _json = deletionV3Canonical(value);
  final String _json;
  final bool fromCache;
  Map<String, dynamic> get snapshot => Map<String, dynamic>.from(jsonDecode(_json) as Map);
  bool get canDelete => snapshot['can_delete'] == true;
  Map<String, dynamic> get confirmation => Map<String, dynamic>.from(snapshot['confirmation'] as Map);
}

/// A new protocol is mandatory: v2 financial-history exemptions never imply
/// consent to permanently delete payments or estimates.
void validateDeletionV3Confirmation(Map<String, dynamic> value,
    String businessId, String jobId, String actorId) {
  const keys = {'schema_version', 'protocol_version', 'business_id', 'job_id',
    'actor_id', 'scope', 'preview_id', 'issued_at', 'expires_at', 'graph_hash', 'deleted_entities'};
  if (value.length != keys.length || !keys.every(value.containsKey)) {
    throw const FormatException('Confirmation must contain only minimal consent fields.');
  }
  final entities = value['deleted_entities'];
  if (value['schema_version'] != 3 ||
      value['protocol_version'] != ownerDeletionV3Protocol ||
      value['scope'] != 'permanent-full-job' || !isDeletionV3Id(value['preview_id']) ||
      value['issued_at'] is! String || value['expires_at'] is! String ||
      DateTime.tryParse('${value['issued_at']}') == null ||
      DateTime.tryParse('${value['expires_at']}') == null ||
      !isDeletionV3Id(businessId) || !isDeletionV3Id(jobId) || !isDeletionV3Id(actorId) ||
      value['business_id'] != businessId || value['job_id'] != jobId ||
      value['actor_id'] != actorId ||
      value['graph_hash'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['graph_hash'] as String) ||
      entities is! List || entities.isEmpty) {
    throw const FormatException('Unverified deletion confirmation.');
  }
  final issued = DateTime.parse(value['issued_at'] as String);
  final expires = DateTime.parse(value['expires_at'] as String);
  if (!expires.isAfter(issued) || expires.difference(issued) > const Duration(hours: 24) || entities.length > 1000) {
    throw const FormatException('Invalid deletion consent lifetime or size.');
  }
  final entityKeys = <String>{};
  for (final entity in entities) {
    if (entity is! Map || entity.length != 2 ||
        entity['entity_kind'] is! String ||
        !validDeletionV3Entity(entity['entity_kind'], entity['entity_id'], businessId) ||
        !entityKeys.add('${entity['entity_kind']}:${entity['entity_id']}')) {
      throw const FormatException('Unverified deletion inventory.');
    }
  }
  if (!entityKeys.contains('job:$jobId')) {
    throw const FormatException('Deletion inventory does not include the Job.');
  }
}

void validateDeletionV3Preview(Map<String, dynamic> value,
    String businessId, String jobId, String actorId) {
  final confirmation = value['confirmation'];
  if (value['schema_version'] != 3 ||
      value['protocol_version'] != ownerDeletionV3Protocol ||
      value['business_id'] != businessId || value['job_id'] != jobId ||
      value['actor_id'] != actorId || value['inventory_complete'] is! bool ||
      value['write_fences_verified'] is! bool || value['can_delete'] is! bool ||
      value['blocked_reasons'] is! List) {
    throw const FormatException('Unverified deletion preview.');
  }
  if (value['can_delete'] == false && confirmation == null) {
    for (final category in ['invoices', 'estimates', 'payments', 'related_records']) {
      if (value[category] is! List) {
        throw const FormatException('Incomplete blocked deletion preview.');
      }
    }
    return;
  }
  if (confirmation is! Map || value['inventory_complete'] != true || value['write_fences_verified'] != true) {
    throw const FormatException('Missing verified confirmation.');
  }
  final confirmed = Map<String, dynamic>.from(confirmation);
  validateDeletionV3Confirmation(confirmed, businessId, jobId, actorId);
  if (value['graph_hash'] != confirmed['graph_hash'] ||
      deletionV3Canonical(value['deleted_entities']) !=
          deletionV3Canonical(confirmed['deleted_entities'])) {
    throw const FormatException('Deletion preview and confirmation differ.');
  }
  final displayed = <String>{'job:$jobId'};
  final allowed = (confirmed['deleted_entities'] as List)
      .map((raw) => '${raw['entity_kind']}:${raw['entity_id']}').toSet();
  for (final category in ['invoices', 'estimates', 'payments', 'related_records']) {
    final items = value[category];
    if (items is! List) throw const FormatException('Incomplete deletion preview.');
    for (final item in items) {
      if (item is! Map || item['display_label'] is! String ||
          (item['display_label'] as String).trim().isEmpty ||
          item['version'] == null ||
          !allowed.contains('${item['entity_kind']}:${item['entity_id']}') ||
          !displayed.add('${item['entity_kind']}:${item['entity_id']}')) {
        throw const FormatException('Unverified displayed deletion item.');
      }
      final kind = item['entity_kind'];
      if ((category == 'invoices' && kind != 'invoice') ||
          (category == 'estimates' && kind != 'estimate') ||
          (category == 'payments' && !const ['payment', 'transaction'].contains(kind)) ||
          (category == 'related_records' && const ['job', 'invoice', 'estimate', 'payment', 'transaction'].contains(kind)) ||
          (const ['invoices', 'estimates'].contains(category) &&
              (!item.containsKey('number') ||
                  (item['number'] != null && (item['number'] is! String || (item['number'] as String).isEmpty)) ||
                  (item['number'] == null && !('${item['display_label']}'.toLowerCase().contains('unnumbered')))))) {
        throw const FormatException('Deletion item is in the wrong display category.');
      }
      if (category == 'payments' &&
          (item['amount'] is! String ||
              !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(item['amount'] as String) ||
              item['currency'] is! String || (item['currency'] as String).trim().isEmpty ||
              item['method_label'] is! String ||
              (item['method_label'] as String).trim().isEmpty)) {
        throw const FormatException('Payment amount or method is missing.');
      }
    }
  }
  if (displayed.length != allowed.length || !displayed.containsAll(allowed)) {
    throw const FormatException('Some selected records are not displayed.');
  }
  if (value['can_delete'] == true && (value['blocked_reasons'] as List).isNotEmpty) {
    throw const FormatException('Blocked deletion cannot be confirmed.');
  }
}

void validateDeletionV3Receipt(Map<String, dynamic> receipt,
    Map<String, dynamic> confirmation, String operationId) {
  const keys = {'schema_version', 'protocol_version', 'business_id', 'job_id',
    'actor_id', 'operation_id', 'graph_hash', 'deleted_entities', 'status',
    'storage_cleanup', 'status_version', 'committed_at', 'cleanup_completed_at'};
  if (receipt.length != keys.length || !keys.every(receipt.containsKey)) {
    throw const FormatException('Receipt must contain only minimal deletion fields.');
  }
  if (receipt['schema_version'] != 3 ||
      receipt['protocol_version'] != ownerDeletionV3Protocol ||
      receipt['business_id'] != confirmation['business_id'] ||
      receipt['job_id'] != confirmation['job_id'] ||
      receipt['actor_id'] != confirmation['actor_id'] ||
      receipt['operation_id'] != operationId ||
      receipt['status_version'] is! int ||
      (receipt['status_version'] as int) < 1 ||
      receipt['committed_at'] is! String ||
      DateTime.tryParse('${receipt['committed_at']}') == null ||
      receipt['graph_hash'] != confirmation['graph_hash'] ||
      deletionV3Canonical(receipt['deleted_entities']) !=
          deletionV3Canonical(confirmation['deleted_entities']) ||
      !const ['deleted', 'purging'].contains(receipt['status']) ||
      !const ['not_required', 'pending', 'failed', 'completed']
          .contains(receipt['storage_cleanup']) ||
      (receipt['status'] == 'deleted' &&
          !const ['not_required', 'completed'].contains(receipt['storage_cleanup'])) ||
      (receipt['status'] == 'purging' &&
          !const ['pending', 'failed'].contains(receipt['storage_cleanup'])) ||
      (receipt['status'] == 'purging' && receipt['cleanup_completed_at'] != null) ||
      (receipt['status'] == 'deleted' && DateTime.tryParse('${receipt['cleanup_completed_at']}') == null)) {
    throw const FormatException('Unverified deletion receipt. Request remains pending.');
  }
}
