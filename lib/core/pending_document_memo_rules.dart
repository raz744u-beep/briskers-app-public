import 'dart:convert';

/// Display-only projection of queued note edits. This never acknowledges or
/// retires an outbox row, changes server versions, or changes financial fields.
Map<String, dynamic> projectPendingDocumentMemo(
  Map<String, dynamic> detail,
  Iterable<Map<String, dynamic>> queued, {
  required String businessId,
  required String documentId,
}) {
  final detailId = detail['id']?.toString();
  if (detailId != null && detailId.isNotEmpty && detailId != documentId) {
    throw StateError('Cannot project a note onto a different document.');
  }
  final detailBusiness = detail['business_id']?.toString();
  if (detailBusiness != null &&
      detailBusiness.isNotEmpty &&
      detailBusiness != businessId) {
    throw StateError('Cannot project a note from a different business.');
  }
  final result = Map<String, dynamic>.from(detail);
  final previouslyProjected = result.remove('_local_pending_memo') == true;
  final serverHadMemo = result.remove('_pending_memo_server_had_value') == true;
  final serverMemo = result.remove('_pending_memo_server_value');
  result.remove('_local_pending_memo_queue_id');
  result.remove('_local_pending_memo_state');
  // Persisted projections retain their underlying server value. Applying the
  // helper again must not mistake the displayed local text for server truth.
  if (previouslyProjected) {
    if (serverHadMemo) {
      result['memo'] = serverMemo;
    } else {
      result.remove('memo');
    }
  }
  final active = queued
      .where(
        (row) =>
            row['business_id'] == businessId &&
            row['entity_id'] == documentId &&
            row['entity_type'] == 'document_edit' &&
            row['operation'] == 'memo' &&
            const {'pending', 'inflight', 'conflict'}.contains(row['state']),
      )
      .toList();
  if (active.isEmpty) return result;
  int rank(Map<String, dynamic> row) {
    final value = int.tryParse(row['id']?.toString() ?? '');
    if (value == null) {
      throw StateError('The saved local note has an invalid queue identity.');
    }
    return value;
  }

  active.sort((a, b) => rank(a).compareTo(rank(b)));
  final latest = active.last;
  final decoded = jsonDecode(latest['payload_json']?.toString() ?? '');
  if (decoded is! Map ||
      !decoded.containsKey('memo') ||
      (decoded['memo'] != null && decoded['memo'] is! String)) {
    throw StateError(
      'The saved local note could not be read. Keep it queued for review.',
    );
  }
  return <String, dynamic>{
    ...result,
    '_pending_memo_server_had_value': result.containsKey('memo'),
    '_pending_memo_server_value': result['memo'],
    'memo': decoded['memo'],
    '_local_pending_memo': true,
    '_local_pending_memo_queue_id': rank(latest),
    '_local_pending_memo_state': latest['state'],
  };
}
