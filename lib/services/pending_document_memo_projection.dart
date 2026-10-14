import 'package:drift/drift.dart';

import '../core/pending_document_memo_rules.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Rebuilds locally edited invoice/estimate notes after stale reads or restart.
/// A failed read propagates: it must not silently present stale text as saved.
class PendingDocumentMemoProjection {
  PendingDocumentMemoProjection({BriskersLocalDatabase? database})
    : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<Map<String, dynamic>> project(
    String businessId,
    String documentId,
    Map<String, dynamic> detail,
  ) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT id,business_id,entity_type,entity_id,operation,payload_json,state
      FROM sync_outbox
      WHERE business_id=? AND entity_id=?
        AND entity_type='document_edit' AND operation='memo'
        AND state IN ('pending','inflight','conflict')
      ORDER BY id
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(documentId),
          ],
        )
        .get();
    return projectPendingDocumentMemo(
      detail,
      rows.map((row) => row.data),
      businessId: businessId,
      documentId: documentId,
    );
  }
}
