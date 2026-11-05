import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invoice edits, conversions, partial payments and rechecks preserve earned work',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('payroll-restored');
    final file = File('${directory.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
      await directory.delete(recursive: true);
    });
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,assigned_employee_id) "
      "VALUES('job','shop','owner','Repair','open','mechanic')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind) "
      "VALUES('invoice','shop','job','invoice'),('estimate','shop','job','estimate')",
    );
    await db.customStatement(
      "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) "
      "VALUES('assignment','shop','job','mechanic','Mechanic')",
    );
    var ledger = LocalPayrollRepository(db, business: 'shop', owner: true, deviceId: 'owner');
    await ledger.bindPaymentAuthority(writerDeviceId: 'owner', assertVerifiedPairing: () {});
    await ledger.saveEmployeeCompensation(
      employee: 'mechanic', name: 'Mechanic', rate: 1001, weeklyBase: false,
    );
    Map<String, dynamic> invoice(String description, num quantity, {String id = 'invoice'}) => {
      'id': id, 'job_id': 'job', 'kind': id == 'estimate' ? 'estimate' : 'invoice',
      'lines': [
        {'id': 'line', 'line_kind': 'labor', 'description': description, 'quantity': quantity},
      ],
    };
    await LocalDocumentDetailCache(database: db).save('shop', 'estimate',
      invoice('Estimate', 2, id: 'estimate'));
    expect(await ledger.tasks(), isEmpty);
    await LocalDocumentDetailCache(database: db).save('shop', 'invoice', invoice('Repair', 2));
    expect(await ledger.tasks(), hasLength(1));
    await ledger.refreshInvoiceTasks();
    final assignment = (await ledger.work()).single;
    expect(assignment['actual_minutes'], 0);
    expect(assignment['estimated_minutes'], 120);
    await LocalDocumentDetailCache(database: db).save('shop', 'invoice', {
      'id': 'invoice', 'job_id': 'job', 'kind': 'invoice', 'lines': <dynamic>[],
    });
    await ledger.refreshInvoiceTasks();
    await expectLater(ledger.updateWork(
      assignment['id'] as String, 'In Progress', 0, '2026-11-04',
    ), throwsStateError);
    await LocalDocumentDetailCache(database: db).save('shop', 'invoice', invoice('Repair', 2));

    await ledger.setEstimatedMinutes(assignment['task_id'] as String, 'mechanic', 90);
    await LocalDocumentDetailCache(database: db).save('shop', 'invoice', invoice('Repair updated', 3));
    await ledger.refreshInvoiceTasks();
    final revised = (await ledger.work()).single;
    expect(revised['estimated_minutes'], 90);
    expect((await ledger.tasks()).single['planned'], 300);
    await ledger.updateWork(revised['id'] as String, 'In Progress', 0, '2026-11-04');
    await ledger.updateWork(revised['id'] as String, 'Done', 100, '2026-11-04');
    Future<bool> pay(String operation, int minutes, int net) async {
      final work = (await ledger.work()).where((row) => row['id'] == revised['id']).single;
      return ledger.verify(
        operation: operation, employee: 'mechanic', week: '2026-11-02',
        date: '2026-11-04', method: 'Cash', selected: [{...work, 'pay_minutes': minutes}],
        base: 0, hourlyAdjustment: 0, adjustmentReason: '', repayment: 0, confirmedNet: net,
      );
    }
    expect(await pay('first', 20, 334), isTrue);
    var balance = (await ledger.work()).single;
    expect(balance['remaining_minutes'], 40);
    expect(balance['remaining_cents'], 667);
    expect(balance['pay_status'], 'Partially Paid');
    await expectLater(ledger.updateWork(
      revised['id'] as String, 'Open', 0, '2026-11-04',
    ), throwsA(anything));
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    ledger = LocalPayrollRepository(db, business: 'shop', owner: true, deviceId: 'owner');
    expect(await pay('second', 20, 333), isTrue);
    expect(await pay('third', 20, 334), isTrue);
    balance = (await ledger.work()).single;
    expect(balance['pay_status'], 'Paid');
    expect(balance['paid_cents'], 1001);
    expect(balance['remaining_minutes'], 0);
    expect((await ledger.historyWithWork('mechanic')).fold<int>(
      0, (sum, row) => sum + (row['gross'] as int),
    ), 1001);

    await db.customStatement(
      "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) "
      "VALUES('weekly-assignment','shop','job','weekly','Weekly mechanic')",
    );
    await ledger.createRecheck(
      operation: 'weekly-recheck', job: 'job', description: 'Weekly work',
      employee: 'weekly', name: 'Weekly mechanic', rate: 2000, estimatedMinutes: 60,
    );
    await ledger.enableWeeklyBase('weekly', 'Weekly mechanic');
    await ledger.recordOpeningAdvance('weekly', 2000);
    final weeklyWork = (await ledger.work(employee: 'weekly')).single;
    await ledger.updateWork(weeklyWork['id'] as String, 'In Progress', 0, '2026-11-04');
    await ledger.updateWork(weeklyWork['id'] as String, 'Done', 100, '2026-11-04');
    final eligible = (await ledger.work(employee: 'weekly')).single;
    expect(await ledger.verify(
      operation: 'weekly-settlement', employee: 'weekly', week: '2026-11-02',
      date: '2026-11-04', method: 'Zelle',
      selected: [{...eligible, 'pay_minutes': 60, 'payment_rate_cents': 1000}],
      base: 80000, hourlyAdjustment: 0,
      adjustmentReason: 'Approved base plus supplemental labor',
      repayment: 2000, confirmedNet: 79000,
    ), isTrue);
    final weeklyPayment = (await ledger.historyWithWork('weekly')).single;
    expect(weeklyPayment['gross'], 81000);
    expect(weeklyPayment['repayment'], 2000);
    expect(weeklyPayment['net'], 79000);
    expect((weeklyPayment['work'] as List).single['gross_cents'], 1000);
    expect((await ledger.work(employee: 'weekly')).single['pay_status'], 'Paid');
    expect(await ledger.advance('weekly'), 0);
    await ledger.createRecheck(
      operation: 'included-recheck', job: 'job', description: 'Included weekly work',
      employee: 'weekly', name: 'Weekly mechanic', rate: 2000, estimatedMinutes: 30,
    );
    final included = (await ledger.work(employee: 'weekly')).where((row) => row['state'] == 'Open').single;
    await ledger.updateWork(included['id'] as String, 'In Progress', 0, '2026-11-09');
    await ledger.updateWork(included['id'] as String, 'Done', 50, '2026-11-09');
    final includedCredit = (await ledger.work(employee: 'weekly')).where((row) => row['id'] == included['id']).single;
    expect(await ledger.verify(
      operation: 'base-inclusive', employee: 'weekly', week: '2026-11-09',
      date: '2026-11-09', method: 'Cash',
      selected: [{...includedCredit, 'pay_minutes': 30, 'payment_rate_cents': 0}],
      base: 80000, hourlyAdjustment: 0, adjustmentReason: 'Labor included in weekly base',
      repayment: 0, confirmedNet: 80000,
    ), isTrue);
    expect((await ledger.work(employee: 'weekly')).where((row) => row['id'] == included['id'])
        .single['remaining_minutes'], 0);

    await LocalDocumentDetailCache(database: db).save('shop', 'invoice', {
      'id': 'invoice', 'job_id': 'job', 'kind': 'invoice', 'lines': <dynamic>[],
    });
    await ledger.refreshInvoiceTasks();
    expect((await ledger.tasks()).where((row) => row['source_kind'] == 'invoice').single['source_active'], 0);
    expect((await ledger.work(employee: 'mechanic')).single['pay_status'], 'Paid');
    await ledger.createRecheck(
      operation: 'recheck', job: 'job', description: 'Reinspect', employee: 'mechanic',
      name: 'Mechanic', rate: 1001, estimatedMinutes: 30,
    );
    await ledger.createRecheck(
      operation: 'recheck', job: 'job', description: 'Reinspect', employee: 'mechanic',
      name: 'Mechanic', rate: 1001, estimatedMinutes: 30,
    );
    expect(await ledger.tasks(), hasLength(4));
    final additional = (await ledger.work(employee: 'mechanic')).where((row) => row['source_kind'] == 'recheck').single;
    expect(additional['pay_status'], 'Unpaid');
    expect((await ledger.work()).where((row) => row['id'] == revised['id']).single['pay_status'], 'Paid');
    await db.customStatement("UPDATE local_documents SET kind='invoice' WHERE id='estimate'");
    await LocalDocumentDetailCache(database: db).save('shop', 'estimate', {
      ...invoice('Converted labor', 2, id: 'estimate'), 'kind': 'invoice',
    });
    await ledger.refreshInvoiceTasks();
    expect((await ledger.tasks()).where((row) => row['invoice_id'] == 'estimate'), hasLength(1));
    expect((await ledger.historyWithWork('mechanic')).length, 3);
  });
}
