import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_work_source.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved labor requires the exact shop, job and active assignment',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('payroll-source-');
    final file = File('${directory.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
      await directory.delete(recursive: true);
    });
    await LocalDocumentDetailCache.initialize(db);
    await db.customStatement(
      "INSERT INTO local_jobs (id, business_id, access_scope, title, status) "
      "VALUES ('job-a', 'shop-a', 'owner', 'Repair', 'open')",
    );
    await db.customStatement(
      "INSERT INTO local_documents (id, business_id, job_id, kind) "
      "VALUES ('invoice-a', 'shop-a', 'job-a', 'invoice')",
    );
    await db.customStatement(
      "INSERT INTO local_job_assignments "
      "(assignment_id, business_id, job_id, employee_id) "
      "VALUES ('assignment-a', 'shop-a', 'job-a', 'employee-a')",
    );
    final cache = LocalDocumentDetailCache(database: db);
    await cache.save('shop-a', 'invoice-a', {
      'id': 'invoice-a',
      'kind': 'invoice',
      'job_id': 'job-a',
      'lines': [
        {'id': 'labor-a', 'line_kind': 'labor', 'description': 'Repair'},
        {'id': 'part-a', 'line_kind': 'part', 'name': 'Labor'},
        {'id': 'ambiguous', 'line_kind': 'labor'},
        {'id': 'ambiguous', 'line_kind': 'part'},
      ],
    });
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));

    var source = LocalPayrollWorkSource(db);
    Future<Map<String, dynamic>?> resolve({
      String business = 'shop-a',
      String job = 'job-a',
      String employee = 'employee-a',
      String line = 'labor-a',
    }) =>
        source.resolve(
          businessId: business,
          jobId: job,
          invoiceId: 'invoice-a',
          lineId: line,
          employeeId: employee,
        );

    expect((await resolve())?['description'], 'Repair');
    expect(await resolve(business: 'shop-b'), isNull);
    expect(await resolve(job: 'job-b'), isNull);
    expect(await resolve(employee: 'employee-b'), isNull);
    expect(await resolve(line: 'part-a'), isNull);
    expect(await resolve(line: 'ambiguous'), isNull);

    await db.customStatement(
      "INSERT INTO local_job_assignments "
      "(assignment_id, business_id, job_id, employee_id) "
      "VALUES ('assignment-b', 'shop-a', 'job-a', 'employee-b')",
    );
    var payroll = LocalPayrollRepository(db, business: 'shop-a', owner: true, deviceId: 'owner-device');
    Future<void> register(String employee) => payroll.registerAssignedLabor(
          jobId: 'job-a',
          invoiceId: 'invoice-a',
          lineId: 'labor-a',
          employeeId: employee,
          employeeName: employee,
          rateCents: 4000,
        );
    await payroll.bindPaymentAuthority(
      writerDeviceId: 'owner-device', assertVerifiedPairing: () {},
    );
    await register('employee-a');
    await register('employee-a');
    await register('employee-b');
    expect(await payroll.tasks(), hasLength(1));
    expect(await payroll.work(), hasLength(2));
    final mechanic = LocalPayrollRepository(db, business: 'shop-a', owner: false);
    void assertSession() {}
    Future<Map<String, dynamic>> ownWork(String employee) async =>
        (await mechanic.mechanicWork(
          job: 'job-a', employee: employee, assertSession: assertSession,
        )).single;
    Future<void> update(String employee, Map<String, dynamic> work,
        String state, int minutes) =>
        mechanic.updateMechanicWork(
          job: 'job-a',
          employee: employee,
          id: work['id'] as String,
          state: state,
          minutes: minutes,
          date: '2026-11-04',
          expectedRevision: work['revision'] as int,
          assertSession: assertSession,
        );
    final first = await ownWork('employee-a');
    final second = await ownWork('employee-b');
    expect(first.containsKey('rate_cents'), isFalse);
    await expectLater(update('employee-a', second, 'In Progress', 0), throwsStateError);
    await update('employee-a', first, 'In Progress', 0);
    await update('employee-a', await ownWork('employee-a'), 'Done', 150);
    expect((await ownWork('employee-b'))['state'], 'Open');
    expect((await payroll.jobs()).single['done'], 0);
    await update('employee-b', second, 'In Progress', 0);
    await update('employee-b', await ownWork('employee-b'), 'Done', 60);
    final selected = await payroll.work(employee: 'employee-a');
    Future<bool> verify(String operation) => payroll.verify(
          operation: operation,
          employee: 'employee-a',
          week: '2026-11-02',
          date: '2026-11-04',
          method: 'Cash',
          selected: selected,
          base: 0,
          hourlyAdjustment: 0,
          adjustmentReason: '',
          repayment: 0,
          confirmedNet: 10000,
        );

    var grantValid = true;
    final guardedPayroll = LocalPayrollRepository(
      db,
      business: 'shop-a',
      owner: true,
      deviceId: 'owner-device',
      assertOwnerGrant: () {
        if (!grantValid) throw StateError('Expired grant');
      },
    );
    await expectLater(
      guardedPayroll.verify(
        operation: 'expired-payment',
        employee: 'employee-a',
        week: '2026-11-02',
        date: '2026-11-04',
        method: 'Cash',
        selected: selected,
        base: 0,
        hourlyAdjustment: 0,
        adjustmentReason: '',
        repayment: 0,
        confirmedNet: 10000,
        beforeCommit: () async { grantValid = false; },
      ),
      throwsStateError,
    );
    expect(await payroll.history('employee-a'), isEmpty);
    // Both devices now have the same unpaid snapshot and cannot communicate.
    await db.close();
    final peerFile = await file.copy('${directory.path}/peer.sqlite');
    db = BriskersLocalDatabase(NativeDatabase(file));
    payroll = LocalPayrollRepository(
      db, business: 'shop-a', owner: true, deviceId: 'owner-device',
    );
    final peerDb = BriskersLocalDatabase(NativeDatabase(peerFile));
    try {
      final disconnected = LocalPayrollRepository(
        peerDb, business: 'shop-a', owner: true, deviceId: 'second-device',
      );
      await expectLater(disconnected.bindPaymentAuthority(
        writerDeviceId: 'second-device', assertVerifiedPairing: () {},
      ), throwsStateError);
      await expectLater(disconnected.verify(
        operation: 'disconnected-attempt',
        employee: 'employee-a',
        week: '2026-11-02',
        date: '2026-11-04',
        method: 'Cash',
        selected: selected,
        base: 0,
        hourlyAdjustment: 0,
        adjustmentReason: '',
        repayment: 0,
        confirmedNet: 10000,
      ), throwsStateError);
      expect(await disconnected.history('employee-a'), isEmpty);
    } finally {
      await peerDb.close();
    }
    expect(await verify('pay-a'), isTrue);
    final receipts = <String, Map<String, dynamic>>{};
    var loseResponse = true;
    Future<Map<String, dynamic>> server(
      String operation, Map<String, dynamic> payload,
    ) async {
      expect(operation, 'pay-a');
      expect(payload['employee'], 'employee-a');
      final prior = receipts.putIfAbsent(operation, () => payload);
      expect(payload, equals(prior));
      if (loseResponse) throw StateError('Connection lost after server commit');
      return {'operation_id': operation, 'status': 'recorded'};
    }
    await expectLater(payroll.reconcile(send: server), throwsStateError);
    expect(receipts, hasLength(1));
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    payroll = LocalPayrollRepository(db, business: 'shop-a', owner: true, deviceId: 'owner-device');
    source = LocalPayrollWorkSource(db);
    expect((await payroll.history('employee-a')).single['net'], 10000);
    expect(await payroll.history('employee-b'), isEmpty);
    final unpaid = (await payroll.work(employee: 'employee-b')).single;
    expect(unpaid['state'], 'Done');
    expect(unpaid['paid'], 0);
    expect(unpaid['gross_cents'], 4000);
    final jobs = await db.customSelect("SELECT status FROM local_jobs WHERE id='job-a'").get();
    expect(jobs.single.data['status'], 'open');
    loseResponse = false;
    expect(await payroll.reconcile(send: server), 1);
    expect(await payroll.reconcile(send: server), 0);
    expect(receipts, hasLength(1));
    expect(await payroll.history('employee-a'), hasLength(1));
    expect(await verify('pay-a'), isFalse);
    await expectLater(verify('pay-a-again'), throwsStateError);
    final nonOwner = LocalPayrollRepository(db, business: 'shop-a', owner: false);
    await expectLater(nonOwner.history('employee-a'), throwsStateError);
    await expectLater(nonOwner.reconcile(send: server), throwsStateError);
    final otherShop = LocalPayrollRepository(db, business: 'shop-b', owner: true);
    expect(await otherShop.history('employee-a'), isEmpty);

    await db.customStatement(
      "UPDATE local_job_assignments SET active = 0 "
      "WHERE assignment_id = 'assignment-a'",
    );
    expect(await resolve(), isNull);
  });
}
