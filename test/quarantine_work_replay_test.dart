import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_job_quarantine.dart';
import 'package:briskers_app/services/offline_customer_detail_write_service.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/services/offline_preinspection_service.dart';
import 'package:briskers_app/services/offline_work_findings_service.dart';

const _business = 'quarantine-shop';

class _ReplayApi extends BriskersApi {
  final calls = <String>[];
  Future<void> Function(String)? beforeResponse;

  Future<void> _call(String name) async {
    calls.add(name);
    await beforeResponse?.call(name);
  }

  @override
  Future<Map<String, dynamic>> syncSavePreInspection(
    String businessId, String jobId, {
    required String operationId,
    int? expectedRowVersion,
    String? notes,
    num? odometer,
  }) async {
    await _call('preinspection:$jobId');
    return {
      'status': 'applied',
      'inspection': {'id': 'inspection', 'job_id': jobId, 'notes': notes},
    };
  }

  @override
  Future<Map<String, dynamic>> syncSaveWorkSummary(
    String businessId, String jobId, {
    required String operationId,
    required int? expectedRowVersion,
    required String workSummary,
  }) async {
    await _call('work:$jobId');
    return {
      'status': 'applied',
      'visit': {
        'id': 'visit', 'job_id': jobId, 'visit_number': 1,
        'work_summary': workSummary, 'planned_hours': 0, 'row_version': 2,
      },
    };
  }

  @override
  Future<String> createJob(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
    String? id,
  }) async {
    await _call('create:$id');
    return id!;
  }

  @override
  Future<void> updateJob(
    String businessId, String jobId, {
    required String customerId,
    String? vehicleId,
    required String title,
    String? requestedWork,
    required num plannedHours,
  }) => _call('update:$jobId');

  @override
  Future<void> updateCustomerNote(
    String businessId, String noteId, {
    required String body,
  }) => _call('note:$noteId');

  @override
  Future<String> syncOfflineAppointmentCreate(
    String businessId, {
    required String operationId,
    required String customerId,
    String? vehicleId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    String? employeeId,
  }) async {
    await _call('appointment-create');
    return 'server-appointment';
  }

  @override
  Future<int> syncOfflineAppointmentCancel(
    String businessId, String appointmentId, {
    required String operationId,
    required int baseVersion,
  }) async {
    await _call('appointment-cancel');
    return baseVersion + 1;
  }

  @override
  Future<Map<String, dynamic>> syncRegisterPreInspectionPhoto(
    String businessId, String jobId, {
    required String operationId,
    required String filename,
    required String mimeType,
    String? note,
  }) async {
    await _call('inspection-register');
    return _registration;
  }

  @override
  Future<Map<String, dynamic>> syncRegisterFindingPhoto(
    String businessId, String findingId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    await _call('finding-register');
    return _registration;
  }

  Map<String, dynamic> get _registration => {
    'status': 'registered', 'attachment_id': 'server-attachment',
    'photo_id': 'server-photo', 'bucket': 'photos', 'key': 'photo-key',
  };

  @override
  Future<void> uploadRegisteredAttachment(
    String businessId, {
    required String bucket,
    required String key,
    required String attachmentId,
    required String mimeType,
    required Uint8List bytes,
    AttachmentReplayGuard? replayGuard,
  }) => _call('upload');

  @override
  Future<void> updateJobPreInspectionPhotoNote(
    String businessId, String photoId, String note,
  ) => _call('photo-note');
}

Future<void> _seedJob(BriskersLocalDatabase db, String id) =>
    db.customStatement(
      '''INSERT INTO local_jobs(id,business_id,access_scope,title,status)
         VALUES (?,?,'full','Queued job','open')''',
      [id, _business],
    );

Future<int> _enqueue(
  BriskersLocalDatabase db, String type, String entityId,
  Map<String, dynamic> payload,
) async {
  await db.customStatement(
    '''INSERT INTO sync_outbox
       (business_id,entity_type,entity_id,operation,payload_json,base_row_version)
       VALUES (?,?,?,'update',?,1)''',
    [_business, type, entityId, jsonEncode(payload)],
  );
  final row = await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
  return row.read<int>('id');
}

Future<void> _flush(
  String type, BriskersLocalDatabase db, _ReplayApi api,
) async {
  switch (type) {
    case 'preinspection':
    case 'preinspection_photo':
      return OfflinePreInspectionService(database: db, api: api).flush(_business);
    case 'work_summary':
    case 'finding_photo':
      return OfflineWorkFindingsService(database: db, api: api).flush(_business);
    case 'job_create':
    case 'job_admin':
      return OfflineJobAdminService(database: db, api: api).flush(_business);
    case 'customer_note_update':
      return OfflineCustomerDetailWriteService(database: db, api: api).flush(_business);
    case 'appointment_create':
      return AppointmentSyncService(database: db, api: api).flushCreates(_business);
    case 'appointment_cancel':
      return AppointmentSyncService(database: db, api: api).flushCancels(_business);
    case 'appointment_delete':
      return AppointmentSyncService(database: db, api: api).flushDeletes(_business);
    case 'appointment_edit':
      return AppointmentSyncService(database: db, api: api).flushEdits(_business);
    case 'appointment_checkin':
      await AppointmentSyncService(database: db, api: api).flush(_business);
      return;
    default:
      throw StateError('Unexpected replay test type: $type');
  }
}

