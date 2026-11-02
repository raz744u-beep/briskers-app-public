import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

import '../local/briskers_local_database.dart';
import 'local_job_deletion_v3.dart';

/// Staged implementation only. Do not wire into production Job actions.
/// Device-authoritative deletion of a locally present Job. The sync history
/// is not an eligibility requirement. This first adapter supports the local
/// relational graph; ambiguous financial/outbox references are rejected rather
/// than silently orphaned. No network calls are made.
// Even a misconfigured signed release cannot enable synthetic financial erasure.
const _syntheticOwnerDeleteBuild = !kReleaseMode &&
    const bool.fromEnvironment(
        'BRISKERS_SYNTHETIC_BUILD', defaultValue: false);

class LocalJobGraphDelete {
  LocalJobGraphDelete(this.db, {
    Map<String, dynamic>? Function()? ownerIdentityProvider,
  }) : _ownerIdentityProvider = ownerIdentityProvider ??
      // Fail closed until stable Owner enrollment has been reviewed and wired.
      (() => null);
  final BriskersLocalDatabase db;
  final Map<String, dynamic>? Function() _ownerIdentityProvider;

  void _assertOwner(String business, String actorId) {
    final owner = _ownerIdentityProvider();
    if (owner == null || owner['role_code'] != 'owner' ||
        owner['business_id'] != business || owner['actor_id'] != actorId) {
      throw StateError('Unlock the Owner account for this business first.');
    }
  }

  static const _owned = <String, (String, String, String)>{
    'job': ('local_jobs', 'id', 'id'),
    'invoice': ('local_documents', 'id', 'job_id'),
    'estimate': ('local_documents', 'id', 'job_id'),
    'job_visit': ('local_job_visits', 'id', 'job_id'),
    'job_assignment': ('local_job_assignments', 'assignment_id', 'job_id'),
    'pre_inspection': ('local_pre_inspections', 'id', 'job_id'),
    'appointment': ('local_appointments', 'id', 'job_id'),
  };

