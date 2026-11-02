import 'dart:io';

import 'package:briskers_app/core/job_list_options.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_access_history.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BriskersLocalDatabase db;
  late LocalJobRepository repository;
  late LocalJobAccessHistory history;
  final today = DateTime.utc(2026, 10, 14, 5);
  final todaySeconds = today.millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    repository = LocalJobRepository(database: db);
    history = LocalJobAccessHistory(database: db);
  });
  tearDown(() => db.close());

  Future<void> addJob(
    String id, {
    String? number,
    String status = 'open',
    int created = 100,
    int? updated,
    int? completed,
    String? payment,
    String business = 'shop',
    String title = 'Repair',
    String syncState = 'synced',
  }) => db.customStatement(
    '''
    INSERT INTO local_jobs (id, business_id, access_scope, job_number,
      title, customer_name, vehicle_label, status, status_name, created_at,
      server_updated_at, completed_at, payment_state, sync_state)
    VALUES (?, ?, 'all', ?, ?, 'Synthetic Jobs Customer', 'Ford Ranger', ?, ?, ?, ?, ?, ?, ?)
  ''',
    [
      id,
      business,
      number ?? id,
      title,
      status,
      status,
      created,
      updated,
      completed,
      payment,
      syncState,
    ],
  );

  List<String> ids(List<Map<String, dynamic>> rows) =>
      rows.map((row) => row['id'] as String).toList();

  test('direct Job local core first frame is readable before secondary graph',
      () async {
    await addJob('fast-local-job', number: 'J-123',
        title: 'Local brake service', status: 'in_progress',
        payment: 'partial');
    final core = await repository.jobDetail(
        'shop', 'fast-local-job', coreOnly: true);
    expect(core, isNotNull);
    expect(core!.job['job_number'], 'J-123');
    expect(core.job['customer_name'], 'Synthetic Jobs Customer');
    expect(core.job['vehicle'], 'Ford Ranger');
    expect(core.job['title'], 'Local brake service');
    expect(core.job['payment_state'], 'partial');
    expect(core.job['_first_frame_only'], isTrue,
        reason: 'Preview cannot authorize edits before full local detail');
    expect(core.preInspection, isNull);
    expect(core.findings, isEmpty);
    expect(core.statuses, isEmpty);

    final full = await repository.jobDetail('shop', 'fast-local-job');
    expect(full, isNotNull);
    expect(full!.job['_first_frame_only'], isNot(true));
    expect(full.job['title'], core.job['title']);
    expect((await repository.jobDetail('other-shop',
        'fast-local-job', coreOnly: true)), isNull,
        reason: 'Never borrow another shop\'s saved Job');
  });

  test(
    'synthetic J-6 completed today stays in first All page and Completed',
    () async {
      for (var i = 0; i < 65; i++) {
        await addJob(
          'older-$i',
          number: 'J-${100 + i}',
          created: 1000 + i,
          updated: todaySeconds - 86400,
        );
      }
      for (var i = 0; i < 40; i++) {
        await addJob(
          'import-$i',
          number: 'MB-${9000 + i}',
          status: 'completed',
          created: todaySeconds + 100,
          updated: todaySeconds + 100,
          completed: todaySeconds - 7 * 86400 - i,
        );
      }
      await addJob(
        'j6',
        number: 'J-6',
        status: 'completed',
        completed: todaySeconds,
        updated: todaySeconds,
        payment: 'paid',
      );
      final recent = await repository.listJobs(
        'shop',
        userId: 'owner',
        limit: 30,
      );
      expect(recent, hasLength(30));
      expect(recent.first['id'], 'j6');
      expect(
        (await repository.listJobs('shop', status: 'completed')).first['id'],
        'j6',
      );
      expect(
        ids(
          await repository.listJobs(
            'shop',
            view: JobListView.active,
            limit: 100,
          ),
        ),
        isNot(contains('j6')),
      );
      expect(await repository.jobCount('shop', view: JobListView.active), 65);
      expect(
        ids(
          await repository.listJobs('shop', view: JobListView.all, search: '6'),
        ),
        ['j6'],
      );
      expect(await repository.jobCount('shop', search: '6'), 1);
    },
  );

  test(
    'real offline status queue keeps completed J-6 above the 30-row cut',
    () async {
      for (var i = 0; i < 40; i++) {
        await addJob('other-$i', number: 'J-${50 + i}', created: 300 + i);
      }
      await addJob('j6', number: 'J-6', status: 'in_progress');
      await history.recordAccess('shop', 'j6', userId: 'owner', at: today);
      await OfflineJobAdminService(
        database: db,
      ).queueStatus('shop', 'j6', code: 'completed', name: 'Completed');
      final recent = await repository.listJobs(
        'shop',
        userId: 'owner',
        limit: 30,
      );
      expect(recent.first['id'], 'j6');
      expect(recent.first['status'], 'completed');
      expect(
        (await repository.listJobs(
          'shop',
          sort: JobListSort.lastModified,
        )).first['id'],
        'j6',
      );
      expect(
        await repository.listJobs(
          'shop',
          search: '6',
          view: JobListView.active,
        ),
        isEmpty,
      );
    },
  );

  test('opens and modification sort remain independent and per-user', () async {
    await addJob('a', created: 100, updated: 200);
    await addJob('b', created: 200, updated: 300);
    await history.recordAccess('shop', 'a', userId: 'alice', at: today);
    await history.recordAccess('shop', 'b', userId: 'bob', at: today);
    expect(
      ids(
        await repository.listJobs(
          'shop',
          view: JobListView.recent,
          sort: JobListSort.lastAccessed,
          userId: 'alice',
        ),
      ),
      ['a', 'b'],
    );
    expect(
      ids(
        await repository.listJobs(
          'shop',
          view: JobListView.recent,
          sort: JobListSort.lastAccessed,
          userId: 'bob',
        ),
      ),
      ['b', 'a'],
    );
    expect(ids(await repository.listJobs('shop')), ['b', 'a']);
    expect(
      ids(
        await repository.listJobs(
          'shop',
          userId: 'alice',
          sort: JobListSort.lastModified,
        ),
      ),
      ['b', 'a'],
    );
    expect(
      ids(
        await repository.listJobs(
          'shop',
          userId: 'alice',
          view: JobListView.all,
        ),
      ),
      ['b', 'a'],
    );
    final row = await db
        .customSelect("SELECT * FROM local_jobs WHERE id='a'")
        .getSingle();
    expect(row.read<int>('server_updated_at'), 200);
    expect(row.read<String>('sync_state'), 'synced');
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
  });

  test(
    'All uses newest meaningful activity and Completed preserves real completion',
    () async {
      final imported = todaySeconds - 6 * 86400;
      final lastYear = DateTime.utc(2025).millisecondsSinceEpoch ~/ 1000;
      await addJob('current', number: 'J-6', created: todaySeconds - 2 * 86400);
      await addJob(
        'known-old',
        number: 'MB-9999',
        status: 'completed',
        created: imported,
        updated: todaySeconds + 10,
        completed: lastYear,
      );
      await addJob(
        'known-new',
        number: 'MB-1',
        status: 'completed',
        created: imported,
        updated: imported,
        completed: todaySeconds - 86400,
      );
      await addJob(
        'missing-completion',
        number: 'J-2',
        status: 'completed',
        created: 100,
        updated: todaySeconds - 43200,
      );
      await addJob(
        'undated-import',
        number: 'MB-99999',
        status: 'completed',
        created: imported,
        updated: imported,
      );
      final before = await db
          .customSelect('SELECT * FROM local_jobs ORDER BY id')
          .get();
      final all = ids(await repository.listJobs('shop'));
      expect(all, [
        'known-old',
        'missing-completion',
        'known-new',
        'current',
        'undated-import',
      ]);
      expect(
        ids(await repository.listJobs('shop', view: JobListView.all)),
        all,
      );
      for (final legacySort in JobListSort.values) {
        expect(
          ids(
            await repository.listJobs(
              'shop',
              view: JobListView.all,
              sort: legacySort,
            ),
          ),
          all,
        );
      }
      // Merely opening an old Job must not bump it in the simplified Jobs list.
      await history.recordAccess(
        'shop',
        'undated-import',
        userId: 'alice',
        at: today,
      );
      expect(ids(await repository.listJobs('shop', userId: 'alice')), all);
      expect(ids(await repository.listJobs('shop', status: 'completed')), [
        'missing-completion',
        'known-new',
        'known-old',
        'undated-import',
      ]);
      final after = await db
          .customSelect('SELECT * FROM local_jobs ORDER BY id')
          .get();
      expect(
        after.map((row) => row.data).toList(),
        before.map((row) => row.data).toList(),
      );
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
    },
  );

  test(
    'offline completion timestamps survive repeated updates and clear on reopen',
    () async {
      await addJob('j6', number: 'J-6', status: 'in_progress');
      final admin = OfflineJobAdminService(database: db);
      final before = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      await admin.queueStatus(
        'shop',
        'j6',
        code: 'completed',
        name: 'Completed',
      );
      var row = await db
          .customSelect("SELECT * FROM local_jobs WHERE id='j6'")
          .getSingle();
      final completed = row.read<int>('completed_at');
      expect(completed, greaterThanOrEqualTo(before));
      // A repeated update preserves actual completion rather than editing it.
      await db.customStatement(
        "UPDATE local_jobs SET completed_at=123 WHERE id='j6'",
      );
      await admin.queueStatus(
        'shop',
        'j6',
        code: 'completed',
        name: 'Completed',
      );
      row = await db
          .customSelect("SELECT * FROM local_jobs WHERE id='j6'")
          .getSingle();
      expect(row.read<int>('completed_at'), 123);
      await admin.queueStatus('shop', 'j6', code: 'open', name: 'Open');
      row = await db
          .customSelect("SELECT * FROM local_jobs WHERE id='j6'")
          .getSingle();
      expect(row.readNullable<int>('completed_at'), isNull);
      await admin.queueStatus(
        'shop',
        'j6',
        code: 'completed',
        name: 'Completed',
      );
      row = await db
          .customSelect("SELECT * FROM local_jobs WHERE id='j6'")
          .getSingle();
      expect(row.read<int>('completed_at'), greaterThanOrEqualTo(completed));
      expect(row.readNullable<int>('server_updated_at'), isNull);
      expect(
        await db.customSelect('SELECT * FROM sync_outbox').get(),
        hasLength(1),
      );
    },
  );

  test(
    'inspection and linked finding activity reorder All without cache timestamps',
    () async {
      await addJob('base', created: 1000);
      await addJob('inspected', created: 100);
      await addJob('finding-job', created: 100);
      await addJob('unrelated', created: 100);
      await addJob('imported', number: 'MB-9000', created: 5000, updated: 5000);
      await db.customStatement(
        "INSERT INTO local_pre_inspections (id,business_id,job_id,inspected_at,server_updated_at) "
        "VALUES ('inspection','shop','inspected',2000,2000),"
        "('old-inspection','shop','imported',200,5000)",
      );
      await db.customStatement(
        "INSERT INTO local_findings "
        "(id,business_id,found_job_id,body,status,created_at,server_updated_at) "
        "VALUES ('finding','shop','finding-job','Synthetic finding','open',3000,3000),"
        "('other-business','other','unrelated','Other business','open',9000,9000),"
        "('import-finding','shop','imported','Imported finding','open',5000,5000)",
      );
      expect(ids(await repository.listJobs('shop')), [
        'finding-job',
        'inspected',
        'base',
        'imported',
        'unrelated',
      ]);
      await db.customStatement(
        "INSERT INTO sync_outbox "
        "(business_id,entity_type,entity_id,operation,payload_json,created_at) "
        "VALUES ('shop','finding_action','finding','update','{\"_activity_at\":7000}',500),"
        "('shop','job_admin','inspected','update','{\"_activity_at\":8000}',500)",
      );
      expect(ids(await repository.listJobs('shop')).take(2), [
        'inspected',
        'finding-job',
      ]);
      final rows = await db
          .customSelect(
            "SELECT server_updated_at FROM local_jobs WHERE id='imported'",
          )
          .getSingle();
      expect(rows.read<int>('server_updated_at'), 5000);
      await db.customStatement(
        "INSERT INTO local_pre_inspection_photos (id,business_id,inspection_id,attachment_id,captured_at) "
        "VALUES ('photo','shop','inspection','attachment-i',9000)",
      );
      await db.customStatement(
        "INSERT INTO local_finding_photos (id,business_id,finding_id,attachment_id,captured_at) "
        "VALUES ('finding-photo','shop','finding','attachment-f',10000)",
      );
      expect(ids(await repository.listJobs('shop')).take(2), [
        'finding-job',
        'inspected',
      ]);
    },
  );

  test(
    'Job date has explicit evidence precedence and safe missing-date fallback',
    () async {
      int epoch(int year) => DateTime.utc(year).millisecondsSinceEpoch ~/ 1000;
      await addJob(
        'completion',
        number: 'MB-10',
        created: todaySeconds,
        updated: todaySeconds + 10,
        completed: epoch(2020),
      );
      await addJob(
        'document',
        number: 'MB-20',
        created: todaySeconds,
        updated: todaySeconds + 20,
      );
      await addJob(
        'visit',
        number: 'MB-30',
        created: todaySeconds,
        updated: todaySeconds + 30,
      );
      await addJob(
        'unknown',
        number: 'MB-999',
        created: todaySeconds,
        updated: todaySeconds + 40,
      );
      await addJob('native', number: 'J-1', created: epoch(2025));
      await db.customStatement(
        "INSERT INTO local_documents (id,business_id,job_id,kind,document_date) VALUES "
        "('completion-doc','shop','completion','invoice','2024-01-01'),"
        "('document-doc','shop','document','invoice','2022-01-01'),"
        "('invalid-doc','shop','visit','invoice','not-a-date'),"
        "('other-shop-doc','other-shop','unknown','invoice','2025-01-01')",
      );
      await db.customStatement(
        "INSERT INTO local_job_visits (id,business_id,job_id,visit_number,closed_at) "
        "VALUES ('document-visit','shop','document',1,?),"
        "('visit-visit','shop','visit',1,?)",
        [epoch(2023), epoch(2021)],
      );
      final rows = await repository.listJobs(
        'shop',
        view: JobListView.recent,
        sort: JobListSort.jobDate,
      );
      expect(ids(rows), [
        'native',
        'document',
        'visit',
        'completion',
        'unknown',
      ]);
      expect(rows.last['job_date'], isNull);
      expect(rows[2]['job_date'], DateTime.utc(2021).toIso8601String());
      expect(rows[3]['job_date'], DateTime.utc(2020).toIso8601String());
    },
  );

  test(
    'opened-first ordering is global before paging, not just a visible-page sort',
    () async {
      for (var i = 0; i < 65; i++) {
        await addJob(
          'unopened-$i',
          number: 'J-${100 + i}',
          created: todaySeconds + i,
          updated: todaySeconds + i,
        );
      }
      await addJob('opened', number: 'J-1', created: 100);
      await history.recordAccess(
        'shop',
        'opened',
        userId: 'owner',
        at: today.subtract(const Duration(days: 3)),
      );
      expect(
        (await repository.listJobs(
          'shop',
          view: JobListView.recent,
          sort: JobListSort.lastAccessed,
          userId: 'owner',
          limit: 30,
        )).first['id'],
        'opened',
      );
      final pages = <String>[];
      for (var offset = 0; offset < 66; offset += 30) {
        pages.addAll(
          ids(
            await repository.listJobs(
              'shop',
              view: JobListView.recent,
              sort: JobListSort.lastAccessed,
              userId: 'owner',
              limit: 30,
              offset: offset,
            ),
          ),
        );
      }
      expect(pages.toSet(), hasLength(66));
      expect(
        pages,
        ids(
          await repository.listJobs(
            'shop',
            view: JobListView.recent,
            sort: JobListSort.lastAccessed,
            userId: 'owner',
            limit: 100,
          ),
        ),
      );
    },
  );

  test(
    'historical linked customer name finds stale Job snapshots in all offline views',
    () async {
      await db.customStatement(
        "INSERT INTO local_customers (id,business_id,display_name) VALUES "
        "('linked','shop','Synthetic Cedar Workshop'),"
        "('wrong-shop','other-shop','Synthetic Cedar Workshop')",
      );
      await addJob('historical', number: 'MB-5180', status: 'completed');
      await addJob('active', number: 'J-7', status: 'open');
      await addJob('isolated', number: 'MB-8', status: 'open');
      await db.customStatement(
        "UPDATE local_jobs SET customer_id = 'linked', customer_name = 'Old snapshot' "
        "WHERE id IN ('historical','active')",
      );
      await db.customStatement(
        "UPDATE local_jobs SET customer_id = 'wrong-shop', "
        "customer_name = 'Old snapshot' WHERE id = 'isolated'",
      );
      for (final view in JobListView.values) {
        final matches = ids(
          await repository.listJobs('shop', view: view, search: 'cEdAr'),
        );
        expect(
          matches.toSet(),
          view == JobListView.active ? {'active'} : {'historical', 'active'},
        );
        expect(
          await repository.jobCount('shop', view: view, search: 'cedar'),
          matches.length,
        );
        expect(
          ids(
            await repository.listJobs(
              'shop',
              view: view,
              search: 'cedar',
              status: 'open',
            ),
          ),
          ['active'],
        );
      }
      expect(
        ids(
          await repository.listJobs(
            'shop',
            view: JobListView.all,
            search: '5180',
          ),
        ),
        ['historical'],
      );
      expect(await repository.listJobs('shop', search: '518'), isEmpty);
      expect(
        await repository.listJobs('shop', search: 'cedar', status: 'cancelled'),
        isEmpty,
      );
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
    },
  );

  test('background detail reads never create an access', () async {
    await addJob('a', created: 100, updated: 100);
    await addJob('b', created: 200, updated: 200);
    await repository.jobDetail('shop', 'a');
    final rows = await repository.listJobs('shop', userId: 'owner');
    expect(ids(rows), ['b', 'a']);
    expect(rows.every((row) => row['last_accessed_at'] == null), isTrue);
  });

  test('repeated opens use newest millisecond and cannot regress', () async {
    await addJob('a');
    await addJob('b');
    await history.recordAccess('shop', 'a', userId: 'owner', at: today);
    await history.recordAccess(
      'shop',
      'b',
      userId: 'owner',
      at: today.add(const Duration(milliseconds: 1)),
    );
    await history.recordAccess(
      'shop',
      'b',
      userId: 'owner',
      at: today.subtract(const Duration(days: 1)),
    );
    expect(
      ids(
        await repository.listJobs(
          'shop',
          view: JobListView.recent,
          sort: JobListSort.lastAccessed,
          userId: 'owner',
        ),
      ),
      ['b', 'a'],
    );
    final accesses = await db
        .customSelect('SELECT * FROM local_job_accesses')
        .get();
    expect(accesses, hasLength(2));
  });

  test(
    'accesses do not cross businesses, even with identical incoming ID',
    () async {
      await addJob('a', created: 100, updated: 100);
      await addJob('b', created: 200, updated: 200);
      await history.recordAccess('other-shop', 'a', userId: 'owner', at: today);
      expect(ids(await repository.listJobs('shop', userId: 'owner')), [
        'b',
        'a',
      ]);
    },
  );

  test(
    'Active groups by status then creation, independent of updates or number',
    () async {
      await db.customStatement(
        "INSERT INTO local_job_statuses "
        "(business_id,code,name,sort_order) VALUES "
        "('shop','waiting_parts','Waiting Parts',2),('shop','open','Open',1)",
      );
      await addJob(
        'open-old',
        number: 'J-900',
        created: 100,
        updated: todaySeconds,
      );
      await addJob('open-new', number: 'J-1', created: 200, updated: 200);
      await addJob('waiting', status: 'waiting_parts', created: 300);
      await addJob('done', status: 'completed', created: 400);
      await addJob('cancel', status: 'cancelled', created: 500);
      await addJob('closed', status: 'closed', created: 600);
      await history.recordAccess(
        'shop',
        'open-old',
        userId: 'owner',
        at: today,
      );
      expect(
        ids(
          await repository.listJobs(
            'shop',
            userId: 'owner',
            view: JobListView.active,
          ),
        ),
        ['open-new', 'open-old', 'waiting'],
      );
      expect(await repository.jobCount('shop', view: JobListView.active), 3);
      expect(await repository.activeJobCount('shop'), 3);
      expect(
        await repository.jobStatusCounts('shop', view: JobListView.active),
        {'open': 2, 'waiting_parts': 1},
      );
    },
  );

  test(
    'All includes temporary Jobs in activity order while legacy modes remain supported',
    () async {
      await addJob('newer', created: todaySeconds);
      await addJob('temp', number: 'TEMP-42', created: 200);
      await addJob(
        'pending',
        number: 'Pending sync',
        created: 300,
        syncState: 'pending',
      );
      for (final view in JobListView.values) {
        for (final sort in JobListSort.values) {
          expect(
            ids(await repository.listJobs('shop', view: view, sort: sort)),
            view == JobListView.all
                ? ['newer', 'pending', 'temp']
                : ['pending', 'temp', 'newer'],
          );
        }
      }
    },
  );

  test(
    'import timestamps never outrank real activity, number fallback is stable',
    () async {
      await addJob('j6', number: 'J-6', updated: todaySeconds);
      await addJob(
        'mb9',
        number: 'MB-9',
        created: todaySeconds + 100,
        updated: todaySeconds + 100,
        status: 'completed',
      );
      await addJob(
        'mb8',
        number: 'MB-8',
        created: todaySeconds + 200,
        updated: todaySeconds + 200,
        status: 'completed',
      );
      expect(
        ids(await repository.listJobs('shop', sort: JobListSort.lastModified)),
        ['j6', 'mb9', 'mb8'],
      );
      await db.customStatement(
        "UPDATE local_jobs SET server_updated_at=? WHERE id='mb8'",
        [todaySeconds + 300],
      );
      expect(
        (await repository.listJobs(
          'shop',
          sort: JobListSort.lastModified,
        )).first['id'],
        'mb8',
      );
    },
  );

  test(
    'imported historical document date wins over import time and numbering',
    () async {
      await addJob(
        'mb9',
        number: 'MB-9',
        created: todaySeconds,
        updated: todaySeconds,
      );
      await addJob(
        'mb8',
        number: 'MB-8',
        created: todaySeconds,
        updated: todaySeconds,
      );
      await db.customStatement(
        "INSERT INTO local_documents "
        "(id,business_id,job_id,kind,document_date,created_at,server_updated_at) "
        "VALUES ('invoice8','shop','mb8','invoice','2020-05-02',?,?),"
        "('invoice9','shop','mb9','invoice','2019-05-02',?,?)",
        [todaySeconds, todaySeconds, todaySeconds, todaySeconds],
      );
      expect(ids(await repository.listJobs('shop', view: JobListView.all)), [
        'mb8',
        'mb9',
      ]);
    },
  );

  test(
    'received payment is activity but never silently completes an open job',
    () async {
      await addJob('unpaid', created: 1000);
      await addJob('paid-job', number: 'J-6', status: 'in_progress');
      await db.customStatement(
        "INSERT INTO local_documents "
        "(id,business_id,job_id,kind,total) VALUES ('invoice','shop','paid-job','invoice',100)",
      );
      await OfflineInvoicePaymentLedger(database: db).recordReceivedPayment(
        'shop',
        'invoice',
        amount: 100,
        remainingBeforePaymentCents: 10000,
        methodId: 'cash',
        methodName: 'Cash',
      );
      final modified = await repository.listJobs(
        'shop',
        sort: JobListSort.lastModified,
      );
      expect(modified.first['id'], 'paid-job');
      expect(modified.first['status'], 'in_progress');
      expect(modified.first['completed_at'], isNull);
      expect(
        ids(await repository.listJobs('shop', view: JobListView.active)),
        contains('paid-job'),
      );
      expect(
        await repository.listJobs('shop', status: 'paid_still_open'),
        isEmpty,
        reason: 'A pending payment must not be advertised as finalized paid.',
      );
    },
  );

  test(
    'Paid Still Open filter and count agree, completed paid is excluded',
    () async {
      await addJob('paid-open', payment: 'paid');
      await addJob('partial-open', payment: 'partial');
      await addJob('paid-done', payment: 'paid', status: 'completed');
      for (final view in JobListView.values) {
        expect(
          ids(
            await repository.listJobs(
              'shop',
              view: view,
              status: 'paid_still_open',
            ),
          ),
          ['paid-open'],
        );
        expect(
          await repository.jobCount(
            'shop',
            view: view,
            status: 'paid_still_open',
          ),
          1,
        );
      }
    },
  );

  test(
    'All pagination covers every job with deterministic ties and filters',
    () async {
      for (var i = 0; i < 75; i++) {
        await addJob(
          'job-$i',
          number: 'J-$i',
          status: i.isEven ? 'completed' : 'open',
          created: 100,
          title: i < 60 ? 'Brake repair' : 'Engine repair',
        );
      }
      final pages = <String>[];
      for (var offset = 0; offset < 75; offset += 30) {
        pages.addAll(
          ids(
            await repository.listJobs(
              'shop',
              view: JobListView.all,
              limit: 30,
              offset: offset,
            ),
          ),
        );
      }
      expect(pages, hasLength(75));
      expect(pages.toSet(), hasLength(75));
      expect(
        pages,
        ids(
          await repository.listJobs('shop', view: JobListView.all, limit: 100),
        ),
      );
      final filtered = await repository.listJobs(
        'shop',
        view: JobListView.all,
        status: 'completed',
        search: 'brake',
        limit: 100,
      );
      expect(filtered, hasLength(30));
      expect(
        await repository.jobCount(
          'shop',
          view: JobListView.all,
          status: 'completed',
          search: 'brake',
        ),
        30,
      );
      expect(ids(await repository.listJobs('shop', search: '6')), ['job-6']);
    },
  );

  test(
    'access remap preserves every user, newest value and business boundary',
    () async {
      await addJob('local-job', number: 'TEMP-42', syncState: 'pending');
      await addJob('real-job', number: 'J-42', title: 'Authoritative');
      await history.recordAccess(
        'shop',
        'local-job',
        userId: 'alice',
        at: today,
      );
      await history.recordAccess(
        'shop',
        'real-job',
        userId: 'alice',
        at: today.add(const Duration(seconds: 1)),
      );
      await history.recordAccess('shop', 'local-job', userId: 'bob', at: today);
      await history.recordAccess(
        'other-shop',
        'local-job',
        userId: 'alice',
        at: today,
      );
      expect(
        await repository.remapProvisionalJob(
          'shop',
          'local-job',
          'real-job',
          jobNumber: 'J-42',
        ),
        'J-42',
      );
      final rows = await repository.listJobs('shop', userId: 'alice');
      expect(rows.single['id'], 'real-job');
      expect(rows.single['title'], 'Authoritative');
      expect(
        rows.single['last_accessed_at'],
        today.add(const Duration(seconds: 1)).toIso8601String(),
      );
      final accesses = await db
          .customSelect('SELECT * FROM local_job_accesses')
          .get();
      expect(accesses, hasLength(3));
      expect(
        accesses
            .where((r) => r.read<String>('business_id') == 'shop')
            .every((r) => r.read<String>('job_id') == 'real-job'),
        isTrue,
      );
    },
  );

  test(
    'access history persists across SQLite restart without a migration',
    () async {
      final folder = Directory.systemTemp.createTempSync(
        'briskers-access-test-',
      );
      final file = File('${folder.path}/jobs.sqlite');
      try {
        final first = BriskersLocalDatabase(NativeDatabase(file));
        await LocalJobAccessHistory(
          database: first,
        ).recordAccess('shop', 'j6', userId: 'owner', at: today);
        await first.close();
        final second = BriskersLocalDatabase(NativeDatabase(file));
        try {
          await LocalJobAccessHistory(database: second).ensureTable();
          final rows = await second
              .customSelect('SELECT * FROM local_job_accesses')
              .get();
          expect(
            rows.single.read<int>('last_accessed_at'),
            today.millisecondsSinceEpoch,
          );
          expect(rows.single.read<String>('user_id'), 'owner');
        } finally {
          await second.close();
        }
      } finally {
        folder.deleteSync(recursive: true);
      }
    },
  );
}
