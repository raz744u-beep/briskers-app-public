import 'dart:io';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:briskers_app/services/job_task_bulk_completion.dart';
import 'package:briskers_app/services/payroll_owner_ledger.dart';
import 'package:briskers_app/services/payroll_lan_peer.dart';
import 'dart:convert';
import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/verified_paid_labor.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'explicit In Progress payment is offline, per mechanic, immutable and restart/idempotency safe',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('progress-payroll-');
      final file = File('${dir.path}/shop.sqlite');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      var repo = LocalPayrollRepository(
        db,
        business: 'shop',
        owner: true,
        deviceId: 'owner',
      );
      await repo.prepare();
      await repo.bindPaymentAuthority(
        writerDeviceId: 'owner',
        assertVerifiedPairing: () {},
      );
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status) VALUES('job','shop','owner','Repair','open')",
      );
      for (final id in ['chris', 'kam']) {
        await db.customStatement(
          "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) VALUES(?, 'shop','job',?,?)",
          [id, id, id],
        );
        await repo.saveEmployeeCompensation(
          employee: id,
          name: id,
          rate: id == 'chris' ? 4000 : 3500,
          weeklyBase: false,
        );
      }
      await repo.createRecheck(
        operation: 'new-work',
        job: 'job',
        description: 'Replace engine',
        employee: 'chris',
        name: 'Chris',
        rate: 4000,
        estimatedMinutes: 1200,
      );
      var chris = (await repo.work(employee: 'chris')).single;
      final task = chris['task_id'] as String, id = chris['id'] as String;
      await repo.saveTaskSchedule(task, '2026-11-09', '2026-11-13', 'Normal');
      await repo.assignTask(task,'kam','Kam',rate:3500);
    await repo.setEstimatedMinutes(task, 'kam', 300);
      await repo.updateWork(id, 'In Progress', 0, '2026-11-09');
      chris = (await repo.work(employee: 'chris')).single;
      expect(chris['actual_minutes'], 0);
      expect(chris['remaining_minutes'], 1200);
      Future<bool> pay(
        String op,
        List<Map<String, dynamic>> selected,
        int net, {
        String week = '2026-11-09',
      }) => repo.verify(
        operation: op,
        employee: 'chris',
        week: week,
        date: week == '2026-11-09' ? '2026-11-13' : '2026-11-20',
        method: 'Cash',
        selected: selected,
        base: 0,
        hourlyAdjustment: 0,
        adjustmentReason: 'Owner explicitly selected In Progress hours',
        repayment: 0,
        confirmedNet: net,
      );
      await expectLater(
        pay('implicit', [
          {...chris, 'pay_minutes': 480},
        ], 32000),
        throwsStateError,
      );
      final request = [
        {...chris, 'allow_in_progress': true, 'pay_minutes': 480},
      ];
      await repo.savePayrollDraft('chris', '2026-11-09', {id: 8});
      expect(
        (await repo.payrollDraftDetails('chris', '2026-11-09'))!['hours'],
        {id: 8.0},
      );
      expect(await pay('eight-hours', request, 32000), true);
      expect(await pay('eight-hours', request, 32000), false);
      final cache = LocalFinancialCache(database: db);
      await cache.saveOptions('shop', {
        'accounts': [{'id': 'checking', 'name': 'Business Checking - 9858'}],
        'categories': [{'id': 'payroll', 'name': 'Payroll', 'normal_direction': 'expense'}],
      });
      final expenses = OfflineFinancialWriteService(database: db, cache: cache);
      await expenses.materializePendingPayrollExpenses('shop');
      await expenses.materializePendingPayrollExpenses('shop');
      final expense = (await cache.loadTransactions('shop')).single;
      expect(expense['payroll_operation_id'], 'eight-hours');
      expect(expense['account_id'], 'checking');
      expect(expense['category_id'], 'payroll');
      expect(expense['payment_method'], 'Cash');
      expect(expense['amount'], 320);
      expect(expense['transaction_date'], '2026-11-13');
      chris = (await repo.work(employee: 'chris')).single;
      expect(chris['state'], 'In Progress');
      expect(chris['paid_minutes'], 480);
      expect(chris['remaining_minutes'], 720);
      expect(chris['last_paid_week'], '2026-11-09');
      await expectLater(
        pay('fresh-same-week', [
          {...chris, 'allow_in_progress': true, 'pay_minutes': 480},
        ], 32000),
        throwsStateError,
      );
      final paidHistoryBeforeCorrection = jsonEncode(await repo.historyWithWork('chris'));
      await repo.setEstimatedMinutes(task, 'chris', 1560);
      chris = (await repo.work(employee: 'chris')).single;
      expect(chris['estimated_minutes'], 1560);
      expect(chris['paid_minutes'], 480);
      expect(chris['remaining_minutes'], 1080);
      await expectLater(pay('implicit-increase', [{...chris, 'pay_minutes': 1080}], 72000,
        week: '2026-11-16'), throwsStateError);
      expect(chris['actual_minutes'], 0);
      expect(chris['state'], 'In Progress');
      expect(jsonEncode(await repo.historyWithWork('chris')), paidHistoryBeforeCorrection);
      expect(await repo.taskPaymentHistory(task), hasLength(1));
      await expectLater(repo.setEstimatedMinutes(task, 'chris', 479), throwsStateError);
      // Repeating an identical correction neither changes wages nor adds audit.
      await repo.setEstimatedMinutes(task, 'chris', 1560);
      expect((await db.customSelect("SELECT * FROM regular_payroll_audit WHERE event='owner_corrected_planned_hours'").get()), hasLength(1));
      await repo.saveServiceTask(operation: 'editor-plan-correction', task: task, job: 'job',
        description: 'Replace engine', mechanics: [
          {'employee': 'chris', 'previous': 'chris', 'name': 'Chris', 'minutes': 1200},
          {'employee': 'kam', 'previous': 'kam', 'name': 'Kam', 'minutes': 300},
        ], start: '2026-11-09', end: '2026-11-13', priority: 'Normal',
        status: 'In Progress', treatment: 'preserve');
      chris = (await repo.work(employee: 'chris')).single;
      expect(chris['estimated_minutes'], 1200);
      expect(jsonEncode(await repo.historyWithWork('chris')), paidHistoryBeforeCorrection);
      expect(chris['actual_minutes'], 0);
      expect(
        await VerifiedPaidLabor(db).allocations('shop'),
        isNot(contains(id)),
      );
      final kam = (await repo.work(employee: 'kam')).single;
      expect(kam['state'], 'Open', reason: 'Editing Chris planned hours must not start another mechanic');
      expect(kam['paid_minutes'], 0);
      expect(kam['estimated_minutes'], 300);
      final replica=BriskersLocalDatabase(NativeDatabase.memory());
    final mechanic=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(replica.close);addTearDown(mechanic.close);
    final replicaLedger=PayrollOwnerLedger(replica,'shop');
    final mechanicRepo=LocalPayrollRepository(mechanic,business:'shop',owner:false,pairedEmployee:'chris');
    Future<void> assignment(int revision)async{final saved=(await repo.assignmentSnapshots('chris')).single;await mechanicRepo.applyLanChange(PayrollLanOperation.assignment,{...saved,'assignment_revision':revision},employee:'chris',assertLink:(){});}
    Future<void> receipt(String op,String week,int net)async{await mechanicRepo.applyLanChange(PayrollLanOperation.payment,{'operation':op,'employee':'chris','week':week,'date':week=='2026-11-09'?'2026-11-13':'2026-11-20','method':'Cash','gross':net,'net':net,'repayment':0,'work':[id],'coverage':await repo.recordedCoverage('chris',op)},employee:'chris',assertLink:(){});}
    await replicaLedger.mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);
    await assignment(1);await receipt('eight-hours','2026-11-09',32000);await receipt('eight-hours','2026-11-09',32000);
    await repo.setEstimatedMinutes(task, 'chris', 1560);
    await replicaLedger.mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);
    await assignment(2);
    expect((await LocalPayrollRepository(replica,business:'shop',owner:true).work(employee:'chris')).single['estimated_minutes'],1560);
    expect((await mechanic.customSelect('SELECT minutes FROM regular_payroll_estimates').getSingle()).data['minutes'],1560);
    await repo.setEstimatedMinutes(task, 'chris', 1200);
    await replicaLedger.mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);
    await assignment(3);

    expect((await mechanic.customSelect('SELECT state FROM regular_payroll_portions').getSingle()).data['state'],'In Progress');
    final original = jsonEncode(await repo.historyWithWork('chris'));
      expect((await repo.taskPaymentHistory(task)).single['amount'], 32000);
      expect((await repo.historyWithWork('chris')).single['net'], 32000);
      await expectLater(
        repo.setEstimatedMinutes(task, 'chris', 479),
        throwsStateError,
      );
      await expectLater(pay('stale', request, 32000), throwsStateError);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      repo = LocalPayrollRepository(
        db,
        business: 'shop',
        owner: true,
        deviceId: 'owner',
        assertOwnerGrant: () {},
      );
      expect(await pay('eight-hours', request, 32000), false);
      expect(jsonEncode(await repo.historyWithWork('chris')), original);
      chris = (await repo.work(employee: 'chris')).single;
      await expectLater(
        pay(
          'too-many',
          [
            {...chris, 'allow_in_progress': true, 'pay_minutes': 721},
          ],
          48067,
          week: '2026-11-16',
        ),
        throwsStateError,
      );
      final rest = [
        {...chris, 'allow_in_progress': true, 'pay_minutes': 720},
      ];
      expect(await pay('remaining', rest, 48000, week: '2026-11-16'), true);
      chris = (await repo.work(employee: 'chris')).single;
      expect(chris['state'], 'In Progress');
      expect(chris['paid_minutes'], 1200);
      expect(chris['remaining_minutes'], 0);
      expect(
        await VerifiedPaidLabor(db).allocations('shop'),
        isNot(contains(id)),
      );
      await receipt('remaining','2026-11-16',48000);
    await replicaLedger.mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);
    final paid = jsonEncode(await repo.historyWithWork('chris'));
      final bulk=JobTaskBulkCompletion(repo);
    final plan=await bulk.plan('job',DateTime(2026,11,20));
    expect(plan.labor,hasLength(2));
    expect(await bulk.complete(plan,DateTime(2026,11,20)),1);
    expect(await bulk.complete(plan,DateTime(2026,11,20)),0);
      chris = (await repo.work(employee: 'chris')).single;
      expect(chris['state'], 'Done');
      expect(chris['can_edit_planned_hours'], isFalse);
      await expectLater(repo.setEstimatedMinutes(task, 'chris', 1560), throwsStateError);
      expect(chris['paid_minutes'], 1200);
      expect(chris['remaining_minutes'], 0);
      expect(jsonEncode(await repo.historyWithWork('chris')), paid);
    await assignment(4);
    await replicaLedger.mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);
    expect((await mechanic.customSelect('SELECT state FROM regular_payroll_portions').getSingle()).data['state'],'Done');
    expect((await LocalPayrollRepository(replica,business:'shop',owner:true).work(employee:'chris')).single['remaining_minutes'],0);
      await expectLater(
        repo.finishPaidProgress(id, '2026-11-20'),
        throwsStateError,
      );
      expect((await repo.taskPaymentHistory(task)), hasLength(2));

      Future<bool> reverse(String operation) => repo.reversePayment(
        operation: operation, employee: 'chris', actorId: 'owner',
        reason: 'Duplicate recording fixture',
      );
      await expectLater(reverse('eight-hours'), throwsStateError);
      final afterRestart = OfflineFinancialWriteService(database: db);
      await afterRestart.materializePendingPayrollExpenses('shop');
      expect(await LocalFinancialCache(database: db).loadTransactions('shop'), hasLength(2));
      expect(await reverse('remaining'), isTrue);
      expect(await reverse('remaining'), isFalse);
      final reversed = (await repo.historyWithWork('chris'))
          .singleWhere((row) => row['operation_id'] == 'remaining');
      expect(reversed['net'], 48000);
      expect(reversed['reversal_reason'], 'Duplicate recording fixture');
      expect(reversed['work'], hasLength(1));
      expect((await repo.taskPaymentHistory(task)).single['amount'], 32000);
      expect((await repo.work(employee: 'chris')).single['paid_minutes'], 480);
      expect((await repo.work(employee: 'chris')).single['remaining_minutes'], 720);
      expect(await LocalFinancialCache(database: db).loadTransactions('shop'), hasLength(1));
      await replicaLedger.mergeSnapshot(await PayrollOwnerLedger(db,'shop').export(),canonical:true);
      expect((await LocalPayrollRepository(replica,business:'shop',owner:true).work(employee:'chris')).single['remaining_minutes'],720);

    },
  );

  test(
    'issue 501: older untagged partial payroll must not block Owner plan edits',
    () async {
      // Synthetic-only reproduction of older covered labor: the payment exists
      // but its snapshot predates the in_progress_payment metadata. Never
      // change production receipts or mechanic payment evidence to reproduce.
      SharedPreferences.setMockInitialValues({});
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalPayrollRepository(
        db, business: 'shop', owner: true, deviceId: 'owner',
      );
      await repo.prepare();
      await repo.bindPaymentAuthority(
        writerDeviceId: 'owner', assertVerifiedPairing: () {},
      );
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status) "
        "VALUES('legacy-job','shop','owner','Synthetic labor','open')",
      );
      await db.customStatement(
        "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) "
        "VALUES('legacy-chris','shop','legacy-job','chris','Chris')",
      );
      await repo.saveEmployeeCompensation(
        employee: 'chris', name: 'Chris', rate: 4000, weeklyBase: false,
      );
      await repo.createRecheck(
        operation: 'legacy-task', job: 'legacy-job',
        description: 'Synthetic engine labor',
        employee: 'chris', name: 'Chris', rate: 4000,
        estimatedMinutes: 1200,
      );
      var row = (await repo.work(employee: 'chris')).single;
      final taskId = row['task_id'] as String;
      final allocationId = row['id'] as String;
      await repo.saveTaskSchedule(taskId, '2026-11-09', '2026-11-13', 'Normal');
      await repo.updateWork(allocationId, 'In Progress', 0, '2026-11-09');
      row = (await repo.work(employee: 'chris')).single;
      // Seed an OLD-SHAPE synthetic receipt as an initial, append-only
      // fixture. After verification the SQLite triggers prohibit UPDATE/DELETE
      // of payment coverage; a modern verify() followed by rewriting its
      // snapshot is not a valid way to reproduce historical input.
      final legacy = <String, dynamic>{
        ...row,
        'employee_name': 'Chris',
        'total_credit_minutes': row['actual_minutes'],
        'credit_revision': row['version'],
        'actual_minutes': 480,
        'hours_hundredths': 800,
        'gross_cents': 32000,
        'payment_rate_cents': 4000,
      };
      expect(legacy.containsKey('in_progress_payment'), isFalse);
      final legacyPayload = jsonEncode({
        'employee': 'chris',
        'week': '2026-11-09',
        'date': '2026-11-13',
        'method': 'Cash',
        'work': [{
          'id': allocationId,
          'version': row['version'],
          'hours': row['hours_hundredths'],
          'minutes': row['actual_minutes'],
          'rate': row['rate_cents'],
          'pay_minutes': 480,
        }],
        'base': 0,
        'adjustment': 0,
        'reason': 'Synthetic older payroll coverage',
        'repayment': 0,
        'confirmed_net': 32000,
      });
      await db.transaction(() async {
        await db.customStatement(
          'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
          ['shop', 'legacy-eight', 'chris', '2026-11-09', legacyPayload,
            32000, 0, 32000, 'Cash', '2026-11-13'],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
          ['shop', allocationId, 'legacy-eight', 480, 32000,
            jsonEncode(legacy)],
        );
      });
      // The legacy record is immutable after insertion; test the permission
      // decision, not a backdated alteration of an existing payment.


      row = (await repo.work(employee: 'chris')).single;
      expect(row['state'], 'In Progress');
      expect(row['paid_minutes'], 480);
      expect(row['estimated_minutes'], 1200);
      expect(row['actual_minutes'], 0);
      // RED until the saved-ledger permission path supports this older shape.
      // No one may unlock completed/historical allocations merely by removing
      // this metadata guard; active state + payment history must be verified.
      expect(row['can_edit_planned_hours'], isTrue,
        reason: 'An active partially-paid task must permit safe planned-hours corrections');

      final payrollBefore = jsonEncode(await repo.historyWithWork('chris'));
      await repo.setEstimatedMinutes(taskId, 'chris', 1560);
      row = (await repo.work(employee: 'chris')).single;
      expect(row['state'], 'In Progress');
      expect(row['estimated_minutes'], 1560);
      expect(row['paid_minutes'], 480);
      expect(row['remaining_minutes'], 1080);
      expect(row['actual_minutes'], 0);
      expect(jsonEncode(await repo.historyWithWork('chris')), payrollBefore);
      expect(await repo.taskPaymentHistory(taskId), hasLength(1));
      await expectLater(
        repo.setEstimatedMinutes(taskId, 'chris', 479), throwsStateError,
      );
    },
  );
}
