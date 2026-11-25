import 'dart:convert';

import 'package:briskers_app/core/owner_report_models.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_employee_reports.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a payroll duplicate deletes immediately despite prior sync attempts', () async {
    SharedPreferences.setMockInitialValues({
      'briskers_job_employees_shop': jsonEncode([
        {'id': 'mechanic', 'name': 'Jamie Example', 'nickname': 'Jay'},
        {'id': 'other', 'name': 'Jamie Other'},
      ]),
    });
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final reports = LocalEmployeeReports(database: database);
    final cache = LocalFinancialCache(database: database);
    Map<String, Object> expense(
      String id,
      String name, {
      String category = 'Payroll',
      String date = '2026-10-09',
      int amount = 250,
    }) => {
      'id': id,
      'direction': 'expense',
      'category': category,
      'counterparty': name,
      'transaction_date': date,
      'amount': amount,
    };
    final duplicate = expense('local-transaction-copy', 'Jamie');
    final kept = expense('kept', 'Jamie Example');
    final customer = expense('service', 'Jamie', category: 'Parts');
    await cache.saveTransactions('shop', [
      duplicate,
      kept,
      customer,
      expense('other', 'Jamie Other'),
      expense('different-date', 'Jamie', date: '2026-10-16'),
      expense('different-amount', 'Jamie', amount: 100),
    ]);
    expect(await reports.duplicateGroups('shop', isOwner: true), isEmpty);
    await reports.savePayrollName(
      'shop',
      isOwner: true,
      name: 'Jamie',
      employeeId: 'mechanic',
    );
    final names = await reports.displayNames('shop');
    expect(names.forExpense(duplicate), 'Jamie Example');
    expect(names.forExpense(customer), isNull);
    expect(
      names.forExpense({...duplicate, 'employee_id': 'other'}),
      'Jamie Other',
    );
    final group = (await reports.duplicateGroups('shop', isOwner: true)).single;
    expect(
      group.entries.map((entry) => entry.expense!['id']),
      unorderedEquals(['kept', 'local-transaction-copy']),
    );
    const duplicateId = 'local-transaction-copy';
    await cache.saveTransactionDetail('shop', duplicateId, duplicate);
    for (final (type, id, payload) in [
      ('financial_create', duplicateId, '{}'),
      ('financial_photo', 'photo', jsonEncode({'transaction_id': duplicateId})),
      ('financial_update', 'kept', '{}'),
    ]) {
      await database.customStatement(
        'INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,'
        'payload_json,last_attempt_at,attempt_count) VALUES (?,?,?,?,?,1,2)',
        ['shop', type, id, 'create', payload],
      );
    }
    final writes = OfflineFinancialWriteService(database: database);
    Future<void> removeDuplicate() => writes.deleteDuplicatePayrollExpense(
      'shop',
      duplicateId,
      assertAuthorized: () {},
    );
    await removeDuplicate();
    await removeDuplicate();
    expect(await cache.loadTransactionDetail('shop', duplicateId), isNull);
    await cache.mergeServerTransactions('shop', [duplicate, kept]);
    expect(await reports.duplicateGroups('shop', isOwner: true), isEmpty);
    expect(
      (await cache.loadTransactions('shop')).map((row) => row['id']),
      unorderedEquals([
        'kept',
        'service',
        'other',
        'different-date',
        'different-amount',
      ]),
    );
    final audit = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE name='local_financial_voids'",
    ).get();
    expect(audit, isEmpty);
    final outbox = await database.customSelect(
      'SELECT entity_id FROM sync_outbox',
    ).getSingle();
    expect(outbox.read<String>('entity_id'), 'kept');
  });

  test(
    'reports settlements once and retains dated historical payroll expenses',
    () async {
      SharedPreferences.setMockInitialValues({
        'briskers_job_employees_shop': jsonEncode([
          {'id': 'chris', 'name': 'Chris Current', 'active': true},
          {'id': 'chris-other', 'name': 'Chris Other', 'nickname': 'Chris'},
          {'id': 'chris', 'name': 'Chris Current', 'nickname': 'Chris'},
        ]),
      });
      final database = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await LocalPayrollRepository(
        database,
        business: 'shop',
        owner: true,
      ).prepare();
      await database.customStatement(
        'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          'shop',
          'paid',
          'chris',
          '2026-11-09',
          '{}',
          35000,
          3000,
          32000,
          'Zelle',
          '2026-11-24',
        ],
      );
      await database.customStatement(
        'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          'shop',
          'reversed',
          'chris',
          '2026-11-09',
          '{}',
          10000,
          0,
          10000,
          'Cash',
          '2026-11-24',
        ],
      );
      await database.customStatement(
        'INSERT INTO regular_payroll_reversals_v1 VALUES(?,?,?,?,?)',
        ['shop', 'reversed', 'owner', 'test reversal', '2026-11-25'],
      );
      await LocalFinancialCache(database: database).saveTransactions('shop', [
        {
          'id': 'linked',
          'direction': 'expense',
          'category': 'Payroll',
          'counterparty': 'Chris',
          'amount': 320,
          'transaction_date': '2026-11-24',
          'payroll_operation_id': 'paid',
        },
        {
          'id': 'voided-payroll',
          'direction': 'expense',
          'category': 'Payroll',
          'counterparty': 'Chris',
          'amount': 100,
          'transaction_date': '2026-11-24',
          'payroll_operation_id': 'reversed',
        },
        {
          'id': 'ambiguous',
          'direction': 'expense',
          'category': 'Payroll',
          'counterparty': 'Chris',
          'amount': 80,
          'transaction_date': '2026-11-25',
        },
        {
          'id': 'old-payroll',
          'kind': 'payroll',
          'counterparty': 'Former Mechanic',
          'amount': '-400.00',
          'transaction_date': '2025-02-14',
        },
      ]);
      final reports = LocalEmployeeReports(database: database);
      final weekly = await reports.load(
        'shop',
        ReportPeriod(DateTime(2026, 11, 23), DateTime(2026, 11, 27)),
        isOwner: true,
      );
      final chris = weekly.employees.singleWhere((row) => row.id == 'chris');
      expect(chris.paidCents, 32000);
      expect(chris.payments.single.expense?['id'], 'linked');
      expect(weekly.review.single.expense?['id'], 'ambiguous');
      expect(weekly.years, [2026, 2025]);
      final prior = await reports.load(
        'shop',
        ReportPeriod(DateTime(2025), DateTime(2025, 12, 31)),
        isOwner: true,
      );
      final historical = prior.employees.singleWhere((row) => row.historical);
      expect(historical.name, 'Former Mechanic');
      expect(historical.paidCents, 40000);
      expect(historical.labor, isEmpty);
      await reports.savePayrollName(
        'shop',
        isOwner: true,
        name: '  CHRIS ',
        employeeId: 'chris',
      );
      await reports.savePayrollName(
        'shop',
        isOwner: true,
        name: 'Former  Mechanic',
        employeeId: 'chris',
      );
      final linkedWeek = await reports.load(
        'shop',
        ReportPeriod(DateTime(2026, 11, 23), DateTime(2026, 11, 27)),
        isOwner: true,
      );
      expect(linkedWeek.payrollNames, hasLength(2));
      expect(linkedWeek.review, isEmpty);
      expect(
        linkedWeek.employees.singleWhere((row) => row.id == 'chris').paidCents,
        40000,
      );
      final linkedPrior = await reports.load(
        'shop',
        ReportPeriod(DateTime(2025), DateTime(2025, 12, 31)),
        isOwner: true,
      );
      expect(linkedPrior.employees.where((row) => row.historical), isEmpty);
      final merged = linkedPrior.employees.singleWhere(
        (row) => row.id == 'chris',
      );
      expect(merged.paidCents, 40000);
      expect(
        merged.payments.single.expense?['counterparty'],
        'Former Mechanic',
      );
      expect(merged.labor, isEmpty);
      await reports.removePayrollName(
        'shop',
        isOwner: true,
        name: 'former mechanic',
      );
      final restored = await reports.load(
        'shop',
        ReportPeriod(DateTime(2025), DateTime(2025, 12, 31)),
        isOwner: true,
      );
      expect(
        restored.employees.singleWhere((row) => row.historical).paidCents,
        40000,
      );
      expect(
        await database.customSelect('SELECT * FROM sync_outbox').get(),
        isEmpty,
      );
      await expectLater(
        reports.load(
          'shop',
          ReportPeriod(DateTime(2025), DateTime(2026)),
          isOwner: false,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'reports completed work and partial pay coverage from saved labor',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await LocalPayrollRepository(
        database,
        business: 'shop',
        owner: true,
      ).prepare();
      await database.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,?)',
        ['shop', 'employee', 'Mechanic', 4000, 0],
      );
      await database.customStatement(
        'INSERT INTO regular_payroll_tasks VALUES(?,?,?,?,?,?)',
        ['shop', 'task', 'job', 'line', 'Oil leak repair', 720],
      );
      await database.customStatement(
        'INSERT INTO regular_payroll_portions VALUES(?,?,?,?,?,?,?)',
        ['shop', 'portion', 'task', 'employee', 'Done', 1, '2026-11-24'],
      );
      await database.customStatement(
        'INSERT INTO local_mechanic_work_credits_v1 '
        '(business_id,allocation_id,job_id,labor_line_id,task_id,employee_id,'
        'actual_minutes,rate_cents,completed,paid_operation_id,revision) '
        'VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          'shop',
          'portion',
          'job',
          'line',
          'task',
          'employee',
          720,
          4000,
          1,
          null,
          1,
        ],
      );
      await database.customStatement(
        'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
        ['shop', 'portion', 'payment', 480, 32000, '{}'],
      );
      final data = await LocalEmployeeReports(database: database).load(
        'shop',
        ReportPeriod(DateTime(2026, 11, 23), DateTime(2026, 11, 27)),
        isOwner: true,
      );
      final person = data.employees.single;
      expect((person.completed, person.paid, person.unpaid), (720, 480, 240));
      expect(person.labor.single.description, 'Oil leak repair');
      expect(person.paidCents, 0);
    },
  );
}
