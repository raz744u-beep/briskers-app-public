import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';

/// Removal from a server feed must never acknowledge an unrelated local write.
/// Keep uncertain work recoverable and leave the pull cursor unchanged for retry.
class LocalCleanupSafety {
  static bool referencesAny(Object? value, Set<String> ids) {
    if (value is String) return ids.contains(value);
    if (value is List) return value.any((child) => referencesAny(child, ids));
    if (value is Map) return value.values.any((child) => referencesAny(child, ids));
    return false;
  }

  static Future<void> requireNoQueuedReferences(
    BriskersLocalDatabase database, String businessId, Set<String> ids,
  ) async {
    final queue = await database.customSelect(
      'SELECT entity_id,payload_json FROM sync_outbox WHERE business_id=?',
      variables: [Variable<String>(businessId)],
    ).get();
    for (final row in queue) {
      Object? payload;
      try {
        payload = jsonDecode(row.read<String>('payload_json'));
        if (payload is! Map) throw const FormatException('Unknown queued payload');
      } catch (_) {
        throw StateError('A queued operation cannot be verified. Resolve '
            'synchronization before removing server-deleted records.');
      }
      if (ids.contains(row.read<String>('entity_id')) || referencesAny(payload, ids)) {
        throw StateError('A server-deleted record still has local edits or '
            'payments. The queue has been preserved for reconciliation.');
      }
    }
  }

  static Future<void> requireDocumentsRemovable(
    BriskersLocalDatabase database, String businessId, Set<String> documentIds,
  ) async {
    if (documentIds.isEmpty) return;
    await requireNoQueuedReferences(database, businessId, documentIds);
    for (final id in documentIds) {
      final rows = await database.customSelect(
        'SELECT sync_state FROM local_documents WHERE business_id=? AND id=?',
        variables: [Variable<String>(businessId), Variable<String>(id)],
      ).get();
      if (rows.any((row) => row.read<String>('sync_state') != 'synced')) {
        throw StateError('A server-deleted document has local changes. '
            'They have been preserved for reconciliation.');
      }
    }
  }

  static Future<void> requireJobRemovable(
    BriskersLocalDatabase database, String businessId, String jobId,
  ) async {
    final variables = [Variable<String>(businessId), Variable<String>(jobId)];
    final ids = <String>{jobId};
    for (final table in const ['local_documents', 'local_job_visits', 'local_pre_inspections']) {
      final rows = await database.customSelect(
        'SELECT id,sync_state FROM $table WHERE business_id=? AND job_id=?',
        variables: variables,
      ).get();
      for (final row in rows) {
        ids.add(row.read<String>('id'));
        if (row.read<String>('sync_state') != 'synced') {
          throw StateError('A server-deleted Job has unsynchronized local '
              'work. It has been preserved for reconciliation.');
        }
      }
    }
    final job = await database.customSelect(
      'SELECT sync_state FROM local_jobs WHERE business_id=? AND id=?',
      variables: variables,
    ).get();
    if (job.any((row) => row.read<String>('sync_state') != 'synced')) {
      throw StateError('The server-deleted Job has pending local edits.');
    }
    final findings = await database.customSelect(
      'SELECT id,sync_state FROM local_findings WHERE business_id=? '
      'AND (found_job_id=? OR repair_job_id=?)',
      variables: [...variables, Variable<String>(jobId)],
    ).get();
    for (final row in findings) {
      ids.add(row.read<String>('id'));
      if (row.read<String>('sync_state') != 'synced') {
        throw StateError('The server-deleted Job has pending findings.');
      }
    }
    await requireNoQueuedReferences(database, businessId, ids);
    final photos = await database.customSelect('''
      SELECT p.id FROM local_pre_inspection_photos p
      JOIN local_pre_inspections i ON i.id=p.inspection_id
        AND i.business_id=p.business_id
      WHERE i.business_id=? AND i.job_id=?
        AND (p.upload_state IS NOT 'synced' OR
             COALESCE(p.local_file_path,'')<>'')
      UNION ALL
      SELECT p.id FROM local_finding_photos p
      JOIN local_findings f ON f.id=p.finding_id AND f.business_id=p.business_id
      WHERE f.business_id=? AND (f.found_job_id=? OR f.repair_job_id=?)
        AND (p.upload_state IS NOT 'synced' OR
             COALESCE(p.local_file_path,'')<>'')
    ''', variables: [...variables, ...variables, Variable<String>(jobId)]).get();
    if (photos.isNotEmpty) {
      throw StateError('The server-deleted Job still has local photos. '
          'Back them up and reconcile them before removing its cache.');
    }
  }
}
