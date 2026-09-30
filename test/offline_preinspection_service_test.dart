import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_preinspection_service.dart';

class _FakeApi extends BriskersApi {
  _FakeApi({this.conflict = false});

  final bool conflict;
  var uploadCount = 0;

  @override
  Future<Map<String, dynamic>> syncSavePreInspection(
    String businessId,
    String jobId, {
    required String operationId,
    int? expectedRowVersion,
    String? notes,
    num? odometer,
  }) async {
    if (conflict) {
      return {
        'status': 'conflict',
        'reason': 'row_version_mismatch',
        'server': {
          'id': 'server-inspection',
          'job_id': jobId,
          'vehicle_id': 'vehicle-1',
          'inspected_at': '2026-09-30T18:00:00Z',
          'odometer': 49999,
          'notes': 'Server version',
          'created_by': 'user-server',
          'updated_at': '2026-09-30T18:05:00Z',
          'row_version': 8,
        },
      };
    }

    return {
      'status': 'applied',
      'inspection': {
        'id': 'server-inspection',
        'job_id': jobId,
        'vehicle_id': 'vehicle-1',
        'inspected_at': '2026-09-30T18:00:00Z',
        'odometer': odometer,
        'notes': notes,
        'created_by': 'user-1',
        'updated_at': '2026-09-30T18:05:00Z',
        'row_version': 1,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncRegisterPreInspectionPhoto(
    String businessId,
    String jobId, {
    required String operationId,
    required String filename,
    required String mimeType,
    String? note,
  }) async {
    return {
      'status': 'registered',
      'inspection': {
        'id': 'server-inspection',
        'job_id': jobId,
        'vehicle_id': 'vehicle-1',
        'inspected_at': '2026-09-30T18:00:00Z',
        'odometer': 50000,
        'notes': 'Local notes',
        'created_by': 'user-1',
        'updated_at': '2026-09-30T18:05:00Z',
        'row_version': 1,
      },
      'photo_id': 'server-photo',
      'attachment_id': 'server-attachment',
      'bucket': 'briskers-private',
      'key': 'business-1/job-pre-inspections/job-1/server-attachment',
    };
  }

  @override
  Future<void> updateJobPreInspectionPhotoNote(
    String businessId,
    String photoId,
    String note,
  ) async {}

  @override
  Future<void> uploadRegisteredAttachment(
    String businessId, {
    required String bucket,
    required String key,
    required String attachmentId,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    uploadCount++;
    expect(bytes, isNotEmpty);
  }
}

void main() {
  test('offline inspection and photo flush in dependency order', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeApi();
    final temp = await Directory.systemTemp.createTemp('briskers-offline-test-');
    final service = OfflinePreInspectionService(
      api: api,
      database: database,
      mediaDirectoryProvider: () async => temp,
    );

    await service.saveLocalInspection(
      'business-1',
      'job-1',
      vehicleId: 'vehicle-1',
      notes: 'Local notes',
      odometer: 50000,
    );

    await service.stagePhoto(
      'business-1',
      'job-1',
      vehicleId: 'vehicle-1',
      fallbackOdometer: 50000,
      filename: 'damage.jpg',
      mimeType: 'image/jpeg',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      note: 'Front bumper',
    );

    final before = await database.customSelect(
      "SELECT id, entity_type FROM sync_outbox ORDER BY id",
    ).get();
    expect(before, hasLength(2));
    expect(before.first.read<String>('entity_type'), 'preinspection');
    expect(before.last.read<String>('entity_type'), 'preinspection_photo');

    await service.flush('business-1');

    final outbox = await database.customSelect(
      'SELECT COUNT(*) AS count FROM sync_outbox',
    ).getSingle();
    expect(outbox.read<int>('count'), 0);

    final inspection = await database.customSelect(
      '''
      SELECT id, sync_state, row_version, notes
      FROM local_pre_inspections
      WHERE business_id = ? AND job_id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('job-1'),
      ],
    ).getSingle();

    expect(inspection.read<String>('id'), 'server-inspection');
    expect(inspection.read<String>('sync_state'), 'synced');
    expect(inspection.read<int>('row_version'), 1);
    expect(inspection.read<String>('notes'), 'Local notes');

    final photo = await database.customSelect(
      '''
      SELECT id, attachment_id, upload_state, local_file_path
      FROM local_pre_inspection_photos
      WHERE business_id = ?
      ''',
      variables: [const Variable<String>('business-1')],
    ).getSingle();

    expect(photo.read<String>('id'), 'server-photo');
    expect(photo.read<String>('attachment_id'), 'server-attachment');
    expect(photo.read<String>('upload_state'), 'synced');
    expect(await File(photo.read<String>('local_file_path')).exists(), isTrue);
    expect(api.uploadCount, 1);

    await database.close();
    await temp.delete(recursive: true);
  });

  test('version conflict preserves local inspection and marks conflict', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = OfflinePreInspectionService(
      api: _FakeApi(conflict: true),
      database: database,
      mediaDirectoryProvider: () async => Directory.systemTemp,
    );

    await database.customStatement(
      '''
      INSERT INTO local_pre_inspections (
        id, business_id, job_id, vehicle_id, inspected_at,
        odometer, notes, created_by, server_updated_at,
        row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
      ''',
      [
        'server-inspection',
        'business-1',
        'job-1',
        'vehicle-1',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        49990,
        'Old local',
        'user-1',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        7,
      ],
    );

    await service.saveLocalInspection(
      'business-1',
      'job-1',
      vehicleId: 'vehicle-1',
      notes: 'Mechanic offline edit',
      odometer: 50001,
    );

    await service.flush('business-1');

    final inspection = await database.customSelect(
      '''
      SELECT notes, odometer, sync_state, row_version
      FROM local_pre_inspections
      WHERE business_id = ? AND job_id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('job-1'),
      ],
    ).getSingle();

    expect(inspection.read<String>('notes'), 'Mechanic offline edit');
    expect(inspection.data['odometer'], 50001.0);
    expect(inspection.read<String>('sync_state'), 'conflict');
    expect(inspection.read<int>('row_version'), 7);

    final outbox = await database.customSelect(
      "SELECT state, last_error FROM sync_outbox WHERE entity_type = 'preinspection'",
    ).getSingle();

    expect(outbox.read<String>('state'), 'conflict');
    expect(outbox.read<String>('last_error'), contains('row_version_mismatch'));

    await database.close();
  });
}
