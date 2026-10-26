import 'package:briskers_app/tasks_lab/payroll_period_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final drafts = <Map<String, dynamic>>[
    {'employee_id':'chris','week_key':'2026-10-26',
      'selected_json':'{"J24:work":2.0}', 'override_cents':null},
    {'employee_id':'chris','week_key':'2026-10-19',
      'selected_json':'{"J23:work":1.5}', 'override_cents':null},
  ];
  final payments = <Map<String, dynamic>>[
    {'employee_id':'chris','kind':'pay','cents':4000,
      'paid_at':DateTime(2026,10,26).millisecondsSinceEpoch},
    {'employee_id':'chris','kind':'pay','cents':2000,
      'paid_at':DateTime(2026,10,20).millisecondsSinceEpoch},
    {'employee_id':'chris','kind':'advance','cents':9900,
      'paid_at':DateTime(2026,10,27).millisecondsSinceEpoch},
    {'employee_id':'kam','kind':'pay','cents':5000,
      'paid_at':DateTime(2026,10,27).millisecondsSinceEpoch},
  ];
  final taskPayments = <Map<String, dynamic>>[
    {'employee_id':'chris','week_key':'2026-10-26','hours':1.0},
  ];

  test('Payroll period prevents duplicate hours from task + draft overlap', () {
    final week = LabPayrollPeriodProjection.calculate(
      employeeId:'chris',
      from:DateTime(2026,10,26),until:DateTime(2026,11,2),
      hourlyRateCents:4000,drafts:drafts,payments:payments,
      taskPayments:taskPayments);
    expect(week.hours,2.0);
    expect(week.grossCents,8000);
    expect(week.paidCents,4000);
    expect(week.balanceCents,4000);
  });

  test('Last Week and All Time are filtered and accumulated separately', () {
    final last = LabPayrollPeriodProjection.calculate(
      employeeId:'chris',from:DateTime(2026,10,19),
      until:DateTime(2026,10,26),hourlyRateCents:4000,
      drafts:drafts,payments:payments,taskPayments:taskPayments);
    expect(last.hours,1.5);
    expect(last.grossCents,6000);
    expect(last.paidCents,2000);
    expect(last.balanceCents,4000);
    final all = LabPayrollPeriodProjection.calculate(
      employeeId:'chris',from:DateTime(2000),until:DateTime(2100),
      hourlyRateCents:4000,drafts:drafts,
      payments:payments,taskPayments:taskPayments);
    expect(all.hours,3.5);
    expect(all.grossCents,14000);
    expect(all.paidCents,6000);
    expect(all.balanceCents,8000);
  });

  test('Custom period with no work does not invent gross or earnings', () {
    final zero = LabPayrollPeriodProjection.calculate(
      employeeId:'chris',from:DateTime(2026,1,1),
      until:DateTime(2026,1,30),hourlyRateCents:4000,
      drafts:drafts,payments:payments,taskPayments:taskPayments);
    expect(zero.hours,isNull);
    expect(zero.grossCents,isNull);
    expect(zero.balanceCents,isNull);
    expect(zero.paidCents,0);
  });

  test('Verified task hours without drafts still inform the period summary', () {
    final tasks = [
      {'employee_id':'kam','week_key':'2026-10-26','hours':0.5},
      {'employee_id':'kam','week_key':'2026-10-26','hours':0.5},
    ];
    final projection = LabPayrollPeriodProjection.calculate(
      employeeId:'kam',from:DateTime(2026,10,26),
      until:DateTime(2026,11,2),hourlyRateCents:3500,
      drafts:const [],payments:const [],taskPayments:tasks);
    expect(projection.hours,1.0);
    expect(projection.grossCents,3500);
    expect(projection.balanceCents,3500);
  });
}
