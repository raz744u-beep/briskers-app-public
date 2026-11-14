import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/job_display_description.dart';
import 'package:briskers_app/core/job_list_options.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_invoice_task_store.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/local_job_work_date.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_task_schedule.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late BriskersLocalDatabase db;
  void open() => db = BriskersLocalDatabase(
    NativeDatabase(File('${folder.path}/shop.sqlite')),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folder = await Directory.systemTemp.createTemp('job-date-title');
    open();
    await LocalPayrollRepository(db, business: 'shop', owner: true).prepare();
    await LocalDocumentDetailCache.initialize(db);
  });
  tearDown(() async {
    await db.close();
    await folder.delete(recursive: true);
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
  });
  Future<Map<String, dynamic>> invoice(String job, String id) async {
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number,document_date,status) VALUES(?,'shop',?,'invoice',?,'2026-11-13','issued')",
      [id, job, id],
    );
    final detail = <String, dynamic>{
      'id': id,
      'job_id': job,
      'kind': 'invoice',
      'status': 'issued',
      'payments': [
        {'id': 'original-payment', 'amount': 3000},
      ],
      'lines': [
        {
          'id': 'oil',
          'line_kind': 'labor',
          'description': 'Oil Change',
          'quantity': 1,
        },
      ],
    };
    await LocalDocumentDetailCache(database: db).save('shop', id, detail);
    return detail;
  }

  Future<String> financial() async => jsonEncode({
    for (final table in [
      'local_documents',
      'local_document_details',
      'regular_payroll_payments',
      'regular_payroll_owner_prior_paid_v1',
      'local_mechanic_work_credits_v1',
      'regular_payroll_portions',
    ])
      table: (await db.customSelect('SELECT * FROM $table').get())
          .map((r) => r.data)
          .toList(),
  });

  test(
    'Job Date uses Chicago calendar date across midnight and daylight saving',
    () {
      expect(
        LocalJobWorkDate.today(now: DateTime.utc(2026, 11, 13, 4)),
        DateTime(2026, 11, 12),
      );
      expect(
        LocalJobWorkDate.today(now: DateTime.utc(2026, 11, 13, 6)),
        DateTime(2026, 11, 13),
      );
      expect(
        LocalJobWorkDate.today(now: DateTime.utc(2026, 7, 13, 4)),
        DateTime(2026, 7, 12),
      );
      expect(
        LocalJobWorkDate.today(now: DateTime.utc(2026, 7, 13, 5)),
        DateTime(2026, 7, 13),
      );
    },
  );

  test(
    'new tasks inherit saved last-week Job Date; date edits preserve existing tasks, finances, creation order and restart',
    () async {
      final admin = OfflineJobAdminService(database: db);
      final job = await admin.queueJobCreate(
        'shop',
        customerId: 'customer',
        customerName: 'Nathan Hogue',
        title: 'Invoice',
        jobDate: DateTime(2026, 11, 5),
      );
      final detail = await invoice(job, '6373');
      final task =
          (await db.customSelect('SELECT * FROM regular_payroll_tasks').get())
                  .single
                  .data['id']
              as String;
      var date =
          (await db
                  .customSelect('SELECT * FROM regular_task_schedule_v1')
                  .get())
              .single;
      expect(date.data['start_date'], '2026-11-05');
      expect(date.data['end_date'], '2026-11-05');
      final created =
          (await db.customSelect('SELECT created_at FROM local_jobs').get())
              .single
              .data['created_at'];
      final finances = await financial();
      await LocalTaskSchedule(
        db,
      ).save('shop', task, '2026-11-02', '2026-11-03', 'High');
      await admin.queueCore(
        'shop',
        job,
        jobDate: DateTime(2026, 11, 6),
        title: 'Scheduled service',
      );
      await LocalInvoiceTaskStore(db).save('shop', '6373', detail);
      expect(await financial(), finances);
      expect(
        (await db.customSelect('SELECT created_at FROM local_jobs').get())
            .single
            .data['created_at'],
        created,
      );
      await db.close();
      open();
      expect(
        await LocalJobWorkDate(db).read('shop', job),
        DateTime(2026, 11, 6),
      );
      date =
          (await db
                  .customSelect('SELECT * FROM regular_task_schedule_v1')
                  .get())
              .single;
      expect(date.data['start_date'], '2026-11-02');
      expect(date.data['end_date'], '2026-11-03');
      expect(date.data['priority'], 'High');
      final expanded = {
        ...detail,
        'lines': [
          ...detail['lines'] as List,
          {
            'id': 'brake',
            'line_kind': 'labor',
            'description': 'Brake Flush',
            'quantity': 1,
          },
        ],
      };
      await LocalInvoiceTaskStore(db).save('shop', '6373', expanded);
      await LocalInvoiceTaskStore(db).save('shop', '6373', expanded);
      final dates = await db
          .customSelect(
            'SELECT * FROM regular_task_schedule_v1 ORDER BY task_id',
          )
          .get();
      expect(dates, hasLength(2));
      expect(dates.map((r) => r.data['start_date']).toSet(), {
        '2026-11-02',
        '2026-11-06',
      });
      expect(await financial(), finances);
    },
  );

  test(
    'J-54 title save/reopen displays title; Invoice and blank retain repair fallback and search',
    () async {
      final admin = OfflineJobAdminService(database: db);
      final job = await admin.queueJobCreate(
        'shop',
        customerId: 'customer',
        customerName: 'Nathan Hogue',
        title: 'Invoice',
      );
      await db.customStatement(
        "UPDATE local_jobs SET job_number='J-54' WHERE id=?",
        [job],
      );
      await invoice(job, '6373');
      final before = await financial();
      await admin.queueCore('shop', job, title: 'Nathan scheduled maintenance');
      await db.close();
      open();
      var repository = LocalJobRepository(database: db);
      var rows = await repository.listJobs(
        'shop',
        search: 'scheduled maintenance',
        sort: JobListSort.creation,
      );
      expect(rows, hasLength(1));
      expect(
        jobDisplayDescription(rows.single),
        'Nathan scheduled maintenance',
      );
      for (final title in [' Invoice ', '']) {
        await OfflineJobAdminService(
          database: db,
        ).queueCore('shop', job, title: title);
        rows = await repository.listJobs('shop', search: 'oil change');
        expect(rows, hasLength(1));
        expect(jobDisplayDescription(rows.single), 'Oil Change');
        expect(await repository.jobCount('shop', search: 'oil change'), 1);
      }
      expect(await financial(), before);
      expect(
        jobDisplayDescription({
          'title': 'Job diagnosis',
          'work_summary': 'Oil Change',
        }),
        'Job diagnosis',
      );
      expect(
        jobDisplayDescription({
          'title': 'Invoice',
          'requested_work': 'Invoice',
          'work_summary': 'Brake Flush',
        }),
        'Brake Flush',
      );
      final blank = await OfflineJobAdminService(database: db).queueJobCreate(
        'shop',
        customerId: 'customer',
        customerName: 'Test',
        title: '',
        requestedWork: 'Cooling repair',
      );
      expect(
        await LocalJobWorkDate(db).read('shop', blank),
        LocalJobWorkDate.today(),
      );
      expect(
        jobDisplayDescription(
          (await repository.listJobs('shop', search: 'cooling')).single,
        ),
        'Cooling repair',
      );
    },
  );
}
