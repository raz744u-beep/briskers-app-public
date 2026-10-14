import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_repository.dart';

void main() {
  late BriskersLocalDatabase db;
  late LocalJobRepository jobs;

  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    jobs = LocalJobRepository(database: db);
  });
  tearDown(() => db.close());

  Future<void> insertJob(
    String id,
    String number, {
    int createdAt = 100,
    String syncState = 'pending',
    String status = 'open',
    String business = 'shop',
    String title = 'Offline repair',
  }) => db.customStatement(
    '''
    INSERT INTO local_jobs (
      id, business_id, access_scope, job_number, title, status,
      created_at, sync_state, customer_id, customer_name, vehicle_label
    ) VALUES (?, ?, 'full', ?, ?, ?, ?, ?, 'customer', 'Customer', 'Test car')
    ''',
    [id, business, number, title, status, createdAt, syncState],
  );

  test('All pins newest TEMP and Pending sync jobs before the 30-row limit', () async {
    for (var i = 0; i < 40; i++) {
      await insertJob('historical-$i', 'J-${6000 + i}',
          createdAt: 10000 + i, syncState: 'synced');
    }
    await insertJob('temp-old', 'TEMP-A0000001', createdAt: 200);
    await insertJob('temp-new', 'TEMP-B0000002', createdAt: 300,
        // A finished upload must not hide a job whose number has not arrived.
        syncState: 'synced', status: 'completed');
    await insertJob('direct-new', 'Pending sync', createdAt: 400,
        syncState: 'synced');
    await insertJob('other-shop', 'TEMP-OTHER', createdAt: 500, business: 'other');

    final firstPage = await jobs.listJobs('shop', limit: 30);
    expect(firstPage, hasLength(30));
    expect(firstPage.take(3).map((row) => row['id']),
        ['direct-new', 'temp-new', 'temp-old']);
    expect(firstPage[3]['job_number'], 'J-6039');
    expect(await jobs.jobCount('shop'), 43);
    final secondPage = await jobs.listJobs('shop', limit: 30, offset: 30);
    expect(secondPage, hasLength(13));
    expect({...firstPage, ...secondPage}.map((row) => row['id']).toSet(),
        hasLength(43));
  });

  test('provisional pinning still respects status and text filters', () async {
    await insertJob('open', 'TEMP-A1', status: 'open');
    await insertJob('done', 'TEMP-B2', status: 'completed');
    await insertJob('real', 'J-50', syncState: 'synced');
    expect((await jobs.listJobs('shop', status: 'completed'))
        .map((row) => row['id']), ['done']);
    expect((await jobs.listJobs('shop', search: 'temp-a1'))
        .map((row) => row['id']), ['open']);
    expect(await jobs.jobCount('shop', search: 'temp-a1'), 1);
  });

  test('number lookup is business scoped and ignores blank stored values', () async {
    await insertJob('job', ' TEMP-ABC12345 ');
    await insertJob('blank', '   ');
    expect(await jobs.jobNumberForJob('shop', 'job'), 'TEMP-ABC12345');
    expect(await jobs.jobNumberForJob('other', 'job'), isNull);
    expect(await jobs.jobNumberForJob('shop', 'blank'), isNull);
    expect(await jobs.jobNumberForJob('shop', 'missing'), isNull);
  });

  test('successful invoice sync keeps exactly one Job before number pull', () async {
    await insertJob('local-job-1', 'TEMP-ABC12345');
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind) "
      "VALUES ('invoice','shop','local-job-1','invoice')",
    );
    await db.customStatement(
      "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json) "
      "VALUES ('shop','job_admin','local-job-1','update','{}')",
    );
    expect(await jobs.remapProvisionalJob('shop', 'local-job-1', 'server-job'),
        'TEMP-ABC12345');
    // Replay after a cache/write interruption must not drop or duplicate it.
    expect(await jobs.remapProvisionalJob('shop', 'local-job-1', 'server-job'),
        'TEMP-ABC12345');
    final rows = await jobs.listJobs('shop');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'server-job');
    expect(rows.single['title'], 'Offline repair');
    expect(rows.single['customer_name'], 'Customer');
    expect(rows.single['vehicle'], 'Test car');
    expect((await db.customSelect('SELECT job_id FROM local_documents').getSingle())
        .read<String>('job_id'), 'server-job');
    expect((await db.customSelect('SELECT entity_id FROM sync_outbox').getSingle())
        .read<String>('entity_id'), 'server-job');

    await insertJob('historical', 'J-99', syncState: 'synced');
    expect((await jobs.listJobs('shop')).first['id'], 'server-job');
    expect(await jobs.remapProvisionalJob('shop', 'local-job-1', 'server-job',
        jobNumber: 'J-50'), 'J-50');
    expect((await jobs.listJobs('shop')).map((row) => row['job_number']),
        ['J-99', 'J-50']);
    expect(await jobs.jobCount('shop'), 2);
  });

  test('remap never replaces a real Job snapshot with a provisional copy', () async {
    await insertJob('local-job', 'TEMP-NEW');
    await insertJob('server', 'J-100', syncState: 'synced',
        status: 'completed', title: 'Authoritative title');
    expect(await jobs.remapProvisionalJob('shop', 'local-job', 'server',
        jobNumber: 'TEMP-STALE'), 'J-100');
    final rows = await jobs.listJobs('shop');
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Authoritative title');
    expect(rows.single['status'], 'completed');
  });

  test('Job remap preserves offline work and its stable queued operation', () async {
    await insertJob('local-job', 'TEMP-WORK');
    await db.customStatement(
      "INSERT INTO local_job_visits(id,business_id,job_id,visit_number,work_summary,sync_state) "
      "VALUES ('local-visit-work','shop','local-job',1,'Replaced filter','pending')",
    );
    await db.customStatement(
      "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json) "
      "VALUES ('shop','work_summary','local-job','upsert',?)",
      [jsonEncode({'job_id': 'local-job', 'operation_id': 'stable-work',
        'visit_id': 'local-visit-work', 'work_summary': 'Replaced filter'})],
    );
    await jobs.remapProvisionalJob('shop', 'local-job', 'server-job');
    final visit = await db.customSelect('SELECT * FROM local_job_visits').getSingle();
    expect(visit.read<String>('job_id'), 'server-job');
    expect(visit.read<String>('work_summary'), 'Replaced filter');
    expect(visit.read<String>('sync_state'), 'pending');
    final queued = await db.customSelect('SELECT * FROM sync_outbox').getSingle();
    final payload = jsonDecode(queued.read<String>('payload_json')) as Map;
    expect(queued.read<String>('entity_id'), 'server-job');
    expect(payload['job_id'], 'server-job');
    expect(payload['operation_id'], 'stable-work');
    expect(payload['visit_id'], 'local-visit-work');
  });

  test('invalid or missing server identity leaves the provisional Job intact', () async {
    await insertJob('local-job', 'TEMP-KEEP');
    await expectLater(jobs.remapProvisionalJob('shop', 'local-job', ''),
        throwsStateError);
    await expectLater(jobs.remapProvisionalJob('other', 'local-job', 'server'),
        throwsStateError);
    expect(await jobs.jobNumberForJob('shop', 'local-job'), 'TEMP-KEEP');
    expect(await jobs.jobCount('shop'), 1);
  });
}
