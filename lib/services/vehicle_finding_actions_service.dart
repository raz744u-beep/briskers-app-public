import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'customer_detail_cache.dart';
import 'local_job_quarantine.dart';

/// Local-first, identity-based state changes shared by both finding entrypoints.
/// Generated invoice notes remain separate from the user's manually typed memo.
class VehicleFindingActionsService {
  VehicleFindingActionsService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
    CustomerDetailCache cache = const CustomerDetailCache(),
  }) : _api = api,
       _database = database ?? localDatabase,
       _cache = cache;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final CustomerDetailCache _cache;
  static final _changes = StreamController<String>.broadcast();
  static Stream<String> get changes => _changes.stream;
  static void notifyChanged(String businessId) => _changes.add(businessId);
  static final Expando<Map<String, Future<void>>> _flushes = Expando();

  Future<Map<String, dynamic>> setInvoiceFlag(
    String businessId,
    Map<String, dynamic> finding,
    bool include, {
    String? customerId,
  }) => _change(businessId, finding, 'invoice', {
    'include_on_invoice': include,
  }, customerId: customerId);
  Future<Map<String, dynamic>> addToJob(
    String businessId,
    Map<String, dynamic> finding,
    String jobId, {
    String? customerId,
  }) => _change(
    businessId,
    finding,
    'add',
    {'status': 'in_job', 'repair_job_id': jobId, 'resolved_at': null},
    jobId: jobId,
    customerId: customerId,
  );
  Future<Map<String, dynamic>> removeFromJob(
    String businessId,
    Map<String, dynamic> finding,
    String jobId, {
    String? customerId,
  }) => _change(
    businessId,
    finding,
    'remove',
    {'status': 'open', 'repair_job_id': null, 'resolved_at': null},
    jobId: jobId,
    customerId: customerId,
  );
  Future<Map<String, dynamic>> resolve(
    String businessId,
    Map<String, dynamic> finding,
    String jobId, {
    String? customerId,
  }) => _change(
    businessId,
    finding,
    'resolve',
    {
      'status': 'resolved',
      // The server stores the resolving Job separately from an In Job link.
      // Do not turn a completed Job into an active repair assignment.
      'resolved_job_id': jobId,
      'include_on_invoice': false,
      'resolved_at': DateTime.now().toUtc().toIso8601String(),
    },
    jobId: jobId,
    customerId: customerId,
  );
  Future<Map<String, dynamic>> reopen(
    String businessId,
    Map<String, dynamic> finding, {
    String? customerId,
  }) => _change(businessId, finding, 'reopen', {
    'status': 'open',
    'repair_job_id': null,
    'resolved_at': null,
  }, customerId: customerId);

  Future<Map<String, dynamic>> _change(
    String businessId,
    Map<String, dynamic> finding,
    String action,
    Map<String, dynamic> patch, {
    String? jobId,
    String? customerId,
  }) async {
    final id = finding['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw StateError('Finding identity is missing. Reopen the vehicle.');
    }
    if (jobId != null && jobId.isEmpty) throw StateError('Choose a Job first.');
    if (await LocalJobQuarantine.isEntityBlocked(_database, businessId, [
      id,
      jobId,
      finding['found_job_id']?.toString(),
      finding['repair_job_id']?.toString(),
    ])) {
      throw StateError(
        'Job access changed. Reopen this finding to verify access.',
      );
    }
    late Map<String, dynamic> updated;
    await _database.transaction(() async {
      final existing = await _database
          .customSelect(
            'SELECT * FROM local_findings WHERE business_id=? AND id=?',
            variables: [Variable<String>(businessId), Variable<String>(id)],
          )
          .getSingleOrNull();
      if (existing == null && id.startsWith('local-finding-')) {
        final queuedCreate = await _database
            .customSelect(
              "SELECT id FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type IN ('finding_create','customer_finding_create') AND state='pending' LIMIT 1",
              variables: [Variable<String>(businessId), Variable<String>(id)],
            )
            .get();
        if (queuedCreate.isEmpty) {
          throw StateError(
            'This finding has synchronized. Reopen it before making another change.',
          );
        }
      }
      final current = <String, dynamic>{
        ...finding,
        if (existing != null) ..._rowMap(existing),
      };
      if (current['sync_state'] == 'conflict') {
        throw StateError(
          'Resolve the sync conflict before changing this finding.',
        );
      }
      if (action == 'add' &&
          current['status'] == 'in_job' &&
          current['repair_job_id'] != jobId) {
        throw StateError('This finding is already assigned to another Job.');
      }
      final relevant = patch.keys.where((key) => key != 'resolved_at');
      if (relevant.every((key) => current[key] == patch[key])) {
        updated = current;
        return;
      }
      updated = {
        ...current,
        ...patch,
        'sync_state': 'pending',
        '_pending_finding_action': true,
      };
      await _database.customStatement(
        '''
        INSERT INTO local_findings(id,business_id,vehicle_id,found_job_id,repair_job_id,body,status,include_on_invoice,created_at,resolved_at,can_edit,can_delete,row_version,sync_state)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'pending')
        ON CONFLICT(id) DO UPDATE SET status=excluded.status, repair_job_id=excluded.repair_job_id,
          include_on_invoice=excluded.include_on_invoice,resolved_at=excluded.resolved_at,sync_state='pending'
      ''',
        [
          id,
          businessId,
          current['vehicle_id'] ?? current['_vehicle_id'],
          current['found_job_id'],
          updated['repair_job_id'],
          current['body'] ?? '',
          updated['status'] ?? 'open',
          updated['include_on_invoice'] == true ? 1 : 0,
          _unix(current['created_at']),
          _unix(updated['resolved_at']),
          current['can_edit'] == false ? 0 : 1,
          current['can_delete'] == true ? 1 : 0,
          current['row_version'],
        ],
      );
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state,attempt_count,created_at)
        VALUES(?,'finding_action',?,?,?,'pending',0,?)
      ''',
        [
          businessId,
          id,
          action,
          jsonEncode({
            'finding_id': id,
            'vehicle_id': current['vehicle_id'] ?? current['_vehicle_id'],
            'customer_id': customerId,
            'job_id':
                jobId ?? current['repair_job_id'] ?? current['found_job_id'],
            'action': action,
            '_activity_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'patch': patch,
          }),
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ],
      );
    });
    if (customerId != null && customerId.isNotEmpty) {
      await _updateCustomerCache(businessId, customerId, updated);
    }
    _changes.add(businessId);
    return updated;
  }

  /// Mirror customer-originated edits in the vehicle repository used by Jobs.
  Future<void> cacheCustomerFinding(
    String businessId,
    Map<String, dynamic> finding,
  ) async {
    final id = finding['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await _database.customStatement(
      '''INSERT INTO local_findings(
      id,business_id,vehicle_id,found_job_id,repair_job_id,body,status,include_on_invoice,
      created_at,resolved_at,can_edit,can_delete,row_version,sync_state)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET body=excluded.body,sync_state=excluded.sync_state''',
      [
        id,
        businessId,
        finding['vehicle_id'] ?? finding['_vehicle_id'],
        finding['found_job_id'],
        finding['repair_job_id'],
        finding['body'] ?? '',
        finding['status'] ?? 'open',
        finding['include_on_invoice'] == true ? 1 : 0,
        _unix(finding['created_at']),
        _unix(finding['resolved_at']),
        finding['can_edit'] == false ? 0 : 1,
        finding['can_delete'] == true ? 1 : 0,
        finding['row_version'],
        finding['sync_state'] ?? 'pending',
      ],
    );
    for (final raw
        in (finding['attachments'] as List? ?? const []).whereType<Map>()) {
      final photoId = (raw['attachment_id'] ?? raw['id'])?.toString() ?? '';
      if (photoId.isEmpty) continue;
      await _database.customStatement(
        '''INSERT INTO local_finding_photos(
        id,business_id,finding_id,attachment_id,local_file_path,storage_bucket,storage_key,
        filename,mime_type,upload_state,can_delete) VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET local_file_path=COALESCE(excluded.local_file_path,local_file_path),
        storage_bucket=COALESCE(excluded.storage_bucket,storage_bucket),storage_key=COALESCE(excluded.storage_key,storage_key)''',
        [
          photoId,
          businessId,
          id,
          photoId,
          raw['local_file_path'],
          raw['bucket'],
          raw['key'],
          raw['filename'],
          raw['mime_type'],
          raw['upload_state'] ?? 'synced',
          raw['can_delete'] == true ? 1 : 0,
        ],
      );
    }
    _changes.add(businessId);
  }

  Future<void> recoverPendingCustomerCache(
    String businessId,
    List<Map<String, dynamic>> findings,
  ) async {
    for (final finding in findings) {
      final id = finding['id']?.toString() ?? '';
      if (id.isEmpty || finding['sync_state'] != 'pending') continue;
      final existing = await _database
          .customSelect(
            'SELECT id FROM local_findings WHERE business_id=? AND id=?',
            variables: [Variable<String>(businessId), Variable<String>(id)],
          )
          .get();
      if (existing.isNotEmpty) continue;
      final queued = await _database
          .customSelect(
            "SELECT id FROM sync_outbox WHERE business_id=? AND state IN ('pending','conflict') AND (entity_id=? OR json_extract(payload_json,'\$.finding_id')=?) LIMIT 1",
            variables: [
              Variable<String>(businessId),
              Variable<String>(id),
              Variable<String>(id),
            ],
          )
          .get();
      if (queued.isNotEmpty) await cacheCustomerFinding(businessId, finding);
    }
  }

  /// Apply only queued fields, so a pending body edit does not hide a newer
  /// server repair status, while queued repair/selection cannot be resurrected.
  Future<List<Map<String, dynamic>>> project(
    String businessId,
    List<Map<String, dynamic>> findings,
  ) async {
    final queued = await _database
        .customSelect(
          "SELECT entity_type,entity_id,payload_json,last_error FROM sync_outbox WHERE business_id=? AND entity_type IN ('finding_action','customer_finding_create','customer_finding_photo','finding_photo') AND state='pending' ORDER BY id",
          variables: [Variable<String>(businessId)],
        )
        .get();
    final patches = <String, Map<String, dynamic>>{};
    final errors = <String, String>{};
    for (final row in queued) {
      final payload = _payload(row);
      final id =
          (payload['finding_id'] ??
                  payload['local_finding_id'] ??
                  row.read<String>('entity_id'))
              .toString();
      final error = row.readNullable<String>('last_error');
      if (error != null && error.isNotEmpty) errors[id] = error;
      if (row.read<String>('entity_type') == 'finding_action') {
        patches[id] = {
          ...?patches[id],
          ...Map<String, dynamic>.from(payload['patch'] as Map),
        };
      }
    }
    return findings.map((finding) {
      final patch = patches[finding['id']?.toString()];
      return patch == null
          ? {
              ...finding,
              if (errors.containsKey(finding['id']?.toString()))
                '_finding_action_error': errors[finding['id']?.toString()],
            }
          : {
              ...finding,
              ...patch,
              'sync_state': 'pending',
              '_pending_finding_action': true,
              '_pending_finding_fields': patch.keys.toList(),
              if (errors.containsKey(finding['id']?.toString()))
                '_finding_action_error': errors[finding['id']?.toString()],
            };
    }).toList();
  }

  Future<void> remap(String businessId, String localId, String serverId) async {
    final rows = await _database
        .customSelect(
          "SELECT id,entity_id,payload_json FROM sync_outbox WHERE business_id=? AND entity_type IN ('finding_action','finding_update','finding_photo','customer_finding_update','customer_finding_photo')",
          variables: [Variable<String>(businessId)],
        )
        .get();
    for (final row in rows) {
      final payload = _payload(row);
      final entityId = row.read<String>('entity_id');
      if (payload['finding_id'] != localId && entityId != localId) continue;
      payload['finding_id'] = serverId;
      if (payload['local_finding_id'] == localId) {
        payload['local_finding_id'] = serverId;
      }
      await _database.customStatement(
        'UPDATE sync_outbox SET entity_id=?,payload_json=? WHERE id=?',
        [
          entityId == localId ? serverId : entityId,
          jsonEncode(payload),
          row.read<int>('id'),
        ],
      );
    }
  }

  Future<void> flush(String businessId) async {
    final active = _flushes[_database] ??= {};
    if (active[businessId] != null) return active[businessId];
    final task = _flush(businessId);
    active[businessId] = task;
    try {
      await task;
    } finally {
      if (identical(active[businessId], task)) active.remove(businessId);
    }
  }

  Future<void> _flush(String businessId) async {
    while (true) {
      final row = await _database
          .customSelect(
            "SELECT * FROM sync_outbox WHERE business_id=? AND entity_type='finding_action' AND state='pending' ORDER BY id LIMIT 1",
            variables: [Variable<String>(businessId)],
          )
          .getSingleOrNull();
      if (row == null) return;
      final payload = _payload(row);
      final findingId = payload['finding_id'].toString();
      // The create service remaps dependent actions before they can replay.
      if (findingId.startsWith('local-finding-') ||
          (payload['job_id']?.toString() ?? '').startsWith('local-job-')) {
        return;
      }
      final id = row.read<int>('id');
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: id,
        );
        // Verify before retrying a mutation whose response may have been lost.
        final beforeRows = await _api.vehicleFindings(
          businessId,
          payload['vehicle_id'].toString(),
          includeResolved: true,
        );
        final before = beforeRows
            .where((f) => f['id']?.toString() == findingId)
            .firstOrNull;
        if (before == null || !_matchesActionResult(before, payload)) {
          if (payload['_mutation_attempted'] == true) {
            throw StateError(
              'The earlier finding change is not yet verified. '
              'Its local copy is preserved; no duplicate change was sent.',
            );
          }
          payload['_mutation_attempted'] = true;
          await _database.customStatement(
            'UPDATE sync_outbox SET payload_json=? WHERE id=?',
            [jsonEncode(payload), id],
          );
          await LocalJobQuarantine.guardReplay(_database, businessId, () async {
            final jobId = payload['job_id']?.toString() ?? '';
            switch (payload['action']) {
              case 'invoice':
                await _api.setVehicleFindingInvoiceFlag(
                  businessId,
                  findingId,
                  (payload['patch'] as Map)['include_on_invoice'] == true,
                );
              case 'add':
                await _api.addVehicleFindingToJob(businessId, findingId, jobId);
              case 'remove':
                await _api.removeVehicleFindingFromJob(
                  businessId,
                  findingId,
                  jobId,
                );
              case 'resolve':
                await _api.resolveVehicleFinding(businessId, findingId, jobId);
              case 'reopen':
                await _api.reopenVehicleFinding(businessId, findingId);
              default:
                throw StateError('Unknown finding action.');
            }
          }, outboxId: id);
        }
        final serverRows = await _api.vehicleFindings(
          businessId,
          payload['vehicle_id'].toString(),
          includeResolved: true,
        );
        final server = serverRows
            .where((f) => f['id']?.toString() == findingId)
            .firstOrNull;
        if (server == null || !_matchesActionResult(server, payload)) {
          throw StateError(
            'The saved finding could not yet be verified. It remains queued.',
          );
        }
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
            _database,
            businessId,
            outboxId: id,
          );
          await _database.customStatement(
            'DELETE FROM sync_outbox WHERE id=?',
            [id],
          );
          final projected = (await project(businessId, [server])).single;
          final dirty = await _database
              .customSelect(
                "SELECT id FROM sync_outbox WHERE business_id=? AND entity_id=? AND state IN ('pending','conflict') LIMIT 1",
                variables: [
                  Variable<String>(businessId),
                  Variable<String>(findingId),
                ],
              )
              .get();
          await _database.customStatement(
            '''UPDATE local_findings SET status=?,repair_job_id=?,include_on_invoice=?,resolved_at=?,row_version=?,sync_state=CASE WHEN sync_state='conflict' THEN sync_state ELSE ? END WHERE business_id=? AND id=?''',
            [
              projected['status'] ?? 'open',
              projected['repair_job_id'],
              projected['include_on_invoice'] == true ? 1 : 0,
              _unix(projected['resolved_at']),
              projected['row_version'],
              dirty.isEmpty ? 'synced' : 'pending',
              businessId,
              findingId,
            ],
          );
        });
        final customerId = payload['customer_id']?.toString() ?? '';
        if (customerId.isNotEmpty) {
          final current = (await project(businessId, [server])).single;
          await _updateCustomerCache(
            businessId,
            customerId,
            current,
            metadataOnly: true,
          );
        }
        _changes.add(businessId);
      } catch (error) {
        if (error is LocalJobQuarantineException) rethrow;
        await _database.customStatement(
          'UPDATE sync_outbox SET attempt_count=attempt_count+1,last_error=?,last_attempt_at=? WHERE id=?',
          [error.toString(), DateTime.now().millisecondsSinceEpoch ~/ 1000, id],
        );
        _changes.add(businessId);
        return;
      }
    }
  }

  Future<Map<String, dynamic>> projectInvoiceNotes(
    String businessId,
    Map<String, dynamic> detail,
  ) async {
    final documentJobId = detail['job_id']?.toString() ?? '';
    final documentId = detail['id']?.toString() ?? '';
    final status =
        (detail['display_status_code'] ?? detail['status'])
            ?.toString()
            .toLowerCase() ??
        '';
    if ((detail['kind']?.toString() ?? 'invoice') != 'invoice' ||
        documentJobId.isEmpty ||
        documentId.isEmpty ||
        detail['legacy_read_only'] == true ||
        detail['origin'] == 'legacy' ||
        detail['closed_at'] != null ||
        [
          'closed',
          'paid',
          'cancelled',
          'canceled',
          'void',
          'voided',
        ].contains(status)) {
      return detail;
    }
    // Only the newest editable invoice for this Job receives new generated
    // contributions. Historical/closed invoices retain their saved notes.
    final invoices = await _database
        .customSelect(
          "SELECT id,created_at,document_date FROM local_documents WHERE business_id=? AND job_id=? AND kind='invoice' AND closed_at IS NULL AND lower(COALESCE(display_status_code,status,'')) NOT IN ('closed','paid','cancelled','canceled','void','voided')",
          variables: [
            Variable<String>(businessId),
            Variable<String>(documentJobId),
          ],
        )
        .get();
    final candidates = <String, int>{
      for (final row in invoices)
        row.read<String>('id'):
            (row.data['created_at'] as int?) ??
            _unix(row.data['document_date']) ??
            0,
      documentId:
          _unix(detail['created_at']) ??
          _unix(detail['document_date']) ??
          invoices
                  .where((row) => row.read<String>('id') == documentId)
                  .firstOrNull
                  ?.data['created_at']
              as int? ??
          0,
    };
    if (candidates.length > 1) {
      final newest = candidates.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (newest.first.key != documentId ||
          newest.first.value == newest[1].value) {
        return detail;
      }
    }
    var vehicleId = detail['vehicle_id']?.toString() ?? '';
    if (vehicleId.isEmpty && detail['job_id'] != null) {
      final job = await _database
          .customSelect(
            'SELECT vehicle_id FROM local_jobs WHERE business_id=? AND id=?',
            variables: [
              Variable<String>(businessId),
              Variable<String>(detail['job_id'].toString()),
            ],
          )
          .getSingleOrNull();
      vehicleId = job?.readNullable<String>('vehicle_id') ?? '';
    }
    if (vehicleId.isEmpty) return detail;
    final local = await _database
        .customSelect(
          'SELECT * FROM local_findings WHERE business_id=? AND vehicle_id=?',
          variables: [
            Variable<String>(businessId),
            Variable<String>(vehicleId),
          ],
        )
        .get();
    final findings = await project(businessId, local.map(_rowMap).toList());
    final notes = <String, Map<String, dynamic>>{};
    var anonymous = 0;
    for (final raw
        in (detail['finding_notes'] as List? ?? const []).whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      // Preserve older anonymous server contributions rather than deleting by body.
      notes[(row['finding_id'] ?? row['id'])?.toString() ??
              'anonymous-${anonymous++}'] =
          row;
    }
    for (final finding in findings) {
      final findingJobId =
          (finding['repair_job_id'] ?? finding['found_job_id'])?.toString() ??
          '';
      if (findingJobId.isEmpty || findingJobId != documentJobId) continue;
      final id = finding['id'].toString();
      final existing = notes[id];
      final pendingFields =
          finding['_pending_finding_fields'] as List? ?? const [];
      final locallyChanged =
          pendingFields.contains('include_on_invoice') ||
          finding['sync_state'] == 'pending';
      if (existing != null &&
          existing['_local_finding_projection'] != true &&
          !locallyChanged) {
        continue;
      }
      notes.remove(id);
      if (finding['include_on_invoice'] == true) {
        notes[id] = {
          'id': id,
          'finding_id': id,
          'body': finding['body'],
          '_local_finding_projection': true,
        };
      }
    }
    return {...detail, 'finding_notes': notes.values.toList()};
  }

  Future<void> _updateCustomerCache(
    String businessId,
    String customerId,
    Map<String, dynamic> updated, {
    bool metadataOnly = false,
  }) async {
    final raw = await _cache.load(businessId, customerId, 'findings');
    if (raw is! List) return;
    final rows = raw
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final index = rows.indexWhere((r) => r['id'] == updated['id']);
    if (index < 0) return;
    rows[index] = metadataOnly
        ? {
            ...rows[index],
            for (final key in [
              'status',
              'repair_job_id',
              'resolved_job_id',
              'resolved_job_number',
              'include_on_invoice',
              'resolved_at',
              'row_version',
              'sync_state',
            ])
              if (updated.containsKey(key)) key: updated[key],
          }
        : {...rows[index], ...updated};
    await _cache.save(businessId, customerId, 'findings', rows);
  }

  // The server's resolve RPC writes resolved_job_id, NOT repair_job_id.
  // Compare authoritative server effects so that an acknowledged (or
  // previously applied with a lost reply) resolution is never resent.
  static bool _matchesActionResult(
    Map<String, dynamic> server,
    Map<String, dynamic> payload,
  ) {
    if (payload['action'] == 'resolve') {
      final jobId = payload['job_id']?.toString() ?? '';
      return jobId.isNotEmpty &&
          server['status'] == 'resolved' &&
          server['resolved_job_id']?.toString() == jobId &&
          server['resolved_at'] != null;
    }
    final patch = payload['patch'];
    return patch is Map && _matchesPatch(server, patch);
  }

  static bool _matchesPatch(Map<String, dynamic> server, Map patch) {
    for (final entry in patch.entries) {
      if (entry.key == 'resolved_at') {
        if (entry.value == null && server['resolved_at'] != null) return false;
        if (entry.value != null && server['resolved_at'] == null) return false;
      } else if (server[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static int? _unix(Object? raw) => raw == null
      ? null
      : DateTime.tryParse(raw.toString())?.millisecondsSinceEpoch == null
      ? null
      : DateTime.parse(raw.toString()).millisecondsSinceEpoch ~/ 1000;
  static Map<String, dynamic> _payload(QueryRow row) =>
      Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
  static Map<String, dynamic> _rowMap(QueryRow row) => {
    'id': row.read<String>('id'),
    'vehicle_id': row.readNullable<String>('vehicle_id'),
    'found_job_id': row.readNullable<String>('found_job_id'),
    'repair_job_id': row.readNullable<String>('repair_job_id'),
    'body': row.read<String>('body'),
    'status': row.read<String>('status'),
    'include_on_invoice': row.read<int>('include_on_invoice') == 1,
    'row_version': row.readNullable<int>('row_version'),
    'sync_state': row.read<String>('sync_state'),
    'can_edit': row.read<int>('can_edit') == 1,
    'can_delete': row.read<int>('can_delete') == 1,
    'created_at': row.data['created_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (row.data['created_at'] as int) * 1000,
            isUtc: true,
          ).toIso8601String(),
    'resolved_at': row.data['resolved_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (row.data['resolved_at'] as int) * 1000,
            isUtc: true,
          ).toIso8601String(),
  };
}
