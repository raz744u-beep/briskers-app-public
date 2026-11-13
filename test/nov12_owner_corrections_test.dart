import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/nov12_job_completion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late BriskersLocalDatabase db;
  late LocalPayrollRepository repo;
  void repository() => repo = LocalPayrollRepository(
    db,
    business: 'shop',
    owner: true,
    deviceId: 'owner-device',
    assertLanWriter: () async {},
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folder = await Directory.systemTemp.createTemp('nov12-preservation');
    db = BriskersLocalDatabase(
      NativeDatabase(File('${folder.path}/shop.sqlite')),
    );
    repository();
    await LocalDocumentDetailCache.initialize(db);
    await repo.prepare();
    await repo.bindPaymentAuthority(
      writerDeviceId: 'owner-device',
      assertVerifiedPairing: () {},
    );
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_name) VALUES('gloria','shop','owner','Oil Separator','open','J-40','Gloria Johnson')",
    );
    await db.customStatement(
      "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) VALUES('a','shop','gloria','chris','Chris')",
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,kind,document_number,document_date) VALUES('invoice','shop','gloria','invoice','6359','2026-11-02')",
    );
    await LocalDocumentDetailCache(database: db).save('shop', 'invoice', {
      'id': 'invoice',
      'job_id': 'gloria',
      'kind': 'invoice',
      'status': 'issued',
      'total_amount': 7882.11,
      'paid_amount': 7882.11,
      'pending_payment': 0,
      'payments': [
        {'id': 'original-3000', 'amount': 3000, 'state': 'posted'},
        {'id': 'original-4882', 'amount': 4882.11, 'state': 'posted'},
      ],
      'lines': [
        {
          'id': 'original-labor',
          'line_kind': 'labor',
          'description': 'Replace oil separator, thermostat and crossover pipe',
          'quantity': 10,
        },
      ],
    });
    await repo.registerAssignedLabor(
      jobId: 'gloria',
      invoiceId: 'invoice',
      lineId: 'original-labor',
      employeeId: 'chris',
      employeeName: 'Chris',
      rateCents: 0,
    );
  });
  tearDown(() async {
    await db.close();
    await folder.delete(recursive: true);
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
  });
  Future<void> rework(String operation) => repo.createRecheck(
    operation: operation,
    job: 'gloria',
    description: 'Oil Separator',
    employee: 'chris',
    name: 'Chris',
    rate: 0,
    estimatedMinutes: 600,
  );
  Future<String> financial() async => jsonEncode(
    await LocalDocumentDetailCache(
      database: db,
    ).loadReadOnly('shop', 'invoice'),
  );
  test(
    'exact unpaid warranty allocation carries once, survives restart and pays exactly 400 without altering customer records',
    () async {
      final before = await financial();
      final originalId = (await repo.work()).single['id'];
      await rework('new-warranty');
      await repo.localCompensation([]);
      expect((await repo.employees()).single['rate'], 4000);
      expect(await repo.applyNov12OilSeparatorCarry(), isNull);
      var work = (await repo.work()).singleWhere(
        (r) => r['description'] == 'Oil Separator',
      );
      final stableId = work['id'];
      expect(work['actual_minutes'], 600);
      expect(work['state'], 'Done');
      expect(work['carry_week'], '2026-11-09');
      expect(work['payment_rate_cents'], 4000);
      final original = (await repo.work()).singleWhere(
        (r) => r['id'] == originalId,
      );
      expect(original['actual_minutes'], 0);
      expect(original['archived_labor'], 1);
      expect(original['carry_week'], isNull);
      await repo.savePayrollDraft('chris', '2026-11-09', {
        stableId as String: 10,
      });
      await db.close();
      db = BriskersLocalDatabase(
        NativeDatabase(File('${folder.path}/shop.sqlite')),
      );
      repository();
      expect(await repo.applyNov12OilSeparatorCarry(), isNull);
      expect(await repo.payrollDraft('chris', '2026-11-09'), {stableId: 10.0});
      work = (await repo.work()).singleWhere((r) => r['id'] == stableId);
      Future<bool> pay(String operation, {String week = '2026-11-09'}) =>
          repo.verify(
            operation: operation,
            employee: 'chris',
            week: week,
            date: '2026-11-13',
            method: 'Cash',
            selected: [work],
            base: 0,
            hourlyAdjustment: 0,
            adjustmentReason:
                'Owner authorized warranty carry and saved compensation',
            repayment: 0,
            confirmedNet: 40000,
          );
      await expectLater(
        pay('before-week', week: '2026-11-02'),
        throwsStateError,
      );
      expect(await pay('warranty-payment'), isTrue);
      expect(await pay('warranty-payment'), isFalse);
      await expectLater(pay('duplicate-payment'), throwsStateError);
      expect(await repo.applyNov12OilSeparatorCarry(), isNull);
      expect((await repo.history('chris')).single['net'], 40000);
      expect(
        await db
            .customSelect('SELECT * FROM regular_payroll_carry_weeks_v1')
            .get(),
        hasLength(1),
      );
      expect(
        (await repo.work()).where((r) => r['description'] == 'Oil Separator'),
        hasLength(1),
      );
      expect(await financial(), before);
    },
  );
  test(
    'ambiguous warranty work remains untouched and requests review',
    () async {
      await rework('first');
      await rework('second');
      await repo.localCompensation([]);
      final before = jsonEncode(await repo.work());
      expect(
        await repo.applyNov12OilSeparatorCarry(),
        contains('more than one'),
      );
      expect(jsonEncode(await repo.work()), before);
      expect(
        await db
            .customSelect('SELECT * FROM regular_payroll_carry_weeks_v1')
            .get(),
        isEmpty,
      );
    },
  );
  test(
    'saved compensation survives zero-rate task creation and other pay arrangements',
    () async {
      await repo.saveEmployeeCompensation(
        employee: 'chris',
        name: 'Chris',
        rate: 4500,
        weeklyBase: false,
      );
      await repo.saveLocalPayBasis(
        employee: 'secretary',
        name: 'Secretary',
        paymentType: 'fixed_weekly',
        amountCents: 80000,
      );
      await repo.saveEmployeeCompensation(
        employee: 'adam',
        name: 'Adam',
        rate: 0,
        weeklyBase: true,
      );
      await rework('new');
      final rows = await repo.localCompensation([
        {'id': 'kam', 'name': 'Kam'},
        {'id': 'unknown', 'name': 'New Employee'},
      ]);
      expect(rows.singleWhere((r) => r['id'] == 'chris')['rate'], 4500);
      expect(rows.singleWhere((r) => r['id'] == 'kam')['rate'], 3500);
      expect(rows.singleWhere((r) => r['id'] == 'unknown')['rate'], isNull);
      expect(rows.singleWhere((r) => r['id'] == 'adam')['base_enabled'], 1);
      expect(
        rows.singleWhere((r) => r['id'] == 'secretary')['weekly_rate'],
        800,
      );
      expect(
        await repo.applyNov12OilSeparatorCarry(),
        contains('needs review'),
      );
    },
  );
  test(
    'Owner-confirmed completion uses local financial evidence once and keeps payment identities',
    () async {
      final before = await financial();
      await Nov12JobCompletion(db).reconcile('shop', isOwner: false);
      expect(
        (await db
                .customSelect("SELECT status FROM local_jobs WHERE id='gloria'")
                .get())
            .single
            .data['status'],
        'open',
      );
      await Nov12JobCompletion(db).reconcile('shop', isOwner: true);
      await Nov12JobCompletion(db).reconcile('shop', isOwner: true);
      expect(
        (await db
                .customSelect("SELECT status FROM local_jobs WHERE id='gloria'")
                .get())
            .single
            .data['status'],
        'completed',
      );
      expect(
        await db
            .customSelect('SELECT * FROM owner_nov12_job_completion_v1')
            .get(),
        hasLength(1),
      );
      expect(await financial(), before);
      await db.close();
      db = BriskersLocalDatabase(
        NativeDatabase(File('${folder.path}/shop.sqlite')),
      );
      repository();
      await Nov12JobCompletion(db).reconcile('shop', isOwner: true);
      expect(
        (await db
                .customSelect("SELECT status FROM local_jobs WHERE id='gloria'")
                .get())
            .single
            .data['status'],
        'completed',
      );
      expect(await financial(), before);
    },
  );
}
