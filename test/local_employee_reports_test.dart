import 'dart:convert';

import 'package:briskers_app/core/owner_report_models.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_employee_reports.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('reports completed work and partial pay coverage from saved labor', () async {
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
      'INSERT INTO local_mechanic_work_credits_v1 VALUES(?,?,?,?,?,?,?,?,?,?)',
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
  });
}
