import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/local_document_repository.dart';

void main() {
  test('imported completed jobs sort by number, not created timestamp',
      () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final repository = LocalJobRepository(database: database);
    // All imported with nearly identical timestamps in an order unrelated
    // to their historical job numbers.
    for (final item in [
      ('6330', 300),
      ('6329', 299),
      ('6220', 298),
      ('6328', 297),
      ('6187', 296),
      ('6327', 295),
    ]) {
      await database.customStatement(
        '''
        INSERT INTO local_jobs (
          id, business_id, access_scope, job_number, title,
          status, created_at, sync_state
        ) VALUES (?, ?, 'all', ?, 'Service', 'completed', ?, 'synced')
        ''',
        [
          'job-${item.$1}',
          'shop-1',
          'MB-${item.$1}',
          item.$2,
        ],
      );
    }
    final rows = await repository.listJobs('shop-1');
    expect(
      rows.map((row) => row['job_number']).toList(),
      ['MB-6330', 'MB-6329', 'MB-6328', 'MB-6327',
       'MB-6220', 'MB-6187'],
    );
    await database.close();
  });


  test('local job repository rebuilds list and detail snapshots', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final repository = LocalJobRepository(database: database);

    final now =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    await database.customStatement(
      '''
      INSERT INTO local_job_statuses (
        business_id, code, name, color_hex, icon_key, sort_order
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        'business-1',
        'open',
        'Open',
        '#2563EB',
        'build',
        10,
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_jobs (
        id, business_id, access_scope, job_number, title, requested_work,
        status, status_name, status_color, status_icon,
        customer_id, customer_name, customer_problem_flag,
        customer_problem_flag_note, capabilities_json,
        pending_request_count, payment_state,
        vehicle_id, vehicle_label, vehicle_vin, vehicle_plate,
        planned_hours, odometer_in,
        assigned_employee_id, assigned_employee_name, assigned_position,
        is_unassigned, created_at, server_updated_at, row_version, sync_state
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?, 'synced'
      )
      ''',
      [
        'job-1',
        'business-1',
        'assigned',
        '1001',
        'Brake repair',
        'Brake noise when stopping',
        'open',
        'Open',
        '#2563EB',
        'build',
        'customer-1',
        'Test Customer',
        1,
        'Call before additional work',
        jsonEncode({
          'manage_job': false,
          'view_financial': false,
          'request_job': false,
          'edit_work': true,
          'edit_findings': true,
          'edit_inspection': true,
          'delete_records': false,
        }),
        0,
        null,
        'vehicle-1',
        '2020 BMW X5',
        'TESTVIN',
        'ABC123',
        2.5,
        50000,
        'employee-1',
        'Mike Mechanic',
        'Mechanic',
        0,
        now,
        now,
        4,
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_job_assignments (
        assignment_id, business_id, job_id, employee_id,
        employee_name, position, active
      ) VALUES (?, ?, ?, ?, ?, ?, 1)
      ''',
      [
        'assignment-1',
        'business-1',
        'job-1',
        'employee-1',
        'Mike Mechanic',
        'Mechanic',
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_job_visits (
        id, business_id, job_id, visit_number, reason,
        planned_hours, work_summary, opened_at,
        server_updated_at, row_version, sync_state
      ) VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, 'pending')
      ''',
      [
        'visit-1',
        'business-1',
        'job-1',
        'Initial visit',
        2.5,
        'Pads removed',
        now,
        now,
        3,
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_pre_inspections (
        id, business_id, job_id, vehicle_id, inspected_at,
        odometer, notes, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')
      ''',
      [
        'inspection-1',
        'business-1',
        'job-1',
        'vehicle-1',
        now,
        50000,
        'Scratch on bumper',
        2,
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_pre_inspection_photos (
        id, business_id, inspection_id, attachment_id,
        local_file_path, filename, mime_type,
        can_edit_note, can_delete, upload_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, 'pending')
      ''',
      [
        'photo-1',
        'business-1',
        'inspection-1',
        'photo-1',
        '/tmp/preinspection.jpg',
        'preinspection.jpg',
        'image/jpeg',
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_findings (
        id, business_id, vehicle_id, found_job_id,
        body, status, include_on_invoice, created_at,
        can_edit, can_delete, row_version, sync_state
      ) VALUES (?, ?, ?, ?, ?, 'open', 0, ?, 1, 1, 2, 'pending')
      ''',
      [
        'finding-1',
        'business-1',
        'vehicle-1',
        'job-1',
        'Front pads worn',
        now,
      ],
    );

    await database.customStatement(
      '''
      INSERT INTO local_finding_photos (
        id, business_id, finding_id, attachment_id,
        local_file_path, filename, mime_type,
        can_delete, upload_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 'pending')
      ''',
      [
        'finding-photo-1',
        'business-1',
        'finding-1',
        'finding-photo-1',
        '/tmp/finding.jpg',
        'finding.jpg',
        'image/jpeg',
      ],
    );

    final list = await repository.listJobs('business-1');
    expect(list, hasLength(1));
    expect(list.single['job_number'], '1001');
    expect(list.single['open_findings'], 1);
    expect(list.single['assigned_employee'], 'Mike Mechanic');
    expect(list.single['_local_snapshot'], true);

    final snapshot = await repository.jobDetail(
      'business-1',
      'job-1',
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.job['customer_problem_flag'], true);
    expect(
      (snapshot.job['capabilities'] as Map)['edit_work'],
      true,
    );

    final assignments =
        List<dynamic>.from(snapshot.job['assignments'] as List);
    expect(assignments, hasLength(1));

    final visits =
        List<dynamic>.from(snapshot.job['visits'] as List);
    expect(visits, hasLength(1));
    expect((visits.single as Map)['work_summary'], 'Pads removed');
    expect((visits.single as Map)['sync_state'], 'pending');

    expect(snapshot.preInspection, isNotNull);
    expect(snapshot.preInspection!['notes'], 'Scratch on bumper');
    final inspectionPhotos = List<dynamic>.from(
      snapshot.preInspection!['photos'] as List,
    );
    expect((inspectionPhotos.single as Map)['can_delete'], false);

    expect(snapshot.findings, hasLength(1));
    expect(snapshot.findings.single['body'], 'Front pads worn');
    expect(snapshot.findings.single['can_delete'], false);
    final findingPhotos = List<dynamic>.from(
      snapshot.findings.single['attachments'] as List,
    );
    expect((findingPhotos.single as Map)['can_delete'], false);

    expect(snapshot.statuses, hasLength(1));
    expect(snapshot.statuses.single['name'], 'Open');

    await database.close();
  });

  test('local document repository exposes creation time for stale detail recovery',
      () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final documents = LocalDocumentRepository(database: database);
    final created =
        DateTime.utc(2026, 10, 7, 0, 15).millisecondsSinceEpoch ~/ 1000;

    await database.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, kind, status, converted, total,
        created_at, row_version, sync_state
      ) VALUES (?, ?, 'estimate', 'draft', 0, 0, ?, 1, 'synced')
      ''',
      ['estimate-1', 'business-1', created],
    );

    final value = await documents.createdAtForDocument(
      'business-1',
      'estimate-1',
    );

    expect(value, isNotNull);
    expect(DateTime.parse(value!).toUtc(), DateTime.utc(2026, 10, 7, 0, 15));

    await database.close();
  });

}