  Future<List<Map<String, dynamic>>> _rows(
      String table, String business, String field, String value) async {
    // All SQL identifiers are compiled-in constants, never user input.
    final result = await db.customSelect(
      'SELECT * FROM $table WHERE business_id=? AND $field=?',
      variables: [Variable<String>(business), Variable<String>(value)],
    ).get();
    return result.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>> _inventory(String business, String job) async {
    final found = <Map<String, dynamic>>[];
    final root = await _rows('local_jobs', business, 'id', job);
    if (root.length != 1) throw StateError('Job is not present locally.');
    // A local summary is not a complete financial ledger. In particular, a
    // paid/partially-paid server Job may have NO locally cached receipt rows.
    // Never infer safe hard deletion from missing payment cache entries.
    final paymentState =
        root.single['payment_state']?.toString().trim().toLowerCase() ?? '';
    if (paymentState.isNotEmpty &&
        !const {'unpaid', 'none', 'no_payment'}.contains(paymentState)) {
      throw StateError(
          'Job payment status requires authoritative reconciliation before deletion.');
    }
    // Only recognized invoice/estimate kinds can be included in this graph.
    // Any other linked document must fail the entire preview, rather than
    // leave an orphan behind after removing its parent Job.
    for (final document in await _rows(
        'local_documents', business, 'job_id', job)) {
      if (!const {'invoice', 'estimate'}.contains(document['kind'])) {
        throw StateError(
            'An unrecognized linked document requires reconciliation.');
      }
    }
    for (final entry in _owned.entries) {
      final (table, key, field) = entry.value;
      for (final row in await _rows(table, business, field, job)) {
        if (table == 'local_documents' && row['kind'] != entry.key) continue;
        if (table == 'local_documents') {
          // Issued, paid or closed documents may have external payment/audit
          // references absent from this device. This partial implementation
          // must not treat their locally empty payment cache as proof.
          final status = row['status']?.toString().trim().toLowerCase() ?? '';
          final displayStatus =
              row['display_status_code']?.toString().trim().toLowerCase() ?? '';
          const protected = {
            'issued', 'sent', 'paid', 'partially_paid',
            'partial', 'closed', 'complete', 'completed',
            'finalized', 'pending_close',
          };
          if (row['closed_at'] != null ||
              row['converted'] == 1 ||
              row['converted'] == true ||
              protected.contains(status) ||
              protected.contains(displayStatus)) {
            throw StateError(
                'Issued or settled documents require financial reconciliation.');
          }
        }
        found.add({'kind': entry.key, 'table': table,
          'id': row[key], 'label': row['document_number'] ??
            row['job_number'] ?? row['title'] ?? row[key]});
      }
    }
    final inspections = found.where((r) => r['kind'] == 'pre_inspection').toList();
    for (final inspection in inspections) {
      for (final row in await _rows('local_pre_inspection_photos',
          business, 'inspection_id', inspection['id'].toString())) {
        found.add({'kind': 'pre_inspection_photo', 'table': 'local_pre_inspection_photos',
          'id': row['id'], 'label': row['filename'] ?? row['id']});
      }
    }
    final findings = await db.customSelect(
      'SELECT * FROM local_findings WHERE business_id=? AND '
      '(found_job_id=? OR repair_job_id=?)',
      variables: [Variable<String>(business), Variable<String>(job),
        Variable<String>(job)]).get();
    for (final item in findings) {
      final row = item.data;
      if ((row['found_job_id'] != null && row['found_job_id'] != '' &&
           row['found_job_id'] != job) ||
          (row['repair_job_id'] != null && row['repair_job_id'] != '' &&
           row['repair_job_id'] != job)) {
        throw StateError('A finding is shared with another Job. Review it before deleting.');
      }
      found.add({'kind': 'finding', 'table': 'local_findings',
        'id': row['id'], 'label': row['body']});
      for (final photo in await _rows('local_finding_photos',
          business, 'finding_id', row['id'].toString())) {
        found.add({'kind': 'finding_photo', 'table': 'local_finding_photos',
          'id': photo['id'], 'label': photo['filename'] ?? photo['id']});
      }
    }
    // Financial projections and queued work can contain nested allocations.
    // These must be reconciled explicitly before this relational delete can
    // safely erase their parent. Do not discard unknown transactions.
    final ids = <String>{job, ...found.map((row) => row['id'].toString())};
    final queued = await db.customSelect(
      'SELECT * FROM sync_outbox WHERE business_id=?',
      variables: [Variable<String>(business)]).get();
    for (final row in queued) {
      final data = row.data;
      Object? payload;
      try { payload = jsonDecode(data['payload_json'] as String); }
      catch (_) { throw StateError('Pending changes need local reconciliation.'); }
      if (ids.contains(data['entity_id']) ||
          LocalJobDeletionV3.referencesAny(payload, ids)) {
        // Only tagged, isolated synthetic payments are eligible for this test.
        // Production financial entries continue to require reviewed handling.
        if (_syntheticOwnerDeleteBuild &&
            data['entity_type'] == 'invoice_payment_received' &&
            data['state'] == 'pending' && data['attempt_count'] == 0 &&
            data['last_attempt_at'] == null &&
            payload is Map && payload['synthetic_test_only'] == true &&
            ids.contains(payload['invoice_id']) &&
            payload['operation_id'] is String) {
          found.add({'kind': 'payment', 'table': 'sync_outbox',
            'id': payload['operation_id'],
            'outbox_id': data['id'],
            'label': 'FAKE payment • ${((payload['amount_cents'] as num) / 100).toStringAsFixed(2)} • ${payload['method_name']}'});
          continue;
        }
        throw StateError('This Job has pending local edits or payments. '
          'Resolve those linked changes before deletion.');
      }
    }
    final cache = await db.customSelect(
      'SELECT * FROM local_financial_cache WHERE business_id=?',
      variables: [Variable<String>(business)]).get();
    for (final row in cache) {
      final data = row.data;
      Object? payload;
      try { payload = jsonDecode(data['payload_json'] as String); }
      catch (_) { throw StateError('Financial cache needs review before deletion.'); }
      if (ids.any((id) => data['cache_key'].toString().contains(id)) ||
          LocalJobDeletionV3.referencesAny(payload, ids)) {
        if (_syntheticOwnerDeleteBuild && payload is Map &&
            payload['synthetic_test_only'] == true &&
            payload['job_id'] == job &&
            data['cache_key'] == 'synthetic_payment_audit:$job') {
          found.add({'kind': 'payment_edit_audit', 'table': 'local_financial_cache',
            'id': data['cache_key'], 'label': 'FAKE payment edit audit'});
          continue;
        }
        throw StateError('Linked financial records need review before deletion.');
      }
    }
    return found;
  }

  Future<List<Map<String, dynamic>>> preview({
    required String businessId, required String jobId,
    required String actorId,
  }) async {
    _assertOwner(businessId, actorId);
    await LocalJobDeletionV3.ensureSchema(db);
    return db.transaction(() async => _inventory(businessId, jobId));
  }

  Future<void> confirm({
    required String businessId, required String jobId,
    required String actorId,
    required List<Map<String, dynamic>> reviewed,
  }) async {
    _assertOwner(businessId, actorId);
    await LocalJobDeletionV3.ensureSchema(db);
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    final operation = '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
    await db.transaction(() async {
      _assertOwner(businessId, actorId);
      final current = await _inventory(businessId, jobId);
      // Only exact identities and types are authoritative for a reviewed graph.
      String fingerprint(List<Map<String, dynamic>> rows) =>
          (rows.map((r) => jsonEncode([r['kind'], r['id'], r['label']])).toList()..sort()).join('|');
      if (fingerprint(current) != fingerprint(reviewed)) {
        throw StateError('Linked records changed. Review Delete Job again.');
      }
      _assertOwner(businessId, actorId);
      // Permanent local tombstones are committed in the SAME transaction as
      // deletion. Sync can propagate them later, without server approval.
      for (final entry in current) {
        await db.customStatement(
          'INSERT INTO local_offline_job_purge_entities '
          '(business_id,job_id,operation_id,entity_kind,entity_id) VALUES (?,?,?,?,?)',
          [businessId, jobId, operation, entry['kind'], entry['id']]);
      }
      for (final entry in current.reversed) {
        final kind = entry['kind'] as String;
        final table = entry['table'] as String;
        if (kind == 'payment') {
          await db.customStatement('DELETE FROM sync_outbox '
            'WHERE business_id=? AND id=? AND state=? AND attempt_count=0',
            [businessId, entry['outbox_id'], 'pending']);
        } else if (kind == 'payment_edit_audit') {
          await db.customStatement('DELETE FROM local_financial_cache '
            'WHERE business_id=? AND cache_key=?',
            [businessId, entry['id']]);
        } else {
          final field = _owned[kind]?.$2 ?? 'id';
          await db.customStatement(
            'DELETE FROM $table WHERE business_id=? AND $field=?',
            [businessId, entry['id']]);
        }
      }
      // An Owner switch mid-transaction must roll back both data removals
      // and the corresponding tombstones; never commit half a deletion.
      _assertOwner(businessId, actorId);
    });
    LocalJobDeletionV3.notifyLocalPurge(db, businessId, jobId);
  }
}
