import 'dart:io';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final date in ['2026-11-06', '2026-11-11', null]) {
    test(
      'saved 3.6-hour labor and explicit splits survive reopen ($date)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final dir = await Directory.systemTemp.createTemp('bugs35-');
        final file = File('${dir.path}/shop.sqlite');
        var db = BriskersLocalDatabase(NativeDatabase(file));
        addTearDown(() async {
          await db.close();
          await dir.delete(recursive: true);
          LocalDocumentDetailCache.sqliteWritesEnabled = false;
        });
        var repo = LocalPayrollRepository(db, business: 'shop', owner: true);
        await repo.prepare();
        await LocalDocumentDetailCache.initialize(db);
        await db.customStatement(
          "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,assigned_employee_id,assigned_employee_name) VALUES('job','shop','owner','Gloria fixture','completed','J-40','chris','Chris')",
        );
        await db.customStatement(
          "INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number,status) VALUES(?,'invoice','shop','job','invoice','6359','paid')",
          [date],
        );
        final detail = <String, dynamic>{
          'id': 'invoice',
          'kind': 'invoice',
          'job_id': 'job',
          'total': 540.0,
          'paid_amount': 540.0,
          'payments': [
            {'id': 'payment-6359', 'amount': 540.0},
          ],
          'lines': [
            {
              'id': 'labor',
              'name': 'Labor',
              'line_kind': 'item',
              'description': 'Replace front air struts',
              'quantity': 3.6,
              'unit_price': 150,
            },
          ],
        };
        await LocalDocumentDetailCache(database: db)
            .save('shop', 'invoice', detail);
        var work = await repo.work();
        expect(work, hasLength(1));
        expect(work.single['employee_id'], 'chris');
        expect(work.single['estimated_minutes'], 216);
        expect(work.single['actual_minutes'], 0);
        if (date != '2026-11-11') {
          expect(work.single['archived_labor'], 1);
          await expectLater(
            repo.recordAllocatedTime(
              work.single['id'] as String,
              'Done',
              216,
              216,
              '2026-11-11',
            ),
            throwsStateError,
          );
        }
        await repo.assignExistingService(
          job: 'job',
          invoice: 'invoice',
          line: 'labor',
          employee: 'kam',
          name: 'Kam',
          rate: 0,
          minutes: 60,
        );
        expect(
          (await repo.work(employee: 'chris')).single['estimated_minutes'],
          216,
        );
        await repo.setEstimatedMinutes(
          work.single['task_id'] as String,
          'chris',
          156,
        );
        // A main-mechanic refresh must preserve explicit splits.
        await repo.setMainMechanic('job', 'chris', 'Chris');
        await db.close();
        db = BriskersLocalDatabase(NativeDatabase(file));
        repo = LocalPayrollRepository(db, business: 'shop', owner: true);
        await LocalDocumentDetailCache.initialize(db);
        await repo.recoverJobAssignments('job');
        work = await repo.work();
        expect(work, hasLength(2));
        expect(
          {for (final r in work) r['employee_id']: r['estimated_minutes']},
          {'chris': 156, 'kam': 60},
        );
        expect(
          work.fold<int>(0, (n, r) => n + (r['estimated_minutes'] as int)),
          216,
        );
        expect(await repo.tasks(), hasLength(1));
        expect(
          jsonEncode(
            await LocalDocumentDetailCache(database: db)
                .load('shop', 'invoice'),
          ),
          jsonEncode(detail),
        );
        expect(
          await db.customSelect('SELECT * FROM regular_payroll_payments').get(),
          isEmpty,
        );
        expect(work.every((r) => r['actual_minutes'] == 0), isTrue);
      },
    );
  }
  test(
    '6370 existing generic Oil Change gets Kam 1 hour without another charge',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        LocalDocumentDetailCache.sqliteWritesEnabled = false;
      });
      final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      await repo.prepare();
      await LocalDocumentDetailCache.initialize(db);
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,assigned_employee_id,assigned_employee_name) VALUES('job','shop','owner','Ireona fixture','open','J-51','kam','Kam')",
      );
      await db.customStatement(
        "INSERT INTO local_documents(document_date,id,business_id,job_id,kind,document_number) VALUES('2026-11-11','invoice','shop','job','invoice','6370')",
      );
      final detail = <String, dynamic>{
        'id': 'invoice',
        'kind': 'invoice',
        'job_id': 'job',
        'total': 192.06,
        'paid_amount': 192.06,
        'payments': [
          {'id': 'payment-6370', 'amount': 192.06},
        ],
        'lines': [
          {
            'id': 'oil',
            'name': 'Oil Change',
            'line_kind': 'item',
            'quantity': 1,
            'unit_price': 175,
          },
        ],
      };
      await LocalDocumentDetailCache(database: db)
          .save('shop', 'invoice', detail);
      expect(await repo.tasks(), isEmpty);
      for (var i = 0; i < 2; i++) {
        await repo.assignExistingService(
          job: 'job',
          invoice: 'invoice',
          line: 'oil',
          employee: 'kam',
          name: 'Kam',
          rate: 0,
          minutes: 60,
        );
        await LocalDocumentDetailCache(database: db)
            .save('shop', 'invoice', detail);
        await repo.recoverJobAssignments('job');
      }
      final work = await repo.work();
      expect(work, hasLength(1));
      expect(work.single['employee_id'], 'kam');
      expect(work.single['estimated_minutes'], 60);
      expect(work.single['source_line_id'], 'oil');
      expect(work.single['source_active'], 1);
      expect(await repo.tasks(), hasLength(1));
      expect(
        jsonEncode(
          await LocalDocumentDetailCache(database: db).load('shop', 'invoice'),
        ),
        jsonEncode(detail),
      );
      expect(
        await db.customSelect('SELECT * FROM regular_payroll_payments').get(),
        isEmpty,
      );
    },
  );
}
