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
import 'package:drift/drift.dart' show Variable;
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
      expect(row['can_finish_paid_progress'], isFalse,
        reason: 'Legacy plan correction must not silently unlock completion');
      // Only an active, unfinished legacy partial receipt permits a plan edit.
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
      // The real Edit Service Task screen saves through this API, not solely
      // through setEstimatedMinutes. It must preserve payment history too.
      await repo.saveServiceTask(
        operation: 'legacy-owner-edits-plan', task: taskId, job: 'legacy-job',
        description: 'Synthetic engine labor',
        mechanics: [
          {'employee': 'chris', 'previous': 'chris', 'name': 'Chris', 'minutes': 1500},
        ],
        start: '2026-11-09', end: '2026-11-13', priority: 'Normal',
        status: 'In Progress', treatment: 'preserve',
      );
      row = (await repo.work(employee: 'chris')).single;
      expect(row['estimated_minutes'], 1500);
      expect(row['paid_minutes'], 480);
      expect(row['remaining_minutes'], 1020);
      expect(row['actual_minutes'], 0);
      expect(jsonEncode(await repo.historyWithWork('chris')), payrollBefore);
      expect(await repo.taskPaymentHistory(taskId), hasLength(1));
      await expectLater(
        repo.setEstimatedMinutes(taskId, 'chris', 479), throwsStateError,
      );
      // A fully covered older receipt must not acquire edit permission.
      await repo.setEstimatedMinutes(taskId, 'chris', 480);
      row = (await repo.work(employee: 'chris')).single;
      expect(row['remaining_minutes'], 0);
      expect(row['can_edit_planned_hours'], isFalse);
      await expectLater(
        repo.setEstimatedMinutes(taskId, 'chris', 1560), throwsStateError,
      );
      expect(jsonEncode(await repo.historyWithWork('chris')), payrollBefore);
    },
  );

  test(
    'issue 501: eight recorded and eight paid legacy hours remain active for Owner plan edits',
    () async {
      // Diagnostic reproduction: an explicitly In Progress allocation with
      // 20 planned hours, 8 actual recorded hours and 8 already paid. Unlike
      // the zero-actual fixture above, this is vulnerable to being projected
      // Done by VerifiedPaidLabor solely because actual == paid.
      // All records are synthetic, memory-only and append-only.
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
        "VALUES('earned-job','shop','owner','Synthetic active labor','open')",
      );
      await db.customStatement(
        "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) "
        "VALUES('earned-chris','shop','earned-job','chris','Chris')",
      );
      await repo.saveEmployeeCompensation(
        employee: 'chris', name: 'Chris', rate: 4000, weeklyBase: false,
      );
      await repo.createRecheck(
        operation: 'earned-task', job: 'earned-job',
        description: 'Synthetic eight hours completed so far',
        employee: 'chris', name: 'Chris', rate: 4000,
        estimatedMinutes: 1200,
      );
      var row = (await repo.work(employee: 'chris')).single;
      final taskId = row['task_id'] as String;
      final allocationId = row['id'] as String;
      await repo.saveTaskSchedule(taskId, '2026-11-09', '2026-11-13', 'Normal');
      await repo.updateWork(allocationId, 'In Progress', 800, '2026-11-09');
      row = (await repo.work(employee: 'chris')).single;
      expect(row['state'], 'In Progress');
      expect(row['actual_minutes'], 480);
      expect(row['recorded_actual_minutes'], 480);
      expect(row['credit_completed'], 0);

      final legacySnapshot = <String, dynamic>{
        ...row,
        'employee_name': 'Chris',
        'total_credit_minutes': 480,
        'credit_revision': row['version'],
        'payment_rate_cents': 4000,
      };
      expect(legacySnapshot.containsKey('in_progress_payment'), isFalse);
      final legacyPayload = jsonEncode({
        'employee': 'chris',
        'week': '2026-11-09',
        'date': '2026-11-13',
        'method': 'Cash',
        'work': [{
          'id': allocationId,
          'version': row['version'],
          'hours': row['hours_hundredths'],
          'minutes': 480,
          'rate': row['rate_cents'],
          'pay_minutes': 480,
        }],
        'base': 0,
        'adjustment': 0,
        'reason': 'Synthetic older earned-hours coverage',
        'repayment': 0,
        'confirmed_net': 32000,
      });
      await db.transaction(() async {
        await db.customStatement(
          'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
          ['shop', 'earned-eight', 'chris', '2026-11-09', legacyPayload,
            32000, 0, 32000, 'Cash', '2026-11-13'],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
          ['shop', allocationId, 'earned-eight', 480, 32000,
            jsonEncode(legacySnapshot)],
        );
      });

      final historyBefore = jsonEncode(await repo.historyWithWork('chris'));
      final coverageBefore = jsonEncode((await db.customSelect(
        "SELECT * FROM regular_payroll_work_coverage WHERE business_id='shop' "
        'AND credit_id=? ORDER BY operation_id',
        variables: [Variable<String>(allocationId)],
      ).get()).map((r) => r.data).toList());

      row = (await repo.work(employee: 'chris')).single;
      expect(row['paid_minutes'], 480);
      expect(row['estimated_minutes'], 1200);
      expect(row['actual_minutes'], 480);
      expect(row['recorded_actual_minutes'], 480);
      expect(row['state'], 'In Progress',
        reason: 'Paying earned hours must not silently complete an active task');
      expect(row['can_edit_planned_hours'], isTrue,
        reason: 'Owner should edit remaining planned time without rewriting paid work');

      await repo.saveServiceTask(
        operation: 'earned-owner-edits-plan', task: taskId, job: 'earned-job',
        description: 'Synthetic eight hours completed so far',
        mechanics: [
          {'employee': 'chris', 'previous': 'chris', 'name': 'Chris', 'minutes': 1560},
        ],
        start: '2026-11-09', end: '2026-11-13', priority: 'Normal',
        status: 'In Progress', treatment: 'preserve',
      );
      row = (await repo.work(employee: 'chris')).single;
      expect(row['state'], 'In Progress');
      expect(row['estimated_minutes'], 1560);
      expect(row['actual_minutes'], 480);
      expect(row['recorded_actual_minutes'], 480);
      expect(row['paid_minutes'], 480);
      expect(row['remaining_minutes'], 1080);
      expect(jsonEncode(await repo.historyWithWork('chris')), historyBefore,
        reason: 'Changing a plan must not create or alter any payroll payment');
      final coverageAfter = jsonEncode((await db.customSelect(
        "SELECT * FROM regular_payroll_work_coverage WHERE business_id='shop' "
        'AND credit_id=? ORDER BY operation_id',
        variables: [Variable<String>(allocationId)],
      ).get()).map((r) => r.data).toList());
      expect(coverageAfter, coverageBefore);
      await expectLater(
        repo.setEstimatedMinutes(taskId, 'chris', 479), throwsStateError,
        reason: 'The Owner cannot reduce planned hours below the 8 paid hours');

      // Negative control: another legacy 8h-recorded/8h-paid allocation was
      // actually completed by the mechanic. It must not gain the edit grant
      // merely because its original plan was 20h. Neither frozen payroll nor
      // Done status may be altered by the compatibility exception.
      await repo.createRecheck(
        operation: 'finished-task', job: 'earned-job',
        description: 'Synthetic completed labor',
        employee: 'chris', name: 'Chris', rate: 4000,
        estimatedMinutes: 1200,
      );
      var finished = (await repo.work(employee: 'chris'))
          .singleWhere((r) => r['task_id'] != taskId);
      final finishedTask = finished['task_id'] as String;
      final finishedAllocation = finished['id'] as String;
      await repo.updateWork(finishedAllocation, 'In Progress', 800, '2026-11-09');
      await repo.updateWork(finishedAllocation, 'Done', 800, '2026-11-13');
      finished = (await repo.work(employee: 'chris'))
          .singleWhere((r) => r['task_id'] == finishedTask);
      expect(finished['actual_minutes'], 480);
      expect(finished['credit_completed'], 1);
      final completedSnapshot = <String, dynamic>{
        ...finished,
        'payment_rate_cents': 4000,
      };
      expect(completedSnapshot.containsKey('in_progress_payment'), isFalse);
      await db.transaction(() async {
        await db.customStatement(
          'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
          ['shop', 'completed-eight', 'chris', '2026-11-09',
            jsonEncode({'employee': 'chris', 'reason': 'Synthetic completed coverage'}),
            32000, 0, 32000, 'Cash', '2026-11-13'],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
          ['shop', finishedAllocation, 'completed-eight', 480, 32000,
            jsonEncode(completedSnapshot)],
        );
      });
      finished = (await repo.work(employee: 'chris'))
          .singleWhere((r) => r['task_id'] == finishedTask);
      expect(finished['state'], 'Done');
      expect(finished['can_edit_planned_hours'], isFalse);
      await expectLater(
        repo.setEstimatedMinutes(finishedTask, 'chris', 1560), throwsStateError,
        reason: 'Completed covered labor must remain immutable');
    },
  );

  for (final firstReceipt in ['legacy-untagged', 'modern-tagged']) {
    test(
      'issue 501: later explicit denial overrides earlier $firstReceipt receipt',
      () async {
        // All records are synthetic, inserted once. A paid coverage snapshot
        // must never be UPDATEd or DELETEd to construct this scenario.
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
          "VALUES('multi-job','shop','owner','Synthetic labor','open')",
        );
        await db.customStatement(
          "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) "
          "VALUES('multi-chris','shop','multi-job','chris','Chris')",
        );
        await repo.saveEmployeeCompensation(
          employee: 'chris', name: 'Chris', rate: 4000, weeklyBase: false,
        );
        await repo.createRecheck(
          operation: 'multi-task', job: 'multi-job',
          description: 'Synthetic engine labor', employee: 'chris',
          name: 'Chris', rate: 4000, estimatedMinutes: 1200,
        );
        var row = (await repo.work(employee: 'chris')).single;
        final taskId = row['task_id'] as String;
        final allocationId = row['id'] as String;
        await repo.updateWork(allocationId, 'In Progress', 0, '2026-11-09');
        row = (await repo.work(employee: 'chris')).single;
        final firstSnapshot = <String, dynamic>{
          ...row,
          'actual_minutes': 480,
          'payment_rate_cents': 4000,
          if (firstReceipt == 'modern-tagged') 'in_progress_payment': true,
        };
        final deniedSnapshot = <String, dynamic>{
          ...row,
          'actual_minutes': 60,
          'payment_rate_cents': 4000,
          'in_progress_payment': false,
        };
        await db.transaction(() async {
          for (final receipt in [
            ('a-first', 480, 32000, firstSnapshot),
            ('z-denied', 60, 4000, deniedSnapshot),
          ]) {
            await db.customStatement(
              'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
              ['shop', receipt.$1, 'chris', '2026-11-09',
                jsonEncode({'employee': 'chris', 'operation': receipt.$1}),
                receipt.$3, 0, receipt.$3, 'Cash', '2026-11-13'],
            );
            await db.customStatement(
              'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
              ['shop', allocationId, receipt.$1, receipt.$2, receipt.$3,
                jsonEncode(receipt.$4)],
            );
          }
        });
        row = (await repo.work(employee: 'chris')).single;
        expect(row['state'], 'In Progress');
        expect(row['paid_minutes'], 540);
        expect(row['estimated_minutes'], 1200);
        expect(row['remaining_minutes'], 660);
        expect(row['can_edit_planned_hours'], isFalse,
          reason: 'Every immutable receipt must permit the correction, not only the first');
        final historyBefore = jsonEncode(await repo.historyWithWork('chris'));
        final coverageBefore = jsonEncode((await db.customSelect(
          "SELECT * FROM regular_payroll_work_coverage WHERE business_id='shop' "
          'AND credit_id=? ORDER BY operation_id',
          variables: [Variable<String>(allocationId)],
        ).get()).map((r) => r.data).toList());
        await expectLater(
          repo.setEstimatedMinutes(taskId, 'chris', 1560), throwsStateError,
        );
        row = (await repo.work(employee: 'chris')).single;
        expect(row['estimated_minutes'], 1200);
        expect(row['paid_minutes'], 540);
        expect(jsonEncode(await repo.historyWithWork('chris')), historyBefore);
        final coverageAfter = jsonEncode((await db.customSelect(
          "SELECT * FROM regular_payroll_work_coverage WHERE business_id='shop' "
          'AND credit_id=? ORDER BY operation_id',
          variables: [Variable<String>(allocationId)],
        ).get()).map((r) => r.data).toList());
        expect(coverageAfter, coverageBefore);
      },
    );
  }
}
