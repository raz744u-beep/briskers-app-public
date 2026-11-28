import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';
import 'package:briskers_app/services/local_owner_reports.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_shop_closeout.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('closeout shows remaining labor, verified invoices and active jobs without changing records', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final reports = LocalOwnerReports(database: db);
    final agenda = LocalShopCloseout(reports);
    final now = DateTime.utc(2026, 11, 27, 21);
    SharedPreferences.setMockInitialValues({
      'briskers_document_detail_shop_paid': jsonEncode({
        'id': 'paid',
        'business_id': 'shop',
        'kind': 'invoice',
        'job_id': 'job',
        'status': 'issued',
        'document_number': '100',
        'total_amount': 100,
        'paid_amount': 100,
        'pending_payment': 0,
      }),
    });
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) VALUES "
      "('job','shop','owner','Repair','in_progress','J-1'),"
      "('done','shop','owner','Done','completed','J-2'),"
      "('foreign','other','owner','Other shop','open','J-3')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,kind,job_id,total,document_date,status,display_status_code,document_number) VALUES "
      "('paid','shop','invoice','job',100,'2026-11-19','issued','paid','100'),"
      "('unverified','shop','invoice','job',75,'2026-11-19','issued','paid','101'),"
      "('closed','shop','invoice','done',50,'2026-11-19','closed','closed','102')",
    );
    await LocalPayrollRepository(db, business: 'shop', owner: true).prepare();
    await EmployeeNicknameStore(database: db).save('shop', 'mechanic', 'Mac');
    await db.customStatement(
      "INSERT INTO regular_payroll_employees VALUES ('shop','mechanic','Mechanic Name',4000,0)",
    );
    await db.customStatement(
      "INSERT INTO regular_payroll_tasks VALUES ('shop','task','job','line','Repair labor',180)",
    );
    await db.customStatement(
      "INSERT INTO regular_payroll_task_sources(business_id,task_id,invoice_id,line_id,source_kind) "
      "VALUES('shop','task','paid','line','invoice')",
    );
    await db.customStatement(
      "INSERT INTO regular_payroll_portions VALUES ('shop','allocation','task','mechanic','Done',0,'2026-11-19')",
    );
    await db.customStatement(
      "INSERT INTO local_mechanic_work_credits_v1 "
      "(business_id,allocation_id,job_id,labor_line_id,task_id,employee_id,actual_minutes,rate_cents,completed) "
      "VALUES ('shop','allocation','job','line','task','mechanic',180,4000,1)",
    );
    await db.customStatement(
      "INSERT INTO regular_payroll_work_coverage VALUES ('shop','allocation','part',60,4000,'{}')",
    );
    final before = await reports.revision();

    await expectLater(
      agenda.load('shop', isOwner: false, now: now),
      throwsStateError,
    );
    final result = await agenda.load('shop', isOwner: true, now: now);
    expect(result.friday, DateTime(2026, 11, 27));
    expect(result.labor.single.title, contains('Mac · J-1'));
    expect(
      result.labor.single.detail,
      contains('2.00 unpaid hrs · Prior-week carryover'),
    );
    expect(result.invoices.map((row) => row.id), ['paid']);
    expect(result.jobs.map((row) => row.id), ['job']);
    expect(
      result.verify.any((message) => message.contains('Invoice 101')),
      isTrue,
    );
    expect(await reports.revision(), before);
  });

  test('uninitialized labor records are flagged for verification', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final closeout = await LocalShopCloseout(LocalOwnerReports(database: db))
        .load('shop', isOwner: true);
    expect(closeout.payrollAvailable, isFalse);
    expect(
      closeout.verify,
      contains(contains('Saved payroll could not be read')),
    );
  });
}
