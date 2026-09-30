import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_work_findings_service.dart';

class _FakeApi extends BriskersApi {
  _FakeApi({
    this.workConflict = false,
    this.findingConflict = false,
  });

  final bool workConflict;
  final bool findingConflict;
  var uploadedPhotos = 0;
  String? createdFindingBody;

  @override
  Future<Map<String, dynamic>> syncSaveWorkSummary(
    String businessId,
    String jobId, {
    required String operationId,
    required int? expectedRowVersion,
    required String workSummary,
  }) async {
    if (workConflict) {
      return {
        'status': 'conflict',
        'reason': 'row_version_mismatch',
        'server': {
          'id': 'visit-1',
          'job_id': jobId,
          'visit_number': 1,
          'reason': 'Initial visit',
          'planned_hours': 2,
          'work_summary': 'Server work',
          'opened_at': '2026-09-30T18:00:00Z',
          'closed_at': null,
          'updated_at': '2026-09-30T18:30:00Z',
          'row_version': 5,
        },
      };
    }

    return {
      'status': 'applied',
      'visit': {
        'id': 'visit-1',
        'job_id': jobId,
        'visit_number': 1,
        'reason': 'Initial visit',
        'planned_hours': 2,
        'work_summary': workSummary,
        'opened_at': '2026-09-30T18:00:00Z',
        'closed_at': null,
        'updated_at': '2026-09-30T18:31:00Z',
        'row_version': 5,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncCreateFinding(
    String businessId,
    String jobId, {
    required String operationId,
    required String body,
    bool includeOnInvoice = false,
  }) async {
    createdFindingBody = body;
    return {
      'status': 'applied',
      'finding': {
        'id': 'finding-server-1',
        'body': body,
        'status': 'open',
        'include_on_invoice': includeOnInvoice,
        'created_at': '2026-09-30T19:00:00Z',
        'updated_at': '2026-09-30T19:00:00Z',
        'row_version': 1,
        'created_by': 'user-1',
        'vehicle_id': 'vehicle-1',
        'found_job_id': jobId,
        'repair_job_id': null,
        'resolved_job_id': null,
        'resolved_at': null,
        'can_edit': true,
        'can_delete': false,
        'attachments': <dynamic>[],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncUpdateFinding(
    String businessId,
    String findingId, {
    required String operationId,
    required int? expectedRowVersion,
    required String body,
  }) async {
    if (findingConflict) {
      return {
        'status': 'conflict',
        'reason': 'row_version_mismatch',
        'server': {
          'id': findingId,
          'body': 'Server finding',
          'status': 'open',
          'include_on_invoice': false,
          'created_at': '2026-09-30T19:00:00Z',
          'updated_at': '2026-09-30T19:30:00Z',
          'row_version': 4,
          'created_by': 'user-1',
          'vehicle_id': 'vehicle-1',
          'found_job_id': 'job-1',
        },
      };
    }

    return {
      'status': 'applied',
      'finding': {
        'id': findingId,
        'body': body,
        'status': 'open',
        'include_on_invoice': false,
        'created_at': '2026-09-30T19:00:00Z',
        'updated_at': '2026-09-30T19:31:00Z',
        'row_version': (expectedRowVersion ?? 0) + 1,
        'created_by': 'user-1',
        'vehicle_id': 'vehicle-1',
        'found_job_id': 'job-1',
        'repair_job_id': null,
        'resolved_job_id': null,
        'resolved_at': null,
        'can_edit': true,
        'can_delete': false,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncRegisterFindingPhoto(
    String businessId,
    String findingId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    expect(findingId, 'finding-server-1');
    return {
      'status': 'registered',
      'attachment_id': 'attachment-server-1',
      'bucket': 'briskers-private',
      'key': 'business-1/vehicle-findings/vehicle-1/finding-server-1/a1',
    };
  }

  @override
  Future<void> uploadRegisteredAttachment(
    String businessId, {
    required String bucket,
    required String key,
    required String attachmentId,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    uploadedPhotos++;
    expect(bytes, isNotEmpty);
  }
}

void main() {
  test('work performed saves locally then flushes', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeApi();
    final service = OfflineWorkFindingsService(
      api: api,
      database: database,
      mediaDirectoryProvider: () async => Directory.systemTemp,
    );

    await database.customStatement(
      '''
      INSERT INTO local_job_visits (
        id, business_id, job_id, visit_number, reason,
        planned_hours, work_summary, opened_at, server_updated_at,
        row_version, sync_state
      ) VALUES (?, ?, ?, 1, ?, 2, ?, ?, ?, 4, 'synced')
      ''',
      [
        'visit-1',
        'business-1',
        'job-1',
        'Initial visit',
        'Old work',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );

    final local = await service.saveLocalWorkSummary(
      'business-1',
      'job-1',
      workSummary: 'Replaced front brake pads',
    );
    expect(local['work_summary'], 'Replaced front brake pads');
    expect(local['sync_state'], 'pending');

    await service.flush('business-1');

    final synced = await service.loadLocalCurrentVisit(
      'business-1',
      'job-1',
    );
    expect(synced!['work_summary'], 'Replaced front brake pads');
    expect(synced['sync_state'], 'synced');
    expect(synced['row_version'], 5);

    final outbox = await database.customSelect(
      "SELECT COUNT(*) AS count FROM sync_outbox",
    ).getSingle();
    expect(outbox.read<int>('count'), 0);

    await database.close();
  });

  test('work performed conflict preserves local edit', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = OfflineWorkFindingsService(
      api: _FakeApi(workConflict: true),
      database: database,
      mediaDirectoryProvider: () async => Directory.systemTemp,
    );

    await database.customStatement(
      '''
      INSERT INTO local_job_visits (
        id, business_id, job_id, visit_number,
        work_summary, opened_at, row_version, sync_state
      ) VALUES (?, ?, ?, 1, ?, ?, 4, 'synced')
      ''',
      [
        'visit-1',
        'business-1',
        'job-1',
        'Old work',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );

    await service.saveLocalWorkSummary(
      'business-1',
      'job-1',
      workSummary: 'Mechanic offline work',
    );
    await service.flush('business-1');

    final local = await service.loadLocalCurrentVisit(
      'business-1',
      'job-1',
    );
    expect(local!['work_summary'], 'Mechanic offline work');
    expect(local['sync_state'], 'conflict');

    await database.close();
  });

  test('new finding can be edited and photographed before first sync', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final api = _FakeApi();
    final temp = await Directory.systemTemp.createTemp(
      'briskers-finding-test-',
    );
    final service = OfflineWorkFindingsService(
      api: api,
      database: database,
      mediaDirectoryProvider: () async => temp,
    );

    final created = await service.createLocalFinding(
      'business-1',
      'job-1',
      vehicleId: 'vehicle-1',
      body: 'Initial local finding',
    );
    final localId = created['id'].toString();
    expect(localId, startsWith('local-finding-'));

    await service.updateLocalFinding(
      'business-1',
      'job-1',
      localId,
      body: 'Edited before sync',
    );

    await service.stageFindingPhoto(
      'business-1',
      'job-1',
      localId,
      filename: 'leak.jpg',
      mimeType: 'image/jpeg',
      bytes: Uint8List.fromList([8, 9, 10]),
    );

    await service.flush('business-1');

    expect(api.createdFindingBody, 'Edited before sync');
    expect(api.uploadedPhotos, 1);

    final findings = await service.loadLocalFindings(
      'business-1',
      'vehicle-1',
    );
    expect(findings, hasLength(1));
    expect(findings.single['id'], 'finding-server-1');
    expect(findings.single['body'], 'Edited before sync');
    expect(findings.single['sync_state'], 'synced');

    final attachments = List<dynamic>.from(
      findings.single['attachments'] ?? const <dynamic>[],
    );
    expect(attachments, hasLength(1));
    expect(
      (attachments.single as Map)['attachment_id'],
      'attachment-server-1',
    );
    expect(
      (attachments.single as Map)['upload_state'],
      'synced',
    );

    final outbox = await database.customSelect(
      "SELECT COUNT(*) AS count FROM sync_outbox",
    ).getSingle();
    expect(outbox.read<int>('count'), 0);

    await database.close();
    await temp.delete(recursive: true);
  });

  test('finding update conflict preserves local text', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = OfflineWorkFindingsService(
      api: _FakeApi(findingConflict: true),
      database: database,
      mediaDirectoryProvider: () async => Directory.systemTemp,
    );

    await database.customStatement(
      '''
      INSERT INTO local_findings (
        id, business_id, vehicle_id, found_job_id,
        body, status, include_on_invoice, created_at,
        can_edit, can_delete, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, 'open', 0, ?, 1, 0, 3, 'synced')
      ''',
      [
        'finding-1',
        'business-1',
        'vehicle-1',
        'job-1',
        'Old finding',
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
    );

    await service.updateLocalFinding(
      'business-1',
      'job-1',
      'finding-1',
      body: 'Mechanic offline finding',
    );
    await service.flush('business-1');

    final finding = await database.customSelect(
      '''
      SELECT body, sync_state, row_version
      FROM local_findings
      WHERE business_id = ? AND id = ?
      ''',
      variables: [
        const Variable<String>('business-1'),
        const Variable<String>('finding-1'),
      ],
    ).getSingle();

    expect(finding.read<String>('body'), 'Mechanic offline finding');
    expect(finding.read<String>('sync_state'), 'conflict');
    expect(finding.read<int>('row_version'), 3);

    await database.close();
  });
}
