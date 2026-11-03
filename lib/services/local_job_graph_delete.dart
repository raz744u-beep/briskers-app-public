import 'local_job_retirement.dart';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

import '../local/briskers_local_database.dart';
import 'local_job_deletion_v3.dart';
import 'local_owner_authorization.dart';
import 'local_document_detail_cache.dart';
import 'local_document_sql_store.dart';
import 'local_number_allocator.dart';

/// The regular app uses ownerDirected: authenticated Owner selection, atomic
/// local graph deletion, and no server or financial-status eligibility check.
/// The historical constructor/test adapter is retained for legacy regressions.
// The old synthetic adapter remains unavailable in release builds. The normal
// Owner route accepts a protected grant, never a synthetic role-map override.
const _syntheticOwnerDeleteBuild = !kReleaseMode &&
    bool.fromEnvironment(
        'BRISKERS_SYNTHETIC_BUILD', defaultValue: false);

class LocalJobGraphDelete {
  final bool _ownerDirected;
  LocalJobGraphDelete.ownerDirected(this.db, {required LocalOwnerGrant ownerGrant})
      : _ownerGrant = ownerGrant, _testOwnerIdentityProvider = null, _ownerDirected = true;

  LocalJobGraphDelete(this.db, {LocalOwnerGrant? ownerGrant})
      : _ownerGrant = ownerGrant, _testOwnerIdentityProvider = null, _ownerDirected = false;

  /// Synthetic unit-test seam. Release builds never accept a role-map provider.
  LocalJobGraphDelete.forTesting(this.db, {
    required Map<String, dynamic>? Function() ownerIdentityProvider,
  }) : _ownerGrant = null, _testOwnerIdentityProvider = ownerIdentityProvider, _ownerDirected = false {
    if (kReleaseMode) throw StateError('Test authorization is unavailable in release builds.');
  }
  final BriskersLocalDatabase db;
  final LocalOwnerGrant? _ownerGrant;
  final Map<String, dynamic>? Function()? _testOwnerIdentityProvider;

