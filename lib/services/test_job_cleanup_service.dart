import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'document_index_sync_service.dart';
import 'job_sync_service.dart';
import 'local_document_detail_cache.dart';
import 'test_job_cleanup_gateway.dart';
import 'test_job_cleanup_policy.dart';

class TestJobCleanupReceipt {
  const TestJobCleanupReceipt({required this.auditId, this.cacheWarning});
  final String auditId;
  final String? cacheWarning;
}

class TestJobCleanupService {
  TestJobCleanupService({
    TestJobCleanupGateway gateway = const TestJobCleanupGateway(),
    BriskersLocalDatabase? database,
    LocalDocumentDetailCache cache = const LocalDocumentDetailCache(),
    DateTime Function()? now,
  }) : _gateway = gateway,
       _database = database ?? localDatabase,
       _cache = cache,
       _now = now ?? DateTime.now;

  final TestJobCleanupGateway _gateway;
  final BriskersLocalDatabase _database;
  final LocalDocumentDetailCache _cache;
  final DateTime Function() _now;
  bool _executing = false;

  Future<void> verifyOwner(String businessId, String roleCode) async {
    TestJobCleanupPolicy.requireOwner(roleCode);
    await _gateway.verifyOwner(businessId);
  }

  /// Read-only local evidence remains available on a deliberately offline
  /// phone. Cached role gates visibility; it never authorizes deletion.
  Future<List<Map<String, dynamic>>> pendingLocalDocuments(
    String businessId, {
    required String roleCode,
  }) async {
    TestJobCleanupPolicy.requireOwner(roleCode);
    final rows = await _database.customSelect(
      """SELECT d.id,d.kind,d.job_id,d.total,d.sync_state,
                (SELECT COUNT(*) FROM sync_outbox o
                 WHERE o.business_id=d.business_id AND o.entity_id=d.id) AS queued
         FROM local_documents d WHERE d.business_id=?
           AND (d.sync_state IS NOT 'synced' OR EXISTS(
             SELECT 1 FROM sync_outbox o WHERE o.business_id=d.business_id
               AND o.entity_id=d.id))
         ORDER BY d.created_at DESC LIMIT 100""",
      variables: [Variable<String>(businessId)],
    ).get();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = row.read<String>('id');
      final snapshot = await _cache.load(businessId, id);
      result.add({
        'id': id, 'kind': row.read<String>('kind'),
        'total': row.read<double>('total'), 'queued': row.read<int>('queued'),
        'sync_state': row.read<String>('sync_state'),
        'local': id.startsWith('local-invoice-') || id.startsWith('local-estimate-'),
        'customer': snapshot?['customer_name']?.toString() ?? 'Unknown customer',
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> jobs(
    String businessId, {
    required String roleCode,
  }) async {
    await verifyOwner(businessId, roleCode);
    return _gateway.jobs(businessId);
  }

  Future<TestJobCleanupPlan> preview(
    String businessId, String jobId, {
    required String roleCode,
  }) async {
    await verifyOwner(businessId, roleCode);
    final plan = TestJobCleanupPlan.fromJson(
      await _gateway.preview(businessId, jobId),
      businessId: businessId, jobId: jobId, receivedAt: _now(),
    );
    return plan.withLocalBlockers(await localBlockers(plan));
  }

  /// Be deliberately more conservative than the server: any unsynchronized
  /// business operation may refer to this Job indirectly through its payload.
  /// This includes attempted uploads, conflicts and unacknowledged receipts.
  Future<List<String>> localBlockers(TestJobCleanupPlan plan) async {
    final reasons = <String>[];
    final businessId = plan.businessId;
    Future<int> count(String sql, List<String> values) async {
      final row = await _database.customSelect(sql,
        variables: values.map((value) => Variable<String>(value)).toList(),
      ).getSingle();
      return row.read<int>('n');
    }
    if (await count('SELECT COUNT(*) AS n FROM sync_outbox '
        'WHERE business_id=?', [businessId]) != 0) {
      reasons.add('This device has queued or uncertain synchronization. '
          'Synchronize and resolve every pending operation first.');
    }
    for (final table in const [
      'local_jobs', 'local_documents', 'local_job_visits',
      'local_pre_inspections', 'local_findings', 'local_appointments',
      'local_customers', 'local_vehicles',
    ]) {
      if (await count('SELECT COUNT(*) AS n FROM $table '
          "WHERE business_id=? AND sync_state IS NOT 'synced'",
          [businessId]) != 0) {
        reasons.add('This device has unsynchronized records. Synchronize first.');
        break;
      }
    }
    for (final table in const [
      'local_pre_inspection_photos', 'local_finding_photos',
    ]) {
      if (await count('SELECT COUNT(*) AS n FROM $table '
          "WHERE business_id=? AND upload_state IS NOT 'synced'",
          [businessId]) != 0) {
        reasons.add('This device has pending or uncertain photo uploads.');
        break;
      }
    }
    final refs = await count('''
      SELECT
        (SELECT COUNT(*) FROM local_appointments
         WHERE business_id=? AND job_id=?) +
        (SELECT COUNT(*) FROM local_pre_inspections
         WHERE business_id=? AND job_id=?) +
        (SELECT COUNT(*) FROM local_job_assignments
         WHERE business_id=? AND job_id=?) +
        (SELECT COUNT(*) FROM local_findings
         WHERE business_id=? AND (found_job_id=? OR repair_job_id=?)) AS n
    ''', [businessId, plan.jobId, businessId, plan.jobId,
      businessId, plan.jobId, businessId, plan.jobId, plan.jobId]);
    if (refs != 0) {
      reasons.add('Local service, appointment, assignment or finding references '
          'need reconciliation before cleanup.');
    }
    final documents = await _database.customSelect(
      'SELECT id FROM local_documents WHERE business_id=? AND job_id=?',
      variables: [Variable<String>(businessId), Variable<String>(plan.jobId)],
    ).get();
    if (documents.any((row) => !plan.documentIds.contains(row.read<String>('id')))) {
      reasons.add('Local and server document links disagree. Synchronize first.');
    }
    for (final id in plan.documentIds) {
      final snapshot = await _cache.load(businessId, id);
      if (snapshot == null) continue;
      final unsafe = TestJobCleanupPolicy.hasPendingSnapshot(snapshot);
      if (unsafe) {
        reasons.add('A linked document has local edits or uncertain payment '
            'history. Reconcile it before cleanup.');
        break;
      }
    }
    return reasons.toSet().toList();
  }

  Future<TestJobCleanupReceipt> execute(
    TestJobCleanupPlan plan, {
    required String roleCode,
    required String confirmation,
  }) async {
    if (_executing) throw StateError('Cleanup is already in progress.');
    TestJobCleanupPolicy.requireExecutable(plan,
      roleCode: roleCode, confirmation: confirmation, now: _now());
    _executing = true;
    Map<String, dynamic>? committed;
    final snapshots = <String, Map<String, dynamic>?>{};
    try {
      await verifyOwner(plan.businessId, roleCode);
      // Hold the device transaction across the final check and network call.
      // Other local writers cannot enqueue new work between these steps.
      await _database.transaction(() async {
        final reasons = await localBlockers(plan);
        if (reasons.isNotEmpty) throw StateError(reasons.join('\n'));
        for (final id in plan.documentIds) {
          final snapshot = await _cache.load(plan.businessId, id);
          if (TestJobCleanupPolicy.hasPendingSnapshot(snapshot)) {
            throw StateError('A document changed after the local safety check. Preview again.');
          }
          snapshots[id] = snapshot;
        }
        TestJobCleanupPolicy.requireExecutable(plan,
          roleCode: roleCode, confirmation: confirmation, now: _now());
        final result = await _gateway.execute(plan.businessId, plan.jobId,
          fingerprint: plan.fingerprint, confirmation: confirmation);
        _validateReceipt(plan, result);
        committed = result;
        for (final id in plan.documentIds) {
          await _database.customStatement(
            "DELETE FROM local_documents WHERE business_id=? AND id=? "
            "AND job_id=? AND sync_state='synced'",
            [plan.businessId, id, plan.jobId],
          );
        }
        await _database.customStatement(
          "DELETE FROM local_job_visits WHERE business_id=? AND job_id=? "
          "AND sync_state='synced'", [plan.businessId, plan.jobId],
        );
        await _database.customStatement(
          "DELETE FROM local_jobs WHERE business_id=? AND id=? "
          "AND sync_state='synced'", [plan.businessId, plan.jobId],
        );
      });
      String? warning;
      try {
        for (final id in plan.documentIds) {
          if (!await _cache.removeIfUnchanged(plan.businessId, id, snapshots[id])) {
            throw StateError('Document changed during cleanup; latest snapshot kept.');
          }
        }
      } catch (_) {
        warning = 'Cleanup succeeded on the server. Synchronize this device '
            'to finish refreshing its document cache.';
      }
      JobSyncService.notifyCleanup(plan.businessId);
      DocumentIndexSyncService.notifyCleanup(plan.businessId);
      return TestJobCleanupReceipt(
        auditId: committed!['audit_id'] as String, cacheWarning: warning,
      );
    } catch (_) {
      if (committed != null) {
        return TestJobCleanupReceipt(
          auditId: committed!['audit_id'] as String,
          cacheWarning: 'Cleanup succeeded on the server. Synchronize this '
              'device before continuing; its cache could not be refreshed.',
        );
      }
      rethrow;
    } finally {
      _executing = false;
    }
  }

  void _validateReceipt(TestJobCleanupPlan plan, Map<String, dynamic> result) {
    final rawIds = result['deleted_document_ids'];
    if (result['schema_version'] != 1 ||
        result['business_id'] != plan.businessId ||
        result['job_id'] != plan.jobId ||
        result['deleted_job_id'] != plan.jobId ||
        result['audit_id'] is! String ||
        (result['audit_id'] as String).isEmpty || rawIds is! List ||
        rawIds.any((id) => id is! String) ||
        rawIds.length != plan.documentIds.length ||
        rawIds.toSet().length != rawIds.length ||
        !rawIds.toSet().containsAll(plan.documentIds)) {
      throw StateError('Server cleanup result is uncertain. Refresh the '
          'preview and synchronize before taking any further action.');
    }
  }
}