void main() {
  for (final type in [
    'preinspection', 'work_summary', 'job_create', 'job_admin',
    'customer_note_update', 'appointment_create', 'appointment_cancel',
    'appointment_delete', 'appointment_edit', 'appointment_checkin',
  ]) {
    test('$type pauses unrelated queued work before touching the network', () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final api = _ReplayApi();
      await _seedJob(db, 'revoked');
      final id = await _enqueue(db, type, 'allowed', {
        'operation_id': 'unchanged-operation', 'job_id': 'allowed',
        'customer_id': 'customer', 'note_id': 'note', 'body': 'Unsent work',
      });
      final before = await db.customSelect(
        'SELECT payload_json FROM sync_outbox WHERE id=?',
        variables: [Variable<int>(id)],
      ).getSingle();
      await LocalJobQuarantine.quarantineJobs(db, _business, ['revoked']);

      await expectLater(_flush(type, db, api), throwsA(isA<LocalJobQuarantineException>()));

      expect(api.calls, isEmpty);
      final queued = await db.customSelect(
        'SELECT payload_json,attempt_count FROM sync_outbox WHERE id=?',
        variables: [Variable<int>(id)],
      ).getSingle();
      expect(queued.read<String>('payload_json'), before.read<String>('payload_json'));
      expect(queued.read<int>('attempt_count'), 0);
    });
  }

  test('preloaded Job creates cannot replay archived rows after pause resolves', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _ReplayApi();
    final service = OfflineJobAdminService(database: db, api: api);
    final first = await service.queueJobCreate(_business,
      customerId: 'customer', customerName: 'Customer', title: 'First');
    final second = await service.queueJobCreate(_business,
      customerId: 'customer', customerName: 'Customer', title: 'Second');
    api.beforeResponse = (call) async {
      if (call != 'update:$first') return;
      await LocalJobQuarantine.quarantineJobs(db, _business, [second]);
      await LocalJobQuarantine.classifyJobs(db, _business, [second], cleanupJobIds: {});
    };

    await expectLater(service.flushCreates(_business),
      throwsA(isA<LocalJobQuarantineException>()));

    expect(api.calls, ['create:$first', 'update:$first']);
    final jobs = await db.customSelect('SELECT id,sync_state FROM local_jobs').get();
    expect(jobs.length, 1);
    expect(jobs.single.read<String>('id'), first);
    // A revocation changed the business generation during the first Job's
    // update. Preserve its server receipts and pending operation for review
    // instead of acknowledging or replaying across that boundary.
    expect(jobs.single.read<String>('sync_state'), 'pending');
    final queue = await db.customSelect(
      'SELECT id,entity_id FROM sync_outbox WHERE business_id=?',
      variables: [const Variable<String>(_business)],
    ).get();
    expect(queue.length, 1);
    expect(queue.single.read<String>('entity_id'), first);
    final receipts = await db.customSelect(
      'SELECT response_json FROM local_job_recovery_receipts '
      'WHERE business_id=? AND outbox_id=? ORDER BY id',
      variables: [const Variable<String>(_business), Variable<int>(queue.single.read<int>('id'))],
    ).get();
    expect(receipts.map((row) => jsonDecode(row.read<String>('response_json'))),
      [first, null]);
    await expectLater(service.flushCreates(_business),
      throwsA(isA<LocalJobQuarantineException>()));
    expect(api.calls, ['create:$first', 'update:$first']);
  });

  test('late work acknowledgement stays in recovery after classification', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _ReplayApi();
    await _seedJob(db, 'revoked');
    await db.customStatement(
      '''INSERT INTO local_job_visits
         (id,business_id,job_id,visit_number,work_summary,sync_state)
         VALUES ('visit',?,'revoked',1,'Original unsent bytes','pending')''',
      [_business],
    );
    final id = await _enqueue(db, 'work_summary', 'visit', {
      'operation_id': 'original-op', 'job_id': 'revoked', 'visit_id': 'visit',
      'work_summary': 'Original unsent bytes',
    });
    final entered = Completer<void>();
    final release = Completer<void>();
    api.beforeResponse = (_) async {
      entered.complete();
      await release.future;
    };
    final replay = _flush('work_summary', db, api);
    final rejected = expectLater(replay, throwsA(isA<LocalJobQuarantineException>()));
    await entered.future;
    await LocalJobQuarantine.quarantineJobs(db, _business, ['revoked']);
    await LocalJobQuarantine.classifyJobs(db, _business, ['revoked'], cleanupJobIds: {});
    release.complete();
    await rejected;

    expect(await db.customSelect('SELECT * FROM local_job_visits').get(), isEmpty);
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
    final receipt = await db.customSelect(
      'SELECT response_json FROM local_job_recovery_receipts WHERE outbox_id=?',
      variables: [Variable<int>(id)],
    ).getSingle();
    final response = jsonDecode(receipt.read<String>('response_json')) as Map;
    expect((response['visit'] as Map)['work_summary'], 'Original unsent bytes');
    final archived = await db.customSelect(
      "SELECT row_json FROM local_job_recovery_rows WHERE table_name='sync_outbox'",
    ).getSingle();
    final original = jsonDecode(archived.read<String>('row_json')) as Map;
    expect((jsonDecode(original['payload_json'] as String) as Map)['operation_id'], 'original-op');
  });

  for (final type in ['preinspection_photo', 'finding_photo']) {
    test('$type retains late registration and never uploads archived bytes', () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final directory = await Directory.systemTemp.createTemp('quarantine-photo-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/photo.jpg');
      await file.writeAsBytes([1, 2, 3, 4], flush: true);
      final api = _ReplayApi();
      await _seedJob(db, 'revoked');
      if (type == 'preinspection_photo') {
        await db.customStatement(
          "INSERT INTO local_pre_inspections(id,business_id,job_id) VALUES ('parent',?,'revoked')",
          [_business],
        );
        await db.customStatement(
          '''INSERT INTO local_pre_inspection_photos
             (id,business_id,inspection_id,attachment_id,local_file_path,upload_state)
             VALUES ('photo',?,'parent','photo',?,'pending')''',
          [_business, file.path],
        );
      } else {
        await db.customStatement(
          '''INSERT INTO local_findings(id,business_id,found_job_id,body,status)
             VALUES ('parent',?,'revoked','Unsent finding','open')''',
          [_business],
        );
        await db.customStatement(
          '''INSERT INTO local_finding_photos
             (id,business_id,finding_id,attachment_id,local_file_path,upload_state)
             VALUES ('photo',?,'parent','photo',?,'pending')''',
          [_business, file.path],
        );
      }
      await _enqueue(db, type, 'photo', {
        'operation_id': 'photo-op', 'job_id': 'revoked', 'finding_id': 'parent',
        'local_photo_id': 'photo', 'local_file_path': file.path,
        'filename': 'photo.jpg', 'mime_type': 'image/jpeg',
      });
      api.beforeResponse = (_) async {
        await LocalJobQuarantine.quarantineJobs(db, _business, ['revoked']);
        await LocalJobQuarantine.classifyJobs(db, _business, ['revoked'], cleanupJobIds: {});
      };

      await expectLater(_flush(type, db, api), throwsA(isA<LocalJobQuarantineException>()));

      expect(api.calls, [type == 'preinspection_photo' ? 'inspection-register' : 'finding-register']);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
      final receipt = await db.customSelect('SELECT response_json FROM local_job_recovery_receipts').getSingle();
      expect((jsonDecode(receipt.read<String>('response_json')) as Map)['attachment_id'], 'server-attachment');
    });
  }

  test('late appointment creation does not run dependent cancellation or acknowledge locally', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _ReplayApi();
    final service = AppointmentSyncService(database: db, api: api);
    await _seedJob(db, 'revoked');
    final starts = DateTime.utc(2026, 10, 13, 15);
    final localId = await service.queueCreate(_business,
      customerId: 'customer', title: 'Cancelled pending appointment',
      startsAt: starts, endsAt: starts.add(const Duration(hours: 1)));
    await service.cancelPendingCreate(_business, localId, canManage: true);
    api.beforeResponse = (_) => LocalJobQuarantine.quarantineJobs(db, _business, ['revoked']);

    await expectLater(service.flushCreates(_business), throwsA(isA<LocalJobQuarantineException>()));

    expect(api.calls, ['appointment-create']);
    final local = await db.customSelect('SELECT id,sync_state FROM local_appointments').getSingle();
    expect(local.read<String>('id'), localId);
    expect(local.read<String>('sync_state'), isNot('synced'));
    final receipt = await db.customSelect('SELECT response_json FROM local_job_recovery_receipts').getSingle();
    expect(jsonDecode(receipt.read<String>('response_json')), 'server-appointment');
  });

  test('ordinary customer note replay keeps its order when no Job is quarantined', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _ReplayApi();
    for (final id in ['first', 'second']) {
      await _enqueue(db, 'customer_note_update', id, {'note_id': id, 'body': id});
    }
    await _flush('customer_note_update', db, api);
    expect(api.calls, ['note:first', 'note:second']);
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
  });
}