  void _assertOwner(String business, String actorId) {
    if (_ownerGrant != null) {
      _ownerGrant.assertValid(business, actorId);
      return;
    }
    final owner = kReleaseMode ? null : _testOwnerIdentityProvider?.call();
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

  // Capture every stored column, including amounts, ownership and revisions.
  // A display label is not a concurrency token. Keep a detached string so the
  // reviewed snapshot cannot change when the database row changes.
  static String _snapshot(Map<String, dynamic> row) {
    final columns = row.keys.toList()..sort();
    return jsonEncode({for (final column in columns) column: row[column]});
  }

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
    _rejectPublishedProductionRow(root.single);
    // A local summary is not a complete financial ledger. In particular, a
    // paid/partially-paid server Job may have NO locally cached receipt rows.
    // Never infer safe hard deletion from missing payment cache entries.
    final paymentState =
        root.single['payment_state']?.toString().trim().toLowerCase() ?? '';
    if (!_ownerDirected && paymentState.isNotEmpty &&
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
        _rejectPublishedProductionRow(row);
        if (!_ownerDirected && table == 'local_documents') {
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
          'id': row[key], 'snapshot': _snapshot(row), 'label': row['document_number'] ??
            row['job_number'] ?? row['title'] ?? row[key]});
      }
    }
    final inspections = found.where((r) => r['kind'] == 'pre_inspection').toList();
    for (final inspection in inspections) {
      for (final row in await _rows('local_pre_inspection_photos',
          business, 'inspection_id', inspection['id'].toString())) {
        _rejectPublishedProductionRow(row);
        found.add({'kind': 'pre_inspection_photo', 'table': 'local_pre_inspection_photos',
          'id': row['id'], 'snapshot': _snapshot(row), 'label': row['filename'] ?? row['id']});
      }
    }
    final findings = await db.customSelect(
      'SELECT * FROM local_findings WHERE business_id=? AND '
      '(found_job_id=? OR repair_job_id=?)',
      variables: [Variable<String>(business), Variable<String>(job),
        Variable<String>(job)]).get();
    for (final item in findings) {
      final row = item.data;
      _rejectPublishedProductionRow(row);
      if ((row['found_job_id'] != null && row['found_job_id'] != '' &&
           row['found_job_id'] != job) ||
          (row['repair_job_id'] != null && row['repair_job_id'] != '' &&
           row['repair_job_id'] != job)) {
        throw StateError('A finding is shared with another Job. Review it before deleting.');
      }
      found.add({'kind': 'finding', 'table': 'local_findings',
        'id': row['id'], 'snapshot': _snapshot(row), 'label': row['body']});
      for (final photo in await _rows('local_finding_photos',
          business, 'finding_id', row['id'].toString())) {
        _rejectPublishedProductionRow(photo);
        found.add({'kind': 'finding_photo', 'table': 'local_finding_photos',
          'id': photo['id'], 'snapshot': _snapshot(photo), 'label': photo['filename'] ?? photo['id']});
      }
    }
    // Financial projections and queued work can contain nested allocations.
    // These must be reconciled explicitly before this relational delete can
    // safely erase their parent. Do not discard unknown transactions.
    final ids = <String>{job, ...found.map((row) => row['id'].toString())};
    if (_ownerDirected) {
      await LocalDocumentDetailCache.ensureSchema(db);
      for (final document in found.where((r) => r['kind']=='invoice' || r['kind']=='estimate').toList()) {
        final key=LocalDocumentDetailCache.key(business,document['id'].toString());
        final visible=await LocalDocumentDetailCache(database:db).load(business,document['id'].toString());
        if(visible!=null) await LocalDocumentSqlStore.write(db,key,jsonEncode(visible));
        final details=await db.customSelect('SELECT * FROM local_document_details WHERE cache_key=?',
          variables:[Variable<String>(key)]).get();
        for(final detail in details) {
          found.add({'kind':'document_detail','table':'local_document_details','id':key,
            'snapshot':_snapshot(detail.data),'label':'Invoice details, lines and saved payments'});
          void collect(Object? value) {
            if(value is Map) {
              if(value['id'] is String) ids.add(value['id'] as String);
              for(final child in value.values) { collect(child); }
            } else if(value is List) { for(final child in value) { collect(child); } }
          }
          final raw=detail.readNullable<String>('payload_json');
          final body=raw==null ? null : jsonDecode(raw);
          if(body is Map) {
            for(final field in const ['lines','payments','payment_edit_audit','tasks']) { collect(body[field]); }
          }
        }
      }
    }
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
        if (_ownerDirected) {
          void checkLinks(Object? value) {
            if(value is Map) {
              for(final entry in value.entries) {
                if(const {'job_id','provisional_job_id','invoice_id','document_id','target_invoice_id','estimate_id'}.contains(entry.key) &&
                    entry.value is String && (entry.value as String).isNotEmpty && !ids.contains(entry.value)) {
                  throw StateError('A queued operation also belongs to another document or Job. No records were deleted.');
                }
                if(entry.value is Map || entry.value is List) checkLinks(entry.value);
              }
            } else if(value is List) { for(final item in value) { checkLinks(item); } }
          }
          checkLinks(payload);
          found.add({'kind':'queued_operation','table':'sync_outbox','id':'${data['id']}',
            'outbox_id':data['id'],'snapshot':_snapshot(data),
            'label':data['entity_type']=='invoice_payment_received'
              ? 'Payment • ${payload is Map && payload['amount_cents'] is num ? ((payload['amount_cents'] as num)/100).toStringAsFixed(2) : ''}'
              : 'Saved ${data['entity_type']}'});
          continue;
        }
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
            'outbox_id': data['id'], 'snapshot': _snapshot(data),
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
        if (_ownerDirected) {
          final cleaned=_withoutOwned(payload,ids);
          found.add({'kind':'financial_cache','table':'local_financial_cache','id':data['cache_key'],
            'snapshot':_snapshot(data),'replacement':cleaned==null ? null : jsonEncode(cleaned),
            'label':'Linked financial records (${data['cache_key']})'});
          continue;
        }
        if (_syntheticOwnerDeleteBuild && payload is Map &&
            payload['synthetic_test_only'] == true &&
            payload['job_id'] == job &&
            data['cache_key'] == 'synthetic_payment_audit:$job') {
          found.add({'kind': 'payment_edit_audit', 'table': 'local_financial_cache',
            'id': data['cache_key'], 'snapshot': _snapshot(data), 'label': 'FAKE payment edit audit'});
          continue;
        }
        throw StateError('Linked financial records need review before deletion.');
      }
    }
    return found;
  }

  /// A missing local receipt is never evidence that a server row is disposable.
  /// Keep the historical synthetic adapter available only through forTesting;
  /// a real Owner grant cannot override this production financial boundary.
  /// Pending rows still undergo all graph/outbox protections above. This check
  /// alone is NOT proof of unpublished test provenance or permission to wire UI.
  void _rejectPublishedProductionRow(Map<String, dynamic> row) {
    if (_ownerDirected || (_testOwnerIdentityProvider != null && !kReleaseMode)) return;
    if (row['sync_state'] != 'pending' || row['server_updated_at'] != null) {
      throw StateError(
          'Previously synchronized or uncertain records cannot be deleted offline.');
    }
  }

  static Object? _withoutOwned(Object? value,Set<String> ids) {
    if(value is List) {
      return value.map((v)=>_withoutOwned(v,ids)).where((v)=>v!=null).toList();
    }
    if(value is Map) {
      const links={'id','job_id','invoice_id','document_id','payment_id','transaction_id'};
      if(value.entries.any((e)=>links.contains(e.key) && ids.contains(e.value))) return null;
      return {for(final entry in value.entries) entry.key:
        entry.value is Map || entry.value is List ? _withoutOwned(entry.value,ids) : entry.value};
    }
    return value;
  }

  Future<void> _ensureJournal() async {
    await db.customStatement('''CREATE TABLE IF NOT EXISTS local_owner_delete_journal (
      business_id TEXT NOT NULL, job_id TEXT NOT NULL, operation_id TEXT NOT NULL,
      actor_id TEXT NOT NULL, entities_json TEXT NOT NULL,
      state TEXT NOT NULL CHECK(state IN ('awaiting_backend','acknowledged','needs_review')),
      created_at INTEGER NOT NULL,
      PRIMARY KEY(business_id, operation_id), UNIQUE(business_id, job_id))''');
  }

  Future<List<Map<String, dynamic>>> preview({
    required String businessId, required String jobId,
    required String actorId,
  }) async {
    _assertOwner(businessId, actorId);
    await LocalJobDeletionV3.ensureSchema(db);
    return db.transaction(() async {
      _assertOwner(businessId, actorId);
      final inventory = await _inventory(businessId, jobId);
      _assertOwner(businessId, actorId);
      return inventory;
    });
  }

  Future<void> confirm({
    required String businessId, required String jobId,
    required String actorId,
    required List<Map<String, dynamic>> reviewed,
  }) async {
    _assertOwner(businessId, actorId);
    await LocalJobDeletionV3.ensureSchema(db);
    await _ensureJournal();
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    final operation = '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
    await db.transaction(() async {
      _assertOwner(businessId, actorId);
      final current = await _inventory(businessId, jobId);
      // Any stored-column change invalidates the reviewed graph, even when
      // identities and display labels are unchanged.
      String fingerprint(List<Map<String, dynamic>> rows) =>
          (rows.map((r) => jsonEncode([r['kind'], r['id'], r['label'], r['snapshot']])).toList()..sort()).join('|');
      if (fingerprint(current) != fingerprint(reviewed)) {
        throw StateError('Linked records changed. Review Delete Job again.');
      }
      _assertOwner(businessId, actorId);
      if(_ownerDirected) {
        final numbering=LocalNumberAllocator(db);
        for(final kind in current.map((r)=>r['kind']).where((k)=>k=='invoice' || k=='job').toSet()) {
          await numbering.nextNumber(businessId,kind as String);
        }
      }
      // Preserve the original author and operation across restart. This is
      // identity-only sync metadata, not a recovery copy of deleted records.
      // No server path is activated until its reconciliation contract is verified.
      final identities = current.map((row) => {
        'entity_kind': row['kind'], 'entity_id': row['id'],
      }).toList()..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      await db.customStatement(
        'INSERT INTO local_owner_delete_journal '
        '(business_id,job_id,operation_id,actor_id,entities_json,state,created_at) '
        'VALUES (?,?,?,?,?,?,?)',
        [businessId, jobId, operation, actorId, jsonEncode(identities),
          'awaiting_backend', DateTime.now().toUtc().millisecondsSinceEpoch]);
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
        if (kind == 'document_detail') {
          await db.customStatement('INSERT OR IGNORE INTO local_document_detail_deleted VALUES (?)',[entry['id']]);
          await db.customStatement('DELETE FROM local_document_details WHERE cache_key=?',[entry['id']]);
        } else if(kind == 'financial_cache') {
          if(entry['replacement']==null) {
            await db.customStatement('DELETE FROM local_financial_cache WHERE business_id=? AND cache_key=?',
              [businessId,entry['id']]);
          } else {
            await db.customStatement('UPDATE local_financial_cache SET payload_json=? WHERE business_id=? AND cache_key=?',
              [entry['replacement'],businessId,entry['id']]);
          }
        } else if(kind == 'queued_operation') {
          await db.customStatement('DELETE FROM sync_outbox WHERE business_id=? AND id=?',
            [businessId,entry['outbox_id']]);
        } else if (kind == 'payment') {
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
      if(_ownerDirected) {
        final numbering=LocalNumberAllocator(db);
        for(final row in current.where((row)=>row['kind']=='invoice' || row['kind']=='job')) {
          final snapshot=jsonDecode(row['snapshot'] as String) as Map;
          await numbering.release(businessId,row['kind'] as String,row['id'] as String,
            previousNumber:snapshot[row['kind']=='job' ? 'job_number' : 'document_number']);
        }
      }
      // An Owner switch mid-transaction must roll back both data removals
      // and the corresponding tombstones; never commit half a deletion.
      _assertOwner(businessId, actorId);
    });
    LocalJobDeletionV3.notifyLocalPurge(db, businessId, jobId);
    LocalJobRetirement.notify(db,businessId,{jobId});
  }
}
