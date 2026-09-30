import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

typedef WorkFindingMediaDirectoryProvider = Future<Directory> Function();

class OfflineWorkFindingsService {
  OfflineWorkFindingsService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
    WorkFindingMediaDirectoryProvider? mediaDirectoryProvider,
  })  : _api = api,
        _database = database ?? localDatabase,
        _mediaDirectoryProvider =
            mediaDirectoryProvider ?? getApplicationSupportDirectory;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final WorkFindingMediaDirectoryProvider _mediaDirectoryProvider;
  final Random _random = Random.secure();

  Future<void> seedCurrentVisitIfClean(
    String businessId,
    String jobId,
    Map<String, dynamic> server,
  ) async {
    final existing = await _currentVisitRow(businessId, jobId);
    if (existing != null &&
        existing.read<String>('sync_state') != 'synced') {
      return;
    }

    final id = server['id']?.toString() ?? '';
    if (id.isEmpty) return;

    await _database.customStatement(
      '''
      INSERT INTO local_job_visits (
        id, business_id, job_id, visit_number, reason,
        planned_hours, work_summary, opened_at, closed_at,
        server_updated_at, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
      ON CONFLICT(id) DO UPDATE SET
        visit_number=excluded.visit_number,
        reason=excluded.reason,
        planned_hours=excluded.planned_hours,
        work_summary=excluded.work_summary,
        opened_at=excluded.opened_at,
        closed_at=excluded.closed_at,
        server_updated_at=excluded.server_updated_at,
        row_version=excluded.row_version,
        sync_state='synced'
      ''',
      [
        id,
        businessId,
        jobId,
        _int(server['visit_number']) ?? 0,
        _text(server['reason']),
        _double(server['planned_hours']) ?? 0,
        _text(server['work_summary']),
        _unixNullable(_date(server['opened_at'])),
        _unixNullable(_date(server['closed_at'])),
        _unixNullable(_date(server['updated_at'])),
        _int(server['row_version']),
      ],
    );
  }

  Future<Map<String, dynamic>?> loadLocalCurrentVisit(
    String businessId,
    String jobId,
  ) async {
    final row = await _currentVisitRow(businessId, jobId);
    if (row == null) return null;

    return {
      'id': row.read<String>('id'),
      'job_id': jobId,
      'visit_number': row.read<int>('visit_number'),
      'reason': row.readNullable<String>('reason'),
      'planned_hours': row.data['planned_hours'],
      'work_summary': row.readNullable<String>('work_summary'),
      'opened_at': _isoFromDb(row.data['opened_at']),
      'closed_at': _isoFromDb(row.data['closed_at']),
      'updated_at': _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'sync_state': row.read<String>('sync_state'),
    };
  }

  Future<Map<String, dynamic>> saveLocalWorkSummary(
    String businessId,
    String jobId, {
    required String workSummary,
  }) async {
    await _database.transaction(() async {
      final visit = await _currentVisitRow(businessId, jobId);
      if (visit == null) {
        throw StateError(
          'This job has no local visit yet. Open it while online once, then '
          'Work Performed can be edited offline.',
        );
      }
      if (visit.read<String>('sync_state') == 'conflict') {
        throw StateError(
          'Work Performed has a sync conflict. The local copy is preserved '
          'until the conflict is resolved.',
        );
      }

      final visitId = visit.read<String>('id');
      final baseVersion = visit.readNullable<int>('row_version');

      await _database.customStatement(
        '''
        UPDATE local_job_visits
        SET work_summary = ?, sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [_nullIfBlank(workSummary), businessId, visitId],
      );

      await _upsertWorkOutbox(
        businessId,
        jobId,
        visitId: visitId,
        baseRowVersion: baseVersion,
        workSummary: workSummary,
      );
    });

    return (await loadLocalCurrentVisit(businessId, jobId))!;
  }

  Future<void> seedServerFindingsIfClean(
    String businessId,
    String vehicleId,
    List<Map<String, dynamic>> serverFindings,
  ) async {
    if (await _hasDirtyFindings(businessId, vehicleId)) return;

    await _database.transaction(() async {
      await _database.customStatement(
        '''
        DELETE FROM local_finding_photos
        WHERE business_id = ?
          AND finding_id IN (
            SELECT id
            FROM local_findings
            WHERE business_id = ? AND vehicle_id = ?
          )
        ''',
        [businessId, businessId, vehicleId],
      );
      await _database.customStatement(
        '''
        DELETE FROM local_findings
        WHERE business_id = ? AND vehicle_id = ?
        ''',
        [businessId, vehicleId],
      );

      for (final finding in serverFindings) {
        await _insertServerFinding(
          businessId,
          vehicleId,
          finding,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> loadLocalFindings(
    String businessId,
    String vehicleId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_findings
      WHERE business_id = ? AND vehicle_id = ?
      ORDER BY
        CASE status
          WHEN 'open' THEN 0
          WHEN 'in_job' THEN 1
          ELSE 2
        END,
        created_at DESC,
        id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(vehicleId),
      ],
    ).get();

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final findingId = row.read<String>('id');
      final photos = await _database.customSelect(
        '''
        SELECT *
        FROM local_finding_photos
        WHERE business_id = ? AND finding_id = ?
        ORDER BY captured_at, id
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(findingId),
        ],
      ).get();

      result.add({
        'id': findingId,
        'body': row.read<String>('body'),
        'status': row.read<String>('status'),
        'include_on_invoice':
            row.read<int>('include_on_invoice') == 1,
        'created_at': _isoFromDb(row.data['created_at']),
        'resolved_at': _isoFromDb(row.data['resolved_at']),
        'updated_at': _isoFromDb(row.data['server_updated_at']),
        'row_version': row.readNullable<int>('row_version'),
        'created_by': row.readNullable<String>('created_by'),
        'vehicle_id': row.readNullable<String>('vehicle_id'),
        'found_job_id': row.readNullable<String>('found_job_id'),
        'repair_job_id': row.readNullable<String>('repair_job_id'),
        'can_edit': row.read<int>('can_edit') == 1,
        'can_delete': row.read<int>('can_delete') == 1,
        'sync_state': row.read<String>('sync_state'),
        'attachments': photos.map((photo) {
          return <String, dynamic>{
            'attachment_id': photo.read<String>('attachment_id'),
            'id': photo.read<String>('id'),
            'bucket': photo.readNullable<String>('storage_bucket'),
            'key': photo.readNullable<String>('storage_key'),
            'filename': photo.readNullable<String>('filename'),
            'mime_type': photo.readNullable<String>('mime_type'),
            'byte_size': photo.readNullable<int>('byte_size'),
            'captured_at': _isoFromDb(photo.data['captured_at']),
            'can_delete': photo.read<int>('can_delete') == 1,
            'local_file_path':
                photo.readNullable<String>('local_file_path'),
            'upload_state': photo.read<String>('upload_state'),
            'last_error': photo.readNullable<String>('last_error'),
          };
        }).toList(),
      });
    }

    return result;
  }

  Future<Map<String, dynamic>> createLocalFinding(
    String businessId,
    String jobId, {
    required String vehicleId,
    required String body,
    bool includeOnInvoice = false,
  }) async {
    final operationId = _operationId('finding-create');
    final localId = 'local-finding-$operationId';
    final now = DateTime.now().toUtc();

    await _database.transaction(() async {
      await _database.customStatement(
        '''
        INSERT INTO local_findings (
          id, business_id, vehicle_id, found_job_id, repair_job_id,
          body, status, include_on_invoice, created_at, resolved_at,
          created_by, can_edit, can_delete, server_updated_at,
          row_version, sync_state
        ) VALUES (
          ?, ?, ?, ?, NULL, ?, 'open', ?, ?, NULL,
          NULL, 1, 0, NULL, NULL, 'pending'
        )
        ''',
        [
          localId,
          businessId,
          vehicleId,
          jobId,
          body.trim(),
          includeOnInvoice ? 1 : 0,
          _unix(now),
        ],
      );

      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (
          ?, 'finding_create', ?, 'create', ?, NULL,
          'pending', 0, ?, NULL, NULL
        )
        ''',
        [
          businessId,
          localId,
          jsonEncode({
            'operation_id': operationId,
            'job_id': jobId,
            'local_finding_id': localId,
            'body': body.trim(),
            'include_on_invoice': includeOnInvoice,
          }),
          _unix(now),
        ],
      );
    });

    final local = await _findingRow(businessId, localId);
    return _findingMapFromRow(local!);
  }

  Future<Map<String, dynamic>> updateLocalFinding(
    String businessId,
    String jobId,
    String findingId, {
    required String body,
  }) async {
    await _database.transaction(() async {
      final finding = await _findingRow(businessId, findingId);
      if (finding == null) {
        throw StateError('Finding is not available in the local cache.');
      }
      if (finding.read<String>('sync_state') == 'conflict') {
        throw StateError(
          'This Finding has a sync conflict. The local copy is preserved '
          'until the conflict is resolved.',
        );
      }

      final rowVersion = finding.readNullable<int>('row_version');
      final isLocalCreate =
          rowVersion == null && findingId.startsWith('local-finding-');

      await _database.customStatement(
        '''
        UPDATE local_findings
        SET body = ?, sync_state = 'pending'
        WHERE business_id = ? AND id = ?
        ''',
        [body.trim(), businessId, findingId],
      );

      if (isLocalCreate) {
        final rows = await _database.customSelect(
          '''
          SELECT id, payload_json
          FROM sync_outbox
          WHERE business_id = ?
            AND entity_type = 'finding_create'
            AND entity_id = ?
            AND state = 'pending'
          ORDER BY id
          LIMIT 1
          ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(findingId),
          ],
        ).get();

        if (rows.isEmpty) {
          throw StateError('Queued Finding create operation is missing.');
        }

        final outbox = rows.first;
        final payload = Map<String, dynamic>.from(
          jsonDecode(outbox.read<String>('payload_json')) as Map,
        );
        payload['body'] = body.trim();
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET payload_json = ?, last_error = NULL
          WHERE id = ?
          ''',
          [jsonEncode(payload), outbox.read<int>('id')],
        );
      } else {
        await _upsertFindingUpdateOutbox(
          businessId,
          jobId,
          findingId,
          baseRowVersion: rowVersion,
          body: body,
        );
      }
    });

    final local = await _findingRow(businessId, findingId);
    return _findingMapFromRow(local!);
  }

  Future<Map<String, dynamic>> stageFindingPhoto(
    String businessId,
    String jobId,
    String findingId, {
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final finding = await _findingRow(businessId, findingId);
    if (finding == null) {
      throw StateError('Finding is not available in the local cache.');
    }
    if (finding.read<String>('sync_state') == 'conflict') {
      throw StateError(
        'This Finding has a sync conflict. New photos are not queued until '
        'the conflict is resolved.',
      );
    }

    final operationId = _operationId('finding-photo');
    final localPhotoId = 'local-finding-photo-$operationId';
    final root = await _mediaDirectoryProvider();
    final dir = Directory(
      '${root.path}/briskers_media/$businessId/findings/$jobId',
    );
    await dir.create(recursive: true);

    final file = File(
      '${dir.path}/$operationId${_safeExtension(filename)}',
    );
    await file.writeAsBytes(bytes, flush: true);

    try {
      await _database.transaction(() async {
        await _database.customStatement(
          '''
          INSERT INTO local_finding_photos (
            id, business_id, finding_id, attachment_id,
            local_file_path, storage_bucket, storage_key, filename,
            mime_type, byte_size, captured_at, can_delete,
            upload_state, last_error
          ) VALUES (
            ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?, 0,
            'pending', NULL
          )
          ''',
          [
            localPhotoId,
            businessId,
            findingId,
            localPhotoId,
            file.path,
            filename,
            mimeType,
            bytes.length,
            _unix(DateTime.now().toUtc()),
          ],
        );

        await _database.customStatement(
          '''
          INSERT INTO sync_outbox (
            business_id, entity_type, entity_id, operation,
            payload_json, base_row_version, state, attempt_count,
            created_at, last_attempt_at, last_error
          ) VALUES (
            ?, 'finding_photo', ?, 'upload', ?, NULL,
            'pending', 0, ?, NULL, NULL
          )
          ''',
          [
            businessId,
            localPhotoId,
            jsonEncode({
              'operation_id': operationId,
              'job_id': jobId,
              'finding_id': findingId,
              'local_photo_id': localPhotoId,
              'filename': filename,
              'mime_type': mimeType,
              'local_file_path': file.path,
            }),
            _unix(DateTime.now().toUtc()),
          ],
        );
      });
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }

    return {
      'attachment_id': localPhotoId,
      'id': localPhotoId,
      'filename': filename,
      'mime_type': mimeType,
      'local_file_path': file.path,
      'upload_state': 'pending',
      'can_delete': false,
    };
  }

  Future<void> flush(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM sync_outbox
      WHERE business_id = ? AND state = 'pending'
      ORDER BY id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    var pushedAny = false;

    for (final queuedRow in rows) {
      final freshRows = await _database.customSelect(
        '''
        SELECT *
        FROM sync_outbox
        WHERE id = ? AND state = 'pending'
        LIMIT 1
        ''',
        variables: [
          Variable<int>(queuedRow.read<int>('id')),
        ],
      ).get();
      if (freshRows.isEmpty) continue;

      final row = freshRows.first;
      final type = row.read<String>('entity_type');
      try {
        bool handled = true;
        if (type == 'work_summary') {
          if (!await _flushWorkSummary(row)) break;
        } else if (type == 'finding_create') {
          await _flushFindingCreate(row);
        } else if (type == 'finding_update') {
          if (!await _flushFindingUpdate(row)) break;
        } else if (type == 'finding_photo') {
          await _flushFindingPhoto(row);
        } else {
          handled = false;
        }

        if (handled) pushedAny = true;
      } catch (error) {
        await _markOutboxFailure(row.read<int>('id'), error);
        break;
      }
    }

    if (pushedAny) {
      await _database.customStatement(
        '''
        UPDATE local_sync_states
        SET last_push_at = ?, last_error = NULL
        WHERE business_id = ? AND scope = 'jobs'
        ''',
        [_unix(DateTime.now().toUtc()), businessId],
      );
    }
  }

  Future<bool> _flushWorkSummary(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final jobId = payload['job_id']?.toString() ?? '';
    final response = await _api.syncSaveWorkSummary(
      businessId,
      jobId,
      operationId: payload['operation_id']?.toString() ?? '',
      expectedRowVersion:
          row.readNullable<int>('base_row_version'),
      workSummary: payload['work_summary']?.toString() ?? '',
    );

    if (response['status']?.toString() == 'conflict') {
      await _database.transaction(() async {
        await _database.customStatement(
          '''
          UPDATE local_job_visits
          SET sync_state = 'conflict'
          WHERE business_id = ? AND job_id = ?
          ''',
          [businessId, jobId],
        );
        await _markOutboxConflict(
          row.read<int>('id'),
          response,
        );
      });
      return false;
    }

    final raw = response['visit'];
    if (raw is! Map) {
      throw StateError('Server did not return the saved work visit.');
    }
    await _database.transaction(() async {
      await _reconcileVisit(
        businessId,
        Map<String, dynamic>.from(raw),
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });
    return true;
  }

  Future<void> _flushFindingCreate(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final jobId = payload['job_id']?.toString() ?? '';
    final localId = payload['local_finding_id']?.toString() ?? '';

    final response = await _api.syncCreateFinding(
      businessId,
      jobId,
      operationId: payload['operation_id']?.toString() ?? '',
      body: payload['body']?.toString() ?? '',
      includeOnInvoice: payload['include_on_invoice'] == true,
    );

    final raw = response['finding'];
    if (raw is! Map) {
      throw StateError('Server did not return the created Finding.');
    }

    await _database.transaction(() async {
      final server = Map<String, dynamic>.from(raw);
      final serverId = server['id']?.toString() ?? '';
      if (serverId.isEmpty) {
        throw StateError('Server Finding is missing its ID.');
      }

      await _database.customStatement(
        '''
        UPDATE local_finding_photos
        SET finding_id = ?
        WHERE business_id = ? AND finding_id = ?
        ''',
        [serverId, businessId, localId],
      );

      final pendingPhotos = await _database.customSelect(
        '''
        SELECT id, payload_json
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type = 'finding_photo'
          AND state = 'pending'
        ORDER BY id
        ''',
        variables: [Variable<String>(businessId)],
      ).get();

      for (final photoRow in pendingPhotos) {
        final photoPayload = Map<String, dynamic>.from(
          jsonDecode(photoRow.read<String>('payload_json')) as Map,
        );
        if (photoPayload['finding_id']?.toString() != localId) {
          continue;
        }
        photoPayload['finding_id'] = serverId;
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET payload_json = ?
          WHERE id = ?
          ''',
          [
            jsonEncode(photoPayload),
            photoRow.read<int>('id'),
          ],
        );
      }

      await _database.customStatement(
        'DELETE FROM local_findings WHERE business_id = ? AND id = ?',
        [businessId, localId],
      );
      await _insertServerFinding(
        businessId,
        server['vehicle_id']?.toString() ?? '',
        server,
      );

      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });
  }

  Future<bool> _flushFindingUpdate(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final findingId = payload['finding_id']?.toString() ?? '';

    final response = await _api.syncUpdateFinding(
      businessId,
      findingId,
      operationId: payload['operation_id']?.toString() ?? '',
      expectedRowVersion:
          row.readNullable<int>('base_row_version'),
      body: payload['body']?.toString() ?? '',
    );

    if (response['status']?.toString() == 'conflict') {
      await _database.transaction(() async {
        await _database.customStatement(
          '''
          UPDATE local_findings
          SET sync_state = 'conflict'
          WHERE business_id = ? AND id = ?
          ''',
          [businessId, findingId],
        );
        await _markOutboxConflict(
          row.read<int>('id'),
          response,
        );
      });
      return false;
    }

    final raw = response['finding'];
    if (raw is! Map) {
      throw StateError('Server did not return the updated Finding.');
    }

    await _database.transaction(() async {
      final old = await _findingRow(businessId, findingId);
      final vehicleId =
          old?.readNullable<String>('vehicle_id') ??
              (raw['vehicle_id']?.toString() ?? '');
      await _database.customStatement(
        'DELETE FROM local_findings WHERE business_id = ? AND id = ?',
        [businessId, findingId],
      );
      await _insertServerFinding(
        businessId,
        vehicleId,
        Map<String, dynamic>.from(raw),
        preservePhotos: true,
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });

    return true;
  }

  Future<void> _flushFindingPhoto(QueryRow row) async {
    final payload = _payload(row);
    final businessId = row.read<String>('business_id');
    final findingId = payload['finding_id']?.toString() ?? '';
    if (findingId.startsWith('local-finding-')) {
      throw StateError(
        'Finding photo dependency has not been synced yet.',
      );
    }

    final path = payload['local_file_path']?.toString() ?? '';
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Queued Finding photo is missing locally.');
    }

    final registration = await _api.syncRegisterFindingPhoto(
      businessId,
      findingId,
      operationId: payload['operation_id']?.toString() ?? '',
      filename: payload['filename']?.toString() ?? 'finding.jpg',
      mimeType: payload['mime_type']?.toString() ?? 'image/jpeg',
    );

    final attachmentId =
        registration['attachment_id']?.toString() ?? '';
    final bucket = registration['bucket']?.toString() ?? '';
    final key = registration['key']?.toString() ?? '';
    if (attachmentId.isEmpty || bucket.isEmpty || key.isEmpty) {
      throw StateError('Server returned incomplete Finding photo data.');
    }

    final bytes = await file.readAsBytes();
    await _api.uploadRegisteredAttachment(
      businessId,
      bucket: bucket,
      key: key,
      attachmentId: attachmentId,
      mimeType: payload['mime_type']?.toString() ?? 'image/jpeg',
      bytes: bytes,
    );

    await _database.transaction(() async {
      await _database.customStatement(
        '''
        UPDATE local_finding_photos
        SET id = ?,
            attachment_id = ?,
            storage_bucket = ?,
            storage_key = ?,
            byte_size = ?,
            upload_state = 'synced',
            last_error = NULL
        WHERE business_id = ? AND id = ?
        ''',
        [
          attachmentId,
          attachmentId,
          bucket,
          key,
          bytes.length,
          businessId,
          payload['local_photo_id']?.toString() ?? '',
        ],
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [row.read<int>('id')],
      );
    });
  }

  Future<void> _reconcileVisit(
    String businessId,
    Map<String, dynamic> visit,
  ) async {
    final id = visit['id']?.toString() ?? '';
    final jobId = visit['job_id']?.toString() ?? '';
    if (id.isEmpty || jobId.isEmpty) {
      throw StateError('Server work visit is incomplete.');
    }

    await _database.customStatement(
      '''
      INSERT INTO local_job_visits (
        id, business_id, job_id, visit_number, reason,
        planned_hours, work_summary, opened_at, closed_at,
        server_updated_at, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
      ON CONFLICT(id) DO UPDATE SET
        work_summary=excluded.work_summary,
        server_updated_at=excluded.server_updated_at,
        row_version=excluded.row_version,
        sync_state='synced'
      ''',
      [
        id,
        businessId,
        jobId,
        _int(visit['visit_number']) ?? 0,
        _text(visit['reason']),
        _double(visit['planned_hours']) ?? 0,
        _text(visit['work_summary']),
        _unixNullable(_date(visit['opened_at'])),
        _unixNullable(_date(visit['closed_at'])),
        _unixNullable(_date(visit['updated_at'])),
        _int(visit['row_version']),
      ],
    );
  }

  Future<void> _insertServerFinding(
    String businessId,
    String vehicleId,
    Map<String, dynamic> finding, {
    bool preservePhotos = false,
  }) async {
    final findingId = finding['id']?.toString() ?? '';
    if (findingId.isEmpty) return;

    await _database.customStatement(
      '''
      INSERT OR REPLACE INTO local_findings (
        id, business_id, vehicle_id, found_job_id, repair_job_id,
        body, status, include_on_invoice, created_at, resolved_at,
        created_by, can_edit, can_delete, server_updated_at,
        row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
      ''',
      [
        findingId,
        businessId,
        vehicleId,
        _text(finding['found_job_id']),
        _text(finding['repair_job_id']),
        finding['body']?.toString() ?? '',
        finding['status']?.toString() ?? 'open',
        finding['include_on_invoice'] == true ? 1 : 0,
        _unixNullable(_date(finding['created_at'])),
        _unixNullable(_date(finding['resolved_at'])),
        _text(finding['created_by']),
        finding['can_edit'] == true ? 1 : 0,
        finding['can_delete'] == true ? 1 : 0,
        _unixNullable(_date(finding['updated_at'])),
        _int(finding['row_version']),
      ],
    );

    if (preservePhotos) return;

    final attachments = List<dynamic>.from(
      finding['attachments'] ?? const <dynamic>[],
    );
    for (final raw in attachments) {
      if (raw is! Map) continue;
      final photo = Map<String, dynamic>.from(raw);
      final attachmentId =
          photo['attachment_id']?.toString() ?? '';
      if (attachmentId.isEmpty) continue;

      await _database.customStatement(
        '''
        INSERT OR REPLACE INTO local_finding_photos (
          id, business_id, finding_id, attachment_id,
          local_file_path, storage_bucket, storage_key, filename,
          mime_type, byte_size, captured_at, can_delete,
          upload_state, last_error
        ) VALUES (
          ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, 'synced', NULL
        )
        ''',
        [
          attachmentId,
          businessId,
          findingId,
          attachmentId,
          _text(photo['bucket']),
          _text(photo['key']),
          _text(photo['filename']),
          _text(photo['mime_type']),
          _int(photo['byte_size']),
          _unixNullable(_date(
            photo['captured_at'] ?? finding['created_at'],
          )),
          photo['can_delete'] == true ? 1 : 0,
        ],
      );
    }
  }

  Future<Map<String, dynamic>> _findingMapFromRow(
    QueryRow row,
  ) async {
    final findingId = row.read<String>('id');
    final businessId = row.read<String>('business_id');
    final photos = await _database.customSelect(
      '''
      SELECT *
      FROM local_finding_photos
      WHERE business_id = ? AND finding_id = ?
      ORDER BY captured_at, id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(findingId),
      ],
    ).get();

    return {
      'id': findingId,
      'body': row.read<String>('body'),
      'status': row.read<String>('status'),
      'include_on_invoice':
          row.read<int>('include_on_invoice') == 1,
      'created_at': _isoFromDb(row.data['created_at']),
      'resolved_at': _isoFromDb(row.data['resolved_at']),
      'updated_at': _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'created_by': row.readNullable<String>('created_by'),
      'vehicle_id': row.readNullable<String>('vehicle_id'),
      'found_job_id': row.readNullable<String>('found_job_id'),
      'repair_job_id': row.readNullable<String>('repair_job_id'),
      'can_edit': row.read<int>('can_edit') == 1,
      'can_delete': row.read<int>('can_delete') == 1,
      'sync_state': row.read<String>('sync_state'),
      'attachments': photos.map((photo) {
        return <String, dynamic>{
          'attachment_id': photo.read<String>('attachment_id'),
          'id': photo.read<String>('id'),
          'bucket': photo.readNullable<String>('storage_bucket'),
          'key': photo.readNullable<String>('storage_key'),
          'filename': photo.readNullable<String>('filename'),
          'mime_type': photo.readNullable<String>('mime_type'),
          'byte_size': photo.readNullable<int>('byte_size'),
          'captured_at': _isoFromDb(photo.data['captured_at']),
          'can_delete': photo.read<int>('can_delete') == 1,
          'local_file_path':
              photo.readNullable<String>('local_file_path'),
          'upload_state': photo.read<String>('upload_state'),
          'last_error': photo.readNullable<String>('last_error'),
        };
      }).toList(),
    };
  }

  Future<QueryRow?> _currentVisitRow(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_job_visits
      WHERE business_id = ? AND job_id = ?
      ORDER BY COALESCE(closed_at, opened_at) DESC, opened_at DESC
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> _findingRow(
    String businessId,
    String findingId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_findings
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(findingId),
      ],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> _hasDirtyFindings(
    String businessId,
    String vehicleId,
  ) async {
    final row = await _database.customSelect(
      '''
      SELECT
        EXISTS(
          SELECT 1
          FROM local_findings
          WHERE business_id = ?
            AND vehicle_id = ?
            AND sync_state IN ('pending','conflict')
        )
        OR EXISTS(
          SELECT 1
          FROM local_finding_photos p
          JOIN local_findings f
            ON f.business_id = p.business_id
           AND f.id = p.finding_id
          WHERE f.business_id = ?
            AND f.vehicle_id = ?
            AND p.upload_state <> 'synced'
        ) AS dirty
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(vehicleId),
        Variable<String>(businessId),
        Variable<String>(vehicleId),
      ],
    ).getSingle();

    return row.read<int>('dirty') == 1;
  }

  Future<void> _upsertWorkOutbox(
    String businessId,
    String jobId, {
    required String visitId,
    required int? baseRowVersion,
    required String workSummary,
  }) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'work_summary'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    final operationId = rows.isEmpty
        ? _operationId('work')
        : _operationIdFromPayload(rows.first) ??
            _operationId('work');
    final payload = jsonEncode({
      'operation_id': operationId,
      'job_id': jobId,
      'visit_id': visitId,
      'work_summary': workSummary,
    });

    if (rows.isEmpty) {
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (
          ?, 'work_summary', ?, 'upsert', ?, ?, 'pending',
          0, ?, NULL, NULL
        )
        ''',
        [
          businessId,
          jobId,
          payload,
          baseRowVersion,
          _unix(DateTime.now().toUtc()),
        ],
      );
    } else {
      await _database.customStatement(
        '''
        UPDATE sync_outbox
        SET payload_json = ?,
            base_row_version = ?,
            attempt_count = 0,
            last_attempt_at = NULL,
            last_error = NULL
        WHERE id = ?
        ''',
        [
          payload,
          baseRowVersion,
          rows.first.read<int>('id'),
        ],
      );
    }
  }

  Future<void> _upsertFindingUpdateOutbox(
    String businessId,
    String jobId,
    String findingId, {
    required int? baseRowVersion,
    required String body,
  }) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'finding_update'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(findingId),
      ],
    ).get();

    final operationId = rows.isEmpty
        ? _operationId('finding-update')
        : _operationIdFromPayload(rows.first) ??
            _operationId('finding-update');
    final payload = jsonEncode({
      'operation_id': operationId,
      'job_id': jobId,
      'finding_id': findingId,
      'body': body.trim(),
    });

    if (rows.isEmpty) {
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (
          ?, 'finding_update', ?, 'update', ?, ?, 'pending',
          0, ?, NULL, NULL
        )
        ''',
        [
          businessId,
          findingId,
          payload,
          baseRowVersion,
          _unix(DateTime.now().toUtc()),
        ],
      );
    } else {
      await _database.customStatement(
        '''
        UPDATE sync_outbox
        SET payload_json = ?,
            base_row_version = ?,
            attempt_count = 0,
            last_attempt_at = NULL,
            last_error = NULL
        WHERE id = ?
        ''',
        [
          payload,
          baseRowVersion,
          rows.first.read<int>('id'),
        ],
      );
    }
  }

  Future<void> _markOutboxFailure(
    int id,
    Object error,
  ) async {
    await _database.customStatement(
      '''
      UPDATE sync_outbox
      SET attempt_count = attempt_count + 1,
          last_attempt_at = ?,
          last_error = ?
      WHERE id = ?
      ''',
      [
        _unix(DateTime.now().toUtc()),
        error.toString(),
        id,
      ],
    );
  }

  Future<void> _markOutboxConflict(
    int id,
    Map<String, dynamic> response,
  ) async {
    await _database.customStatement(
      '''
      UPDATE sync_outbox
      SET state = 'conflict',
          attempt_count = attempt_count + 1,
          last_attempt_at = ?,
          last_error = ?
      WHERE id = ?
      ''',
      [
        _unix(DateTime.now().toUtc()),
        jsonEncode(response),
        id,
      ],
    );
  }

  Map<String, dynamic> _payload(QueryRow row) =>
      Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );

  String? _operationIdFromPayload(QueryRow row) {
    try {
      return _payload(row)['operation_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  String _operationId(String prefix) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final a = _random.nextInt(0x7fffffff).toRadixString(16);
    final b = _random.nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-$micros-$a-$b';
  }

  String _safeExtension(String filename) {
    final index = filename.lastIndexOf('.');
    if (index <= 0 || index == filename.length - 1) return '.jpg';
    final ext = filename.substring(index).toLowerCase();
    if (const ['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) {
      return ext;
    }
    return '.jpg';
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _text(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  int? _int(Object? value) =>
      int.tryParse(value?.toString() ?? '');

  double? _double(Object? value) =>
      double.tryParse(value?.toString() ?? '');

  DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

  int _unix(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;

  int? _unixNullable(DateTime? value) =>
      value == null ? null : _unix(value);

  String? _isoFromDb(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    return DateTime.tryParse(value.toString())?.toUtc().toIso8601String();
  }
}
