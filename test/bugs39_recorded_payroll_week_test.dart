import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/recorded_payroll_week.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> portion(String id, int minutes, int cents) => {
  'credit_id': id,
  'id': id,
  'task_id': 'task-$id',
  'job_id': 'job-40',
  'job_number': 'J-40',
  'description': 'Oil Separator',
  'actual_minutes': minutes,
  'gross_cents': cents,
  'estimated_minutes': 1200,
  'total_credit_minutes': 1200,
  'rate_cents': 9000,
};
Map<String, dynamic> receipt(
  String id,
  String week,
  int minutes,
  int labor, {
  int adjustment = 0,
  int base = 0,
  int repayment = 0,
  String employee = 'chris',
}) => {
  'business_id': 'shop',
  'employee_id': employee,
  'operation_id': id,
  'week': week,
  'gross': labor + base + adjustment,
  'repayment': repayment,
  'net': labor + base + adjustment - repayment,
  'original_net': labor + base + adjustment - repayment,
  'amount_revision': 0,
  'method': 'Cash',
  'verified_date': '2026-11-14',
  'payload': jsonEncode({'base': base, 'adjustment': adjustment}),
  'work': [if (minutes > 0) portion('same-credit', minutes, labor)],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final week = DateTime(2026, 11, 9);
  RecordedPayrollWeek selected(List<Map<String, dynamic>> rows) =>
      RecordedPayrollWeek.fromHistory(rows, employeeId: 'chris', week: week);

  test('selected payroll week uses recorded payments, not payout date or current rate', () {
    final first = receipt(
      'first',
      '2026-11-09',
      480,
      32000,
      adjustment: -200,
      repayment: 800,
    );
    final second = {
      ...receipt('second', '2026-11-09', 120, 8000, adjustment: 100),
      'verified_date': '2026-11-16',
    };
    final rows = [
      first,
      second,
      receipt('next', '2026-11-16', 600, 40000),
      receipt('other', '2026-11-09', 600, 40000, employee: 'kam'),
    ];
    final before = jsonEncode(rows), sum = selected(rows);
    expect(sum.payments, hasLength(2));
    expect(sum.paidMinutes, 600);
    expect(sum.laborCents, 40000);
    expect(sum.baseCents, 0);
    expect(sum.adjustmentCents, -100);
    expect(sum.grossCents, 39900);
    expect(sum.repaymentCents, 800);
    expect(sum.netCents, 39100);
    expect(sum.work, hasLength(2)); // Two paid portions of the same assignment.
    expect(jsonEncode(rows), before);
  });

  test('retries count once; latest saved amount correction and reversals are respected', () {
    final first = receipt(
      'first',
      '2026-11-09',
      480,
      32000,
      adjustment: -200,
      repayment: 800,
    );
    final corrected = {
      ...first,
      'amount_revision': 1,
      'gross': 30800,
      'net': 30000,
    };
    final sum = selected([first, Map<String, dynamic>.from(first), corrected]);
    expect(sum.payments, hasLength(1));
    expect(sum.paidMinutes, 480);
    expect(sum.laborCents, 32000);
    expect(sum.adjustmentCents, -1200);
    expect(sum.grossCents, 30800);
    expect(sum.netCents, 30000);
    expect(
      selected([
        corrected,
        {...first, 'reversed_at': '2026-11-17'},
      ]).hasPayments,
      isFalse,
    );
  });

  test('base-only and zero-net payments are real records; missing detail is not a zero payout', () {
    final base = selected([
      receipt('base', '2026-11-09', 0, 0, base: 80000, repayment: 10000),
    ]);
    expect(base.paidMinutes, 0);
    expect(base.baseCents, 80000);
    expect(base.netCents, 70000);
    final zero = selected([
      receipt('zero', '2026-11-09', 60, 4000, repayment: 4000),
    ]);
    expect(zero.hasPayments, isTrue);
    expect(zero.netCents, 0);
    expect(zero.grossCents, 4000);
    final legacy = selected([
      {
        'operation_id': 'legacy',
        'week': '2026-11-09',
        'net': 12345,
        'gross': 12345,
        'repayment': 0,
      },
    ]);
    expect(legacy.netCents, 12345);
    expect(legacy.paidMinutes, isNull);
    expect(legacy.baseCents, isNull);
    expect(legacy.adjustmentCents, isNull);
    final empty = selected([]);
    expect(empty.hasPayments, isFalse);
    expect(empty.netCents, 0);
  });

  test('paid work detail and summary share stable recorded task portions', () {
    final payment = receipt('one', '2026-11-09', 480, 32000);
    payment['work'] = [
      portion('same-credit', 480, 32000),
      portion('same-credit', 480, 32000),
    ];
    final sum = selected([payment]);
    expect(sum.work, hasLength(1));
    expect(sum.paidMinutes, 480);
    expect(sum.laborCents, 32000);
    expect(sum.work.single['method'], 'Cash');
    expect(sum.work.single['verified_date'], '2026-11-14');
  });

  test('saved SQLite history survives restart and employee-rate changes without changing payments', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('recorded-week');
    final file = File('${directory.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    var repository = LocalPayrollRepository(db, business: 'shop', owner: true);
    try {
      await repository.prepare();
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) VALUES('job-40','shop','owner','Saved repair','completed','J-40')",
      );
      final payment = receipt(
        'original',
        '2026-11-09',
        480,
        32000,
        adjustment: -200,
        repayment: 800,
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          'shop',
          'original',
          'chris',
          '2026-11-09',
          payment['payload'],
          payment['gross'],
          payment['repayment'],
          payment['net'],
          'Cash',
          '2026-11-14',
        ],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
        [
          'shop',
          'same-credit',
          'original',
          480,
          32000,
          jsonEncode(portion('same-credit', 1200, 90000)),
        ],
      );
      Future<String> ledger() async => jsonEncode([
        for (final table in [
          'regular_payroll_payments',
          'regular_payroll_work_coverage',
        ])
          (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
              .map((r) => r.data)
              .toList(),
      ]);
      final before = await ledger();
      final original = selected(await repository.historyWithWork('chris'));
      expect(original.netCents, 31000);
      expect(original.paidMinutes, 480);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      repository = LocalPayrollRepository(db, business: 'shop', owner: true);
      await repository.saveEmployeeCompensation(
        employee: 'chris',
        name: 'Chris',
        rate: 9000,
        weeklyBase: false,
      );
      final restored = selected(await repository.historyWithWork('chris'));
      expect(restored.netCents, 31000);
      expect(restored.laborCents, 32000);
      expect(restored.paidMinutes, 480);
      expect(await ledger(), before);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
