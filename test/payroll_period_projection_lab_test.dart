import 'package:briskers_app/tasks_lab/payroll_period_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final drafts=<Map<String,dynamic>>[
    {'employee_id':'chris','week_key':'2026-10-26',
      'selected_json':'{"J24:A":2.0}','override_cents':null},
  ];
  final payments=<Map<String,dynamic>>[
    {'employee_id':'chris','kind':'pay','cents':2000,
      'paid_at':DateTime(2026,10,26).millisecondsSinceEpoch},
  ];
  final linked=<Map<String,dynamic>>[
    {'employee_id':'chris','week_key':'2026-10-26','hours':0.5},
  ];

  test('Unfinished assigned work is not automatically owed',(){
    final p=LabPayrollPeriodProjection.calculate(
      employeeId:'chris',from:DateTime(2026,10,26),
      until:DateTime(2026,11,2),hourlyRateCents:4000,
      drafts:drafts,payments:payments,taskPayments:linked);
    expect(p.hours,0.5);
    expect(p.grossCents,2000);
    expect(p.paidCents,2000);
    expect(p.balanceCents,0);
  });

  test('Draft allocations with no confirmed payments stay unknown',(){
    final p=LabPayrollPeriodProjection.calculate(
      employeeId:'chris',from:DateTime(2026,10,26),
      until:DateTime(2026,11,2),hourlyRateCents:4000,
      drafts:drafts,payments:const [],taskPayments:const []);
    expect(p.hours,isNull);
    expect(p.grossCents,isNull);
    expect(p.balanceCents,isNull);
  });

  test('Verified gross includes rounding without changing paid hours',(){
    final p=LabPayrollPeriodProjection.calculate(
      employeeId:'chris',from:DateTime(2026,10,26),
      until:DateTime(2026,11,2),hourlyRateCents:4000,
      drafts:drafts,
      payments:[{'employee_id':'chris','kind':'pay','cents':58000,
        'paid_at':DateTime(2026,10,26).millisecondsSinceEpoch}],
      taskPayments:[{'employee_id':'chris','week_key':'2026-10-26',
        'hours':14.375}],
      settlements:[{'employee_id':'chris','week_key':'2026-10-26',
        'gross_cents':58000,'debt_cents':10000,'net_cents':48000}]);
    expect(p.hours,14.375);
    expect(p.grossCents,58000);
    expect(p.paidCents,58000);
    expect(p.balanceCents,0);
  });

  test('No task-linked credits means no invented gross even if paid',(){
    final p=LabPayrollPeriodProjection.calculate(
      employeeId:'chris',from:DateTime(2026,10,19),
      until:DateTime(2026,10,26),hourlyRateCents:4000,
      drafts:drafts,payments:payments,taskPayments:linked);
    expect(p.hours,isNull);
    expect(p.grossCents,isNull);
    expect(p.balanceCents,isNull);
    expect(p.paidCents,0);
  });
}
