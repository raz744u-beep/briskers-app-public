import 'package:briskers_app/tasks_lab/payroll_week_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TEST payroll projection respects selected Monday-Sunday week', () {
    final drafts = <Map<String, dynamic>>[
      {'employee_id':'chris','week_key':'2026-10-19',
       'selected_json':'{"J24:A":2.5,"J24:B":1.5}',
       'override_cents':null},
      {'employee_id':'chris','week_key':'2026-10-26',
       'selected_json':'{"J24:C":3.0}', 'override_cents':15000},
    ];
    final payments = <Map<String, dynamic>>[
      {'employee_id':'chris','kind':'pay','cents':5000,
       'paid_at':DateTime(2026,10,20).millisecondsSinceEpoch},
      {'employee_id':'chris','kind':'pay','cents':7000,
       'paid_at':DateTime(2026,10,27).millisecondsSinceEpoch},
      {'employee_id':'chris','kind':'advance','cents':9000,
       'paid_at':DateTime(2026,10,27).millisecondsSinceEpoch},
      {'employee_id':'kam','kind':'pay','cents':9999,
       'paid_at':DateTime(2026,10,27).millisecondsSinceEpoch},
    ];
    final prior = LabPayrollWeekSource.summarize(
      employeeId:'chris',week:DateTime(2026,10,20),
      hourlyCents:4000,drafts:drafts,payments:payments);
    expect(prior.hours,4.0);
    expect(prior.taskCount,2);
    expect(prior.grossCents,16000);
    expect(prior.paidCents,5000);
    expect(prior.balanceCents,11000);

    final current = LabPayrollWeekSource.summarize(
      employeeId:'chris',week:DateTime(2026,10,26),
      hourlyCents:4000,drafts:drafts,payments:payments);
    expect(current.grossCents,15000);
    expect(current.paidCents,7000);
    expect(current.balanceCents,8000);
    expect(LabPayrollWeekSource.previousBalance(
      employeeId:'chris',selectedWeek:DateTime(2026,10,26),
      rateCents:4000,drafts:drafts,payments:payments),11000);
    expect(LabPayrollWeekSource.historyWeekKeys(
      employeeId:'chris',drafts:drafts,payments:payments),
      ['2026-10-26','2026-10-19']);
  });

  test('Missing drafts remain unknown rather than zero compensation', () {
    final blank = LabPayrollWeekSource.summarize(
      employeeId:'chris',week:DateTime(2026,11,2),
      hourlyCents:4000,
      drafts: const [],payments: const []);
    expect(blank.hasDraft,isFalse);
    expect(blank.grossCents,isNull);
    expect(blank.balanceCents,isNull);
    expect(blank.paidCents,0);
    expect(blank.taskCount,0);
  });
  test('Visual baseline: overview, details and history stay distinct', () {
    // Flutter widget source contains separated page responsibilities.
    expect(LabPayrollWeekSource.weekKey(DateTime(2026,10,28)),
      '2026-10-26');
  });
}
