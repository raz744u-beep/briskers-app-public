import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

typedef MediaDirectoryProvider = Future<Directory> Function();

class OfflinePreInspectionService {
  OfflinePreInspectionService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
    MediaDirectoryProvider? mediaDirectoryProvider,
  })  : _api = api,
        _database = database ?? localDatabase,
        _mediaDirectoryProvider =
            mediaDirectoryProvider ?? getApplicationSupportDirectory;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final MediaDirectoryProvider _mediaDirectoryProvider;
  final Random _random = Random.secure();

  Future<Map<String, dynamic>?> loadLocalInspection(
    String businessId,
    String jobId,
  ) async {
    final row = await _inspectionRow(businessId, jobId);
    if (row == null) return null;

    final id = row.read<String>('id');
    final photos = await _database.customSelect(
      '''
      SELECT *
      FROM local_pre_inspection_photos
      WHERE business_id = ? AND inspection_id = ?
      ORDER BY captured_at, id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(id),
      ],
    ).get();

    return {
      'id': id,
      'job_id': jobId,
      'vehicle_id': row.readNullable<String>('vehicle_id'),
      'inspected_at': _isoFromDb(row.data['inspected_at']),
      'odometer': row.data['odometer'],
      'notes': row.readNullable<String>('notes'),
      'created_by': row.readNullable<String>('created_by'),
      'updated_at': _isoFromDb(row.data['server_updated_at']),
      'row_version': row.readNullable<int>('row_version'),
      'sync_state': row.read<String>('sync_state'),
      'photos': photos.map((photo) {
        return <String, dynamic>{
          'id': photo.read<String>('id'),
          'attachment_id': photo.read<String>('attachment_id'),
          'filename': photo.readNullable<String>('filename'),
          'bucket': photo.readNullable<String>('storage_bucket'),
          'key': photo.readNullable<String>('storage_key'),
          'mime_type': photo.readNullable<String>('mime_type'),
          'byte_size': photo.readNullable<int>('byte_size'),
          'captured_at': _isoFromDb(photo.data['captured_at']),
          'note': photo.readNullable<String>('note'),
          'created_by': photo.readNullable<String>('created_by'),
          'can_edit_note': photo.read<int>('can_edit_note') == 1,
          'can_delete': photo.read<int>('can_delete') == 1,
          'local_file_path': photo.readNullable<String>('local_file_path'),
          'upload_state': photo.read<String>('upload_state'),
          'last_error': photo.readNullable<String>('last_error'),
        };
      }).toList(),
    };
  }

  Future<Map<String, dynamic>> saveLocalInspection(
    String businessId,
    String jobId, {
    String? vehicleId,
    String? notes,
    num? odometer,
  }) async {
    await _database.transaction(() async {
      final existing = await _inspectionRow(businessId, jobId);
      if (existing != null && existing.read<String>('sync_state') == 'conflict') {
        throw StateError(
          'This pre-inspection has a sync conflict. The local copy is preserved '
          'until the conflict is resolved.',
        );
      }

      final localId = existing?.read<String>('id') ??
          'local-inspection-${_operationId('inspection')}';
      final baseVersion = existing?.readNullable<int>('row_version');
      final inspectedAt = existing?.data['inspected_at'] ??
          _unix(DateTime.now().toUtc());

      await _database.customStatement(
        '''
        INSERT INTO local_pre_inspections (
          id, business_id, job_id, vehicle_id, inspected_at,
          odometer, notes, created_by, server_updated_at,
          row_version, sync_state
        ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, 'pending')
        ON CONFLICT(id) DO UPDATE SET
          vehicle_id=excluded.vehicle_id,
          odometer=excluded.odometer,
          notes=excluded.notes,
          sync_state='pending'
        ''',
        [
          localId,
          businessId,
          jobId,
          vehicleId,
          inspectedAt,
          odometer,
          _nullIfBlank(notes),
          baseVersion,
        ],
      );

      await _upsertInspectionOutbox(
        businessId,
        jobId,
        localInspectionId: localId,
        baseRowVersion: baseVersion,
        notes: notes,
        odometer: odometer,
      );
    });

    return (await loadLocalInspection(businessId, jobId))!;
  }

  Future<Map<String, dynamic>> stagePhoto(
    String businessId,
    String jobId, {
    String? vehicleId,
    num? fallbackOdometer,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    String? note,
  }) async {
    final operationId = _operationId('photo');
    final localPhotoId = 'local-photo-$operationId';
    final root = await _mediaDirectoryProvider();
    final dir = Directory(
      '${root.path}/briskers_media/$businessId/preinspection/$jobId',
    );
    await dir.create(recursive: true);

    final file = File('${dir.path}/$operationId${_safeExtension(filename)}');
    await file.writeAsBytes(bytes, flush: true);

    try {
      await _database.transaction(() async {
        var inspection = await _inspectionRow(businessId, jobId);
        if (inspection != null &&
            inspection.read<String>('sync_state') == 'conflict') {
          throw StateError(
            'This pre-inspection has a sync conflict. New photos are kept out '
            'of the queue until the conflict is resolved.',
          );
        }

        if (inspection == null) {
          final localInspectionId =
              'local-inspection-${_operationId('inspection')}';
          await _database.customStatement(
            '''
            INSERT INTO local_pre_inspections (
              id, business_id, job_id, vehicle_id, inspected_at,
              odometer, notes, created_by, server_updated_at,
              row_version, sync_state
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, 'pending')
            ''',
            [
              localInspectionId,
              businessId,
              jobId,
              vehicleId,
              _unix(DateTime.now().toUtc()),
              fallbackOdometer,
            ],
          );
          inspection = await _inspectionRow(businessId, jobId);
        }

        final inspectionId = inspection!.read<String>('id');
        final baseVersion = inspection.readNullable<int>('row_version');

        if (baseVersion == null ||
            inspection.read<String>('sync_state') == 'pending') {
          await _upsertInspectionOutbox(
            businessId,
            jobId,
            localInspectionId: inspectionId,
            baseRowVersion: baseVersion,
            notes: inspection.readNullable<String>('notes'),
            odometer: inspection.data['odometer'] as num?,
          );
        }

        await _database.customStatement(
          '''
          INSERT INTO local_pre_inspection_photos (
            id, business_id, inspection_id, attachment_id,
            local_file_path, storage_bucket, storage_key, filename,
            mime_type, byte_size, captured_at, note, created_by,
            can_edit_note, can_delete, upload_state, last_error
          ) VALUES (
            ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?, ?, NULL,
            1, 0, 'pending', NULL
          )
          ''',
          [
            localPhotoId,
            businessId,
            inspectionId,
            localPhotoId,
            file.path,
            filename,
            mimeType,
            bytes.length,
            _unix(DateTime.now().toUtc()),
            _nullIfBlank(note),
          ],
        );

        await _database.customStatement(
          '''
          INSERT INTO sync_outbox (
            business_id, entity_type, entity_id, operation,
            payload_json, base_row_version, state, attempt_count,
            created_at, last_attempt_at, last_error
          ) VALUES (?, 'preinspection_photo', ?, 'upload', ?, NULL,
                    'pending', 0, ?, NULL, NULL)
          ''',
          [
            businessId,
            localPhotoId,
            jsonEncode({
              'operation_id': operationId,
              'job_id': jobId,
              'local_photo_id': localPhotoId,
              'local_inspection_id': inspectionId,
              'filename': filename,
              'mime_type': mimeType,
              'note': _nullIfBlank(note),
              'local_file_path': file.path,
            }),
            _unix(DateTime.now().toUtc()),
          ],
        );
      });
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }

    return (await loadLocalInspection(businessId, jobId))!;
  }

  Future<Map<String, dynamic>> updatePendingPhotoNote(
    String businessId,
    String jobId,
    String localPhotoId,
    String note,
  ) async {
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        UPDATE local_pre_inspection_photos
        SET note = ?, last_error = NULL
        WHERE business_id = ? AND id = ? AND upload_state = 'pending'
        ''',
        [_nullIfBlank(note), businessId, localPhotoId],
      );

      final rows = await _database.customSelect(
        '''
        SELECT id, payload_json
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type = 'preinspection_photo'
          AND entity_id = ?
          AND operation = 'upload'
          AND state = 'pending'
        ORDER BY id
        LIMIT 1
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<String>(localPhotoId),
        ],
      ).get();

      if (rows.isNotEmpty) {
        final row = rows.first;
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        payload['note'] = _nullIfBlank(note);
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET payload_json = ?, last_error = NULL
          WHERE id = ?
          ''',
          [jsonEncode(payload), row.read<int>('id')],
        );
      }
    });

    return (await loadLocalInspection(businessId, jobId))!;
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

    for (final row in rows) {
      final id = row.read<int>('id');
      final entityType = row.read<String>('entity_type');

      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );

        if (entityType == 'preinspection') {
          final applied = await _flushInspection(row, payload);
          if (!applied) break;
          pushedAny = true;
        } else if (entityType == 'preinspection_photo') {
          await _flushPhoto(row, payload);
          pushedAny = true;
        } else {
          continue;
        }
      } catch (error) {
        await _markOutboxFailure(id, error);
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

  Future<bool> _flushInspection(
    QueryRow row,
    Map<String, dynamic> payload,
  ) async {
    final outboxId = row.read<int>('id');
    final businessId = row.read<String>('business_id');
    final jobId = payload['job_id']?.toString() ?? '';
    final operationId = payload['operation_id']?.toString() ?? '';

    final response = await _api.syncSavePreInspection(
      businessId,
      jobId,
      operationId: operationId,
      expectedRowVersion: row.readNullable<int>('base_row_version'),
      notes: payload['notes']?.toString(),
      odometer: payload['odometer'] as num?,
    );

    if (response['status']?.toString() == 'conflict') {
      await _database.transaction(() async {
        await _database.customStatement(
          '''
          UPDATE local_pre_inspections
          SET sync_state = 'conflict'
          WHERE business_id = ? AND job_id = ?
          ''',
          [businessId, jobId],
        );
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
            outboxId,
          ],
        );
      });
      return false;
    }

    final rawInspection = response['inspection'];
    if (rawInspection is! Map) {
      throw StateError('Server did not return the saved pre-inspection.');
    }

    await _database.transaction(() async {
      await _reconcileInspection(
        businessId,
        jobId,
        Map<String, dynamic>.from(rawInspection),
      );
      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [outboxId],
      );
    });

    return true;
  }

  Future<void> _flushPhoto(
    QueryRow row,
    Map<String, dynamic> payload,
  ) async {
    final outboxId = row.read<int>('id');
    final businessId = row.read<String>('business_id');
    final jobId = payload['job_id']?.toString() ?? '';
    final operationId = payload['operation_id']?.toString() ?? '';
    final localPhotoId = payload['local_photo_id']?.toString() ?? '';
    final localPath = payload['local_file_path']?.toString() ?? '';
    final filename = payload['filename']?.toString() ?? 'inspection.jpg';
    final mimeType = payload['mime_type']?.toString() ?? 'image/jpeg';

    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Queued inspection photo is missing from local storage.');
    }

    final registration = await _api.syncRegisterPreInspectionPhoto(
      businessId,
      jobId,
      operationId: operationId,
      filename: filename,
      mimeType: mimeType,
      note: payload['note']?.toString(),
    );

    final rawInspection = registration['inspection'];
    if (rawInspection is Map) {
      await _database.transaction(() async {
        await _reconcileInspection(
          businessId,
          jobId,
          Map<String, dynamic>.from(rawInspection),
        );
      });
    }

    final bytes = await file.readAsBytes();
    final attachmentId = registration['attachment_id']?.toString() ?? '';
    final photoId = registration['photo_id']?.toString() ?? '';
    final bucket = registration['bucket']?.toString() ?? '';
    final key = registration['key']?.toString() ?? '';

    if (attachmentId.isEmpty || photoId.isEmpty || bucket.isEmpty || key.isEmpty) {
      throw StateError('Server returned incomplete photo registration.');
    }

    await _api.uploadRegisteredAttachment(
      businessId,
      bucket: bucket,
      key: key,
      attachmentId: attachmentId,
      mimeType: mimeType,
      bytes: bytes,
    );

    await _database.transaction(() async {
      final inspection = await _inspectionRow(businessId, jobId);
      if (inspection == null) {
        throw StateError('Local pre-inspection disappeared during upload.');
      }

      await _database.customStatement(
        '''
        UPDATE local_pre_inspection_photos
        SET id = ?,
            inspection_id = ?,
            attachment_id = ?,
            storage_bucket = ?,
            storage_key = ?,
            byte_size = ?,
            upload_state = 'synced',
            last_error = NULL
        WHERE business_id = ? AND id = ?
        ''',
        [
          photoId,
          inspection.read<String>('id'),
          attachmentId,
          bucket,
          key,
          bytes.length,
          businessId,
          localPhotoId,
        ],
      );

      await _database.customStatement(
        'DELETE FROM sync_outbox WHERE id = ?',
        [outboxId],
      );
    });
  }

  Future<void> _reconcileInspection(
    String businessId,
    String jobId,
    Map<String, dynamic> server,
  ) async {
    final local = await _inspectionRow(businessId, jobId);
    final serverId = server['id']?.toString() ?? '';
    if (serverId.isEmpty) {
      throw StateError('Server pre-inspection is missing its ID.');
    }

    final localId = local?.read<String>('id');

    if (localId != null && localId != serverId) {
      await _database.customStatement(
        '''
        UPDATE local_pre_inspection_photos
        SET inspection_id = ?
        WHERE business_id = ? AND inspection_id = ?
        ''',
        [serverId, businessId, localId],
      );

      await _database.customStatement(
        'DELETE FROM local_pre_inspections WHERE business_id = ? AND id = ?',
        [businessId, localId],
      );
    }

    await _database.customStatement(
      '''
      INSERT INTO local_pre_inspections (
        id, business_id, job_id, vehicle_id, inspected_at,
        odometer, notes, created_by, server_updated_at,
        row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
      ON CONFLICT(id) DO UPDATE SET
        vehicle_id=excluded.vehicle_id,
        inspected_at=excluded.inspected_at,
        odometer=excluded.odometer,
        notes=excluded.notes,
        created_by=excluded.created_by,
        server_updated_at=excluded.server_updated_at,
        row_version=excluded.row_version,
        sync_state='synced'
      ''',
      [
        serverId,
        businessId,
        jobId,
        server['vehicle_id']?.toString(),
        _unixNullable(_parseDate(server['inspected_at'])),
        server['odometer'] as num?,
        _nullIfBlank(server['notes']?.toString()),
        server['created_by']?.toString(),
        _unixNullable(_parseDate(server['updated_at'])),
        int.tryParse(server['row_version']?.toString() ?? ''),
      ],
    );

    if (localId != null && localId != serverId) {
      await _database.customStatement(
        '''
        UPDATE local_pre_inspection_photos
        SET inspection_id = ?
        WHERE business_id = ? AND inspection_id = ?
        ''',
        [serverId, businessId, localId],
      );
    }
  }

  Future<QueryRow?> _inspectionRow(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM local_pre_inspections
      WHERE business_id = ? AND job_id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _upsertInspectionOutbox(
    String businessId,
    String jobId, {
    required String localInspectionId,
    required int? baseRowVersion,
    required String? notes,
    required num? odometer,
  }) async {
    final existing = await _database.customSelect(
      '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'preinspection'
        AND entity_id = ?
        AND operation = 'upsert'
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    String operationId;
    int? existingId;

    if (existing.isNotEmpty) {
      existingId = existing.first.read<int>('id');
      try {
        final oldPayload = Map<String, dynamic>.from(
          jsonDecode(existing.first.read<String>('payload_json')) as Map,
        );
        operationId = oldPayload['operation_id']?.toString() ?? '';
      } catch (_) {
        operationId = '';
      }
      if (operationId.isEmpty) {
        operationId = _operationId('inspection');
      }
    } else {
      operationId = _operationId('inspection');
    }

    final payload = jsonEncode({
      'operation_id': operationId,
      'job_id': jobId,
      'local_inspection_id': localInspectionId,
      'notes': _nullIfBlank(notes),
      'odometer': odometer,
    });

    if (existingId != null) {
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
        [payload, baseRowVersion, existingId],
      );
    } else {
      await _database.customStatement(
        '''
        INSERT INTO sync_outbox (
          business_id, entity_type, entity_id, operation,
          payload_json, base_row_version, state, attempt_count,
          created_at, last_attempt_at, last_error
        ) VALUES (?, 'preinspection', ?, 'upsert', ?, ?, 'pending',
                  0, ?, NULL, NULL)
        ''',
        [
          businessId,
          jobId,
          payload,
          baseRowVersion,
          _unix(DateTime.now().toUtc()),
        ],
      );
    }
  }

  Future<void> _markOutboxFailure(int id, Object error) async {
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

  int _unix(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;

  int? _unixNullable(DateTime? value) =>
      value == null ? null : _unix(value);

  DateTime? _parseDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

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
