import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'customer_detail_cache.dart';
import 'local_job_quarantine.dart';
import 'vehicle_finding_actions_service.dart';
import 'offline_work_findings_service.dart';

class OfflineCustomerDetailWriteService {
  OfflineCustomerDetailWriteService({
    BriskersApi api = const BriskersApi(),
    CustomerDetailCache cache = const CustomerDetailCache(),
    BriskersLocalDatabase? database,
  }) : _api = api,
       _cache = cache,
       _database = database ?? localDatabase;

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final CustomerDetailCache _cache;
  final Random _random = Random.secure();
  static final Expando<Map<String, Future<void>>> _activeFlushes = Expando();

  String _operationId(String prefix) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return '$prefix-$now-$salt';
  }

  int _unixNow() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  Future<List<Map<String, dynamic>>> _loadList(
    String businessId,
    String customerId,
    String section,
  ) async {
    final raw = await _cache.load(businessId, customerId, section);
    return raw is List
        ? raw
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : <Map<String, dynamic>>[];
  }

  Future<void> _saveList(
    String businessId,
    String customerId,
    String section,
    List<Map<String, dynamic>> rows,
  ) {
    return _cache.save(businessId, customerId, section, rows);
  }

  Future<File> _stageFile(
    String businessId,
    String customerId,
    String area,
    String filename,
    Uint8List bytes,
  ) async {
    final root = await getApplicationSupportDirectory();
    final id = _operationId(area);
    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 && filename.length - dot <= 8
        ? filename.substring(dot).toLowerCase()
        : '.img';
    final dir = Directory(
      '${root.path}/briskers_media/$businessId/customers/$customerId/$area',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$id$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _enqueue(
    String businessId,
    String type,
    String entityId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    await _database.customStatement(
      '''
      INSERT INTO sync_outbox (
        business_id, entity_type, entity_id, operation,
        payload_json, base_row_version, state, attempt_count,
        created_at, last_attempt_at, last_error
      ) VALUES (?, ?, ?, ?, ?, NULL, 'pending', 0, ?, NULL, NULL)
      ''',
      [businessId, type, entityId, operation, jsonEncode(payload), _unixNow()],
    );
  }

  Future<Map<String, dynamic>> createCustomerNote(
    String businessId,
    String customerId, {
    required String body,
    required List<Map<String, dynamic>> photos,
  }) async {
    final op = _operationId('customer-note');
    final localId = 'local-note-$op';
    final attachments = <Map<String, dynamic>>[];

    await _database.transaction(() async {
      await _enqueue(businessId, 'customer_note_create', localId, 'create', {
        'operation_id': op,
        'customer_id': customerId,
        'local_note_id': localId,
        'body': body,
      });

      for (final photo in photos) {
        final filename = photo['filename']?.toString() ?? 'photo.jpg';
        final mimeType = photo['mime_type']?.toString() ?? 'image/jpeg';
        final bytes = photo['bytes'] as Uint8List;
        final file = await _stageFile(
          businessId,
          customerId,
          'notes',
          filename,
          bytes,
        );
        final photoId = 'local-note-photo-${_operationId('photo')}';
        attachments.add({
          'attachment_id': photoId,
          'id': photoId,
          'filename': filename,
          'mime_type': mimeType,
          'local_file_path': file.path,
          'upload_state': 'pending',
        });
        await _enqueue(businessId, 'customer_note_photo', photoId, 'upload', {
          'customer_id': customerId,
          'note_id': localId,
          'local_note_id': localId,
          'filename': filename,
          'mime_type': mimeType,
          'local_file_path': file.path,
        });
      }
    });

    final rows = await _loadList(businessId, customerId, 'notes');
    final row = <String, dynamic>{
      'id': localId,
      'body': body,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'seen': true,
      'attachments': attachments,
      'sync_state': 'pending',
    };
    rows.insert(0, row);
    await _saveList(businessId, customerId, 'notes', rows);
    return row;
  }

  Future<List<Map<String, dynamic>>> addCustomerNotePhotos(
    String businessId,
    String customerId,
    String noteId, {
    required List<Map<String, dynamic>> photos,
  }) async {
    final rows = await _loadList(businessId, customerId, 'notes');
    final index = rows.indexWhere((row) => row['id']?.toString() == noteId);
    if (index < 0) {
      throw StateError('Customer note is not available locally.');
    }

    final attachments =
        List<dynamic>.from(
          rows[index]['attachments'] ?? const [],
        ).whereType<Map>().map((raw) {
          return Map<String, dynamic>.from(raw);
        }).toList();

    for (final photo in photos) {
      final filename = photo['filename']?.toString() ?? 'photo.jpg';
      final mimeType = photo['mime_type']?.toString() ?? 'image/jpeg';
      final bytes = photo['bytes'] as Uint8List;
      final file = await _stageFile(
        businessId,
        customerId,
        'notes',
        filename,
        bytes,
      );
      final photoId = 'local-note-photo-${_operationId('photo')}';
      attachments.add({
        'attachment_id': photoId,
        'id': photoId,
        'filename': filename,
        'mime_type': mimeType,
        'local_file_path': file.path,
        'upload_state': 'pending',
      });
      await _enqueue(businessId, 'customer_note_photo', photoId, 'upload', {
        'customer_id': customerId,
        'note_id': noteId,
        'local_note_id': noteId,
        'filename': filename,
        'mime_type': mimeType,
        'local_file_path': file.path,
      });
    }

    rows[index] = {
      ...rows[index],
      'attachments': attachments,
      'sync_state': 'pending',
    };
    await _saveList(businessId, customerId, 'notes', rows);
    return attachments;
  }

  Future<void> updateCustomerNote(
    String businessId,
    String customerId,
    String noteId, {
    required String body,
  }) async {
    final rows = await _loadList(businessId, customerId, 'notes');
    final index = rows.indexWhere((row) => row['id']?.toString() == noteId);
    if (index < 0) {
      throw StateError('Customer note is not available locally.');
    }
    rows[index] = {...rows[index], 'body': body, 'sync_state': 'pending'};
    await _saveList(businessId, customerId, 'notes', rows);

    final pendingCreate = await _database
        .customSelect(
          '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'customer_note_create'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
          variables: [Variable<String>(businessId), Variable<String>(noteId)],
        )
        .get();

    if (pendingCreate.isNotEmpty) {
      final row = pendingCreate.first;
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      payload['body'] = body;
      await _database.customStatement(
        'UPDATE sync_outbox SET payload_json = ?, last_error = NULL WHERE id = ?',
        [jsonEncode(payload), row.read<int>('id')],
      );
      return;
    }

    await _enqueue(businessId, 'customer_note_update', noteId, 'update', {
      'customer_id': customerId,
      'note_id': noteId,
      'body': body,
    });
  }

  Future<Map<String, dynamic>> createFinding(
    String businessId,
    String customerId,
    String vehicleId, {
    required String body,
    required bool includeOnInvoice,
    required List<Map<String, dynamic>> photos,
  }) async {
    final op = _operationId('customer-finding');
    final localId = 'local-finding-$op';
    final attachments = <Map<String, dynamic>>[];

    await _database.transaction(() async {
      await _enqueue(businessId, 'customer_finding_create', localId, 'create', {
        'operation_id': op,
        'customer_id': customerId,
        'vehicle_id': vehicleId,
        'local_finding_id': localId,
        'body': body,
        'include_on_invoice': includeOnInvoice,
      });

      for (final photo in photos) {
        final filename = photo['filename']?.toString() ?? 'photo.jpg';
        final mimeType = photo['mime_type']?.toString() ?? 'image/jpeg';
        final bytes = photo['bytes'] as Uint8List;
        final file = await _stageFile(
          businessId,
          customerId,
          'findings',
          filename,
          bytes,
        );
        final photoId = 'local-finding-photo-${_operationId('photo')}';
        attachments.add({
          'attachment_id': photoId,
          'id': photoId,
          'filename': filename,
          'mime_type': mimeType,
          'local_file_path': file.path,
          'upload_state': 'pending',
        });
        await _enqueue(
          businessId,
          'customer_finding_photo',
          photoId,
          'upload',
          {
            'customer_id': customerId,
            'finding_id': localId,
            'local_finding_id': localId,
            'filename': filename,
            'mime_type': mimeType,
            'local_file_path': file.path,
          },
        );
      }
    });

    final rows = await _loadList(businessId, customerId, 'findings');
    final row = <String, dynamic>{
      'id': localId,
      'body': body,
      'status': 'open',
      'include_on_invoice': includeOnInvoice,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      '_vehicle_id': vehicleId,
      'vehicle_id': vehicleId,
      'attachments': attachments,
      'sync_state': 'pending',
    };
    rows.insert(0, row);
    await _saveList(businessId, customerId, 'findings', rows);
    await VehicleFindingActionsService(
      api: _api,
      database: _database,
      cache: _cache,
    ).cacheCustomerFinding(businessId, row);
    return row;
  }

  Future<List<Map<String, dynamic>>> addFindingPhotos(
    String businessId,
    String customerId,
    String findingId, {
    required List<Map<String, dynamic>> photos,
  }) async {
    final rows = await _loadList(businessId, customerId, 'findings');
    final index = rows.indexWhere((row) => row['id']?.toString() == findingId);
    if (index < 0) {
      throw StateError('Finding is not available locally.');
    }

    final attachments =
        List<dynamic>.from(
          rows[index]['attachments'] ?? const [],
        ).whereType<Map>().map((raw) {
          return Map<String, dynamic>.from(raw);
        }).toList();

    for (final photo in photos) {
      final filename = photo['filename']?.toString() ?? 'photo.jpg';
      final mimeType = photo['mime_type']?.toString() ?? 'image/jpeg';
      final bytes = photo['bytes'] as Uint8List;
      final file = await _stageFile(
        businessId,
        customerId,
        'findings',
        filename,
        bytes,
      );
      final photoId = 'local-finding-photo-${_operationId('photo')}';
      attachments.add({
        'attachment_id': photoId,
        'id': photoId,
        'filename': filename,
        'mime_type': mimeType,
        'local_file_path': file.path,
        'upload_state': 'pending',
      });
      await _enqueue(businessId, 'customer_finding_photo', photoId, 'upload', {
        'customer_id': customerId,
        'finding_id': findingId,
        'local_finding_id': findingId,
        'filename': filename,
        'mime_type': mimeType,
        'local_file_path': file.path,
      });
    }

    rows[index] = {
      ...rows[index],
      'attachments': attachments,
      'sync_state': 'pending',
    };
    await _saveList(businessId, customerId, 'findings', rows);
    await VehicleFindingActionsService(
      api: _api,
      database: _database,
      cache: _cache,
    ).cacheCustomerFinding(businessId, rows[index]);
    return attachments;
  }

  Future<void> updateFinding(
    String businessId,
    String customerId,
    String findingId, {
    required String body,
  }) async {
    final rows = await _loadList(businessId, customerId, 'findings');
    final index = rows.indexWhere((row) => row['id']?.toString() == findingId);
    if (index < 0) {
      throw StateError('Finding is not available locally.');
    }
    rows[index] = {...rows[index], 'body': body, 'sync_state': 'pending'};
    await _saveList(businessId, customerId, 'findings', rows);
    await VehicleFindingActionsService(
      api: _api,
      database: _database,
      cache: _cache,
    ).cacheCustomerFinding(businessId, rows[index]);

    final pendingCreate = await _database
        .customSelect(
          '''
      SELECT id, payload_json
      FROM sync_outbox
      WHERE business_id = ?
        AND entity_type = 'customer_finding_create'
        AND entity_id = ?
        AND state = 'pending'
      ORDER BY id
      LIMIT 1
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(findingId),
          ],
        )
        .get();

    if (pendingCreate.isNotEmpty) {
      final row = pendingCreate.first;
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map,
      );
      payload['body'] = body;
      await _database.customStatement(
        'UPDATE sync_outbox SET payload_json = ?, last_error = NULL WHERE id = ?',
        [jsonEncode(payload), row.read<int>('id')],
      );
      return;
    }

    await _enqueue(businessId, 'customer_finding_update', findingId, 'update', {
      'customer_id': customerId,
      'finding_id': findingId,
      'body': body,
    });
  }

  Future<void> flush(String businessId) async {
    final active = _activeFlushes[_database] ??= <String, Future<void>>{};
    final previous = active[businessId];
    if (previous != null) return previous;
    final work = _flushQueue(businessId);
    active[businessId] = work;
    try {
      await work;
    } finally {
      if (identical(active[businessId], work)) active.remove(businessId);
    }
  }

  Future<void> _flushQueue(String businessId) async {
    final rows = await _database
        .customSelect(
          '''
      SELECT *
      FROM sync_outbox
      WHERE business_id = ?
        AND state = 'pending'
        AND entity_type IN (
          'customer_note_create',
          'customer_note_update',
          'customer_note_photo',
          'customer_finding_create',
          'customer_finding_update',
          'customer_finding_photo'
        )
      ORDER BY id
      ''',
          variables: [Variable<String>(businessId)],
        )
        .get();

    for (final row in rows) {
      final id = row.read<int>('id');
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: id,
        );
        final current = await _database
            .customSelect(
              'SELECT entity_type,payload_json FROM sync_outbox WHERE id=?',
              variables: [Variable<int>(id)],
            )
            .getSingleOrNull();
        if (current == null) continue;
        final type = current.read<String>('entity_type');
        final payload = Map<String, dynamic>.from(
          jsonDecode(current.read<String>('payload_json')) as Map,
        );
        if (type.startsWith('customer_finding_')) {
          final cachedRows = await _loadList(
            businessId,
            payload['customer_id'].toString(),
            'findings',
          );
          await VehicleFindingActionsService(
            api: _api,
            database: _database,
            cache: _cache,
          ).recoverPendingCustomerCache(businessId, cachedRows);
        }
        if (type == 'customer_finding_photo' &&
            (payload['finding_id']?.toString() ?? '').startsWith(
              'local-finding-',
            )) {
          break;
        }
        if (type == 'customer_note_create') {
          await _flushNoteCreate(businessId, id, payload);
        } else if (type == 'customer_note_update') {
          await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => _api.updateCustomerNote(
              businessId,
              payload['note_id'].toString(),
              body: payload['body']?.toString() ?? '',
            ),
            outboxId: id,
          );
          await _deleteOutbox(businessId, id);
        } else if (type == 'customer_note_photo') {
          await _flushNotePhoto(businessId, id, payload);
        } else if (type == 'customer_finding_create') {
          await _flushFindingCreate(businessId, id, payload);
        } else if (type == 'customer_finding_update') {
          await LocalJobQuarantine.guardReplay(
            _database,
            businessId,
            () => _api.updateVehicleFinding(
              businessId,
              payload['finding_id'].toString(),
              body: payload['body']?.toString() ?? '',
            ),
            outboxId: id,
          );
          await _deleteOutbox(businessId, id);
        } else if (type == 'customer_finding_photo') {
          await _flushFindingPhoto(businessId, id, payload);
        }
      } catch (error) {
        if (error is LocalJobQuarantineException) rethrow;
        await _database.customStatement(
          '''
          UPDATE sync_outbox
          SET attempt_count = attempt_count + 1,
              last_attempt_at = ?,
              last_error = ?
          WHERE id = ?
          ''',
          [_unixNow(), error.toString(), id],
        );
        VehicleFindingActionsService.notifyChanged(businessId);
        break;
      }
    }
    await _database.customStatement(
      '''UPDATE local_findings SET sync_state='synced'
      WHERE business_id=? AND sync_state='pending' AND NOT EXISTS(
        SELECT 1 FROM sync_outbox o WHERE o.business_id=local_findings.business_id
        AND o.state IN ('pending','conflict') AND (
          o.entity_id=local_findings.id OR json_extract(o.payload_json,'\$.finding_id')=local_findings.id))''',
      [businessId],
    );
    await VehicleFindingActionsService(
      api: _api,
      database: _database,
      cache: _cache,
    ).flush(businessId);
    await OfflineWorkFindingsService(
      api: _api,
      database: _database,
    ).flush(businessId);
    await _database.customStatement(
      '''UPDATE local_findings SET sync_state='synced'
      WHERE business_id=? AND sync_state='pending' AND NOT EXISTS(
        SELECT 1 FROM sync_outbox o WHERE o.business_id=local_findings.business_id
        AND o.state IN ('pending','conflict') AND (
          o.entity_id=local_findings.id OR json_extract(o.payload_json,'\$.finding_id')=local_findings.id))''',
      [businessId],
    );
    VehicleFindingActionsService.notifyChanged(businessId);
  }

  Future<void> _flushNoteCreate(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final customerId = payload['customer_id'].toString();
    final localId = payload['local_note_id'].toString();
    final serverId = await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.createCustomerNote(
        businessId,
        customerId,
        body: payload['body']?.toString(),
      ),
      outboxId: outboxId,
    );

    await _database.transaction(() async {
      await LocalJobQuarantine.assertReplayAllowed(
        _database,
        businessId,
        outboxId: outboxId,
      );
      final photoRows = await _database
          .customSelect(
            '''
        SELECT id, payload_json
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type = 'customer_note_photo'
          AND state = 'pending'
        ''',
            variables: [Variable<String>(businessId)],
          )
          .get();
      for (final photoRow in photoRows) {
        final photoPayload = Map<String, dynamic>.from(
          jsonDecode(photoRow.read<String>('payload_json')) as Map,
        );
        if (photoPayload['note_id']?.toString() != localId) continue;
        photoPayload['note_id'] = serverId;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json = ? WHERE id = ?',
          [jsonEncode(photoPayload), photoRow.read<int>('id')],
        );
      }
      final rows = await _loadList(businessId, customerId, 'notes');
      final index = rows.indexWhere((row) => row['id']?.toString() == localId);
      if (index >= 0) {
        rows[index] = {...rows[index], 'id': serverId, 'sync_state': 'pending'};
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: outboxId,
        );
        await _saveList(businessId, customerId, 'notes', rows);
      }
      await _deleteOutbox(businessId, outboxId);
    });
  }

  Future<void> _flushNotePhoto(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final file = File(payload['local_file_path'].toString());
    final bytes = await file.readAsBytes();
    await LocalJobQuarantine.guardReplay(
      _database,
      businessId,
      () => _api.uploadCustomerNotePhoto(
        businessId,
        payload['note_id'].toString(),
        filename: payload['filename'].toString(),
        mimeType: payload['mime_type'].toString(),
        bytes: bytes,
        replayGuard: <T>(Future<T> Function() operation) =>
            LocalJobQuarantine.guardReplay<T>(
              _database,
              businessId,
              operation,
              outboxId: outboxId,
            ),
      ),
      outboxId: outboxId,
    );
    await _deleteOutbox(businessId, outboxId);
  }

  Future<void> _flushFindingCreate(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final customerId = payload['customer_id'].toString();
    final localId = payload['local_finding_id'].toString();
    var serverId = payload['_server_finding_id']?.toString() ?? '';
    final submittedBody =
        payload['_created_body']?.toString() ??
        payload['body']?.toString() ??
        '';
    if (serverId.isEmpty) {
      if (payload['_mutation_attempted'] == true) {
        throw StateError(
          'The earlier finding creation is not verified. '
          'The finding and photos are preserved locally; no duplicate was created.',
        );
      }
      payload['_mutation_attempted'] = true;
      await _database.customStatement(
        'UPDATE sync_outbox SET payload_json=? WHERE id=?',
        [jsonEncode(payload), outboxId],
      );
      serverId = await LocalJobQuarantine.guardReplay(
        _database,
        businessId,
        () => _api.createVehicleFindingForVehicle(
          businessId,
          customerId,
          payload['vehicle_id'].toString(),
          body: submittedBody,
          includeOnInvoice: payload['include_on_invoice'] == true,
        ),
        outboxId: outboxId,
      );
      final latest = await _database
          .customSelect(
            'SELECT payload_json FROM sync_outbox WHERE id=?',
            variables: [Variable<int>(outboxId)],
          )
          .getSingle();
      final acknowledged =
          Map<String, dynamic>.from(
              jsonDecode(latest.read<String>('payload_json')) as Map,
            )
            ..['_server_finding_id'] = serverId
            ..['_created_body'] = submittedBody;
      await _database.customStatement(
        'UPDATE sync_outbox SET payload_json=? WHERE id=?',
        [jsonEncode(acknowledged), outboxId],
      );
    }

    await _database.transaction(() async {
      await LocalJobQuarantine.assertReplayAllowed(
        _database,
        businessId,
        outboxId: outboxId,
      );
      final photoRows = await _database
          .customSelect(
            '''
        SELECT id, payload_json
        FROM sync_outbox
        WHERE business_id = ?
          AND entity_type = 'customer_finding_photo'
          AND state = 'pending'
        ''',
            variables: [Variable<String>(businessId)],
          )
          .get();
      for (final photoRow in photoRows) {
        final photoPayload = Map<String, dynamic>.from(
          jsonDecode(photoRow.read<String>('payload_json')) as Map,
        );
        if (photoPayload['finding_id']?.toString() != localId) continue;
        photoPayload['finding_id'] = serverId;
        await _database.customStatement(
          'UPDATE sync_outbox SET payload_json = ? WHERE id = ?',
          [jsonEncode(photoPayload), photoRow.read<int>('id')],
        );
      }
      await VehicleFindingActionsService(
        api: _api,
        database: _database,
        cache: _cache,
      ).remap(businessId, localId, serverId);
      final localRow = await _database
          .customSelect(
            'SELECT * FROM local_findings WHERE business_id=? AND id=?',
            variables: [
              Variable<String>(businessId),
              Variable<String>(localId),
            ],
          )
          .getSingleOrNull();
      final observed = await _database
          .customSelect(
            'SELECT id FROM local_findings WHERE business_id=? AND id=?',
            variables: [
              Variable<String>(businessId),
              Variable<String>(serverId),
            ],
          )
          .get();
      if (observed.isNotEmpty && localRow != null) {
        await _database.customStatement(
          "UPDATE local_findings SET body=?,status=?,repair_job_id=?,include_on_invoice=?,resolved_at=?,sync_state='pending' WHERE business_id=? AND id=?",
          [
            localRow.read<String>('body'),
            localRow.read<String>('status'),
            localRow.data['repair_job_id'],
            localRow.read<int>('include_on_invoice'),
            localRow.data['resolved_at'],
            businessId,
            serverId,
          ],
        );
        await _database.customStatement(
          'DELETE FROM local_findings WHERE business_id=? AND id=?',
          [businessId, localId],
        );
      } else {
        await _database.customStatement(
          'UPDATE local_findings SET id=? WHERE business_id=? AND id=?',
          [serverId, businessId, localId],
        );
      }
      if (localRow != null && localRow.read<String>('body') != submittedBody) {
        await _enqueue(
          businessId,
          'customer_finding_update',
          serverId,
          'update',
          {
            'customer_id': customerId,
            'finding_id': serverId,
            'body': localRow.read<String>('body'),
          },
        );
      }
      await _database.customStatement(
        'UPDATE local_finding_photos SET finding_id=? WHERE business_id=? AND finding_id=?',
        [serverId, businessId, localId],
      );
      final rows = await _loadList(businessId, customerId, 'findings');
      final index = rows.indexWhere((row) => row['id']?.toString() == localId);
      if (index >= 0) {
        rows[index] = {...rows[index], 'id': serverId, 'sync_state': 'pending'};
        await LocalJobQuarantine.assertReplayAllowed(
          _database,
          businessId,
          outboxId: outboxId,
        );
        await _saveList(businessId, customerId, 'findings', rows);
      }
      await _deleteOutbox(businessId, outboxId);
    });
  }

  Future<void> _flushFindingPhoto(
    String businessId,
    int outboxId,
    Map<String, dynamic> payload,
  ) async {
    final queued = await _database
        .customSelect(
          'SELECT entity_id FROM sync_outbox WHERE id=?',
          variables: [Variable<int>(outboxId)],
        )
        .getSingle();
    final photoId = queued.read<String>('entity_id');
    payload['operation_id'] ??= photoId;
    payload['local_photo_id'] ??= photoId;
    await _database.customStatement(
      "UPDATE sync_outbox SET entity_type='finding_photo',payload_json=?,last_error=NULL WHERE id=?",
      [jsonEncode(payload), outboxId],
    );
  }

  Future<void> _deleteOutbox(String businessId, int id) async {
    await LocalJobQuarantine.assertReplayAllowed(
      _database,
      businessId,
      outboxId: id,
    );
    await _database.customStatement('DELETE FROM sync_outbox WHERE id = ?', [
      id,
    ]);
  }
}
