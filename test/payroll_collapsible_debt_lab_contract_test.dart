import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Payroll Tasks are compact and expandable without extra navigation',(){
    final tasks=File('lib/tasks_lab/weekly_labor_review_screen.dart')
      .readAsStringSync();
    expect(tasks,contains('final Set<String> _expandedTasks'));
    expect(tasks,contains('if(_expandedTasks.contains(_id(task)))'));
    expect(tasks,contains("'Customer billed'"));
    expect(tasks,contains("'Mechanic assigned'"));
    expect(tasks,contains("'Previously paid'"));
    expect(tasks,contains("'Remaining to pay'"));
    expect(tasks,contains('onAssignedHoursChange'));
    expect(tasks,contains('selectUnpaidByDefault:false'));
    expect(tasks,contains('Verify Payment'));
  });

  test('Verified pay has atomic linked gross/debt/net records',(){
    final service=File('lib/tasks_lab/lab_payroll_payment_service.dart')
      .readAsStringSync();
    expect(service,contains('await localDatabase.transaction(() async'));
    expect(service,contains('lab_payroll_settlements'));
    expect(service,contains('lab_employee_advance_repayments'));
    expect(service,contains('Payroll deduction'));
    expect(service,contains('grossCents-debtCents'));
    expect(service,contains('lab_payroll_task_payments'));
    expect(service,contains('Task paid hours changed'));
  });

  test('Numeric input and Reports filter are consistent',(){
    final tasks=File('lib/tasks_lab/weekly_labor_review_screen.dart')
      .readAsStringSync();
    expect(tasks,contains('baseOffset:0,extentOffset:amount.text.length'));
    expect(tasks,contains('baseOffset:0,extentOffset:debtInput.text.length'));
    expect(tasks,contains('baseOffset:0,extentOffset:payInput.text.length'));
    final reports=File('lib/tasks_lab/payroll_history_panel.dart')
      .readAsStringSync();
    expect(reports,contains('reports-period-'));
    expect(reports,contains('borderRadius:BorderRadius.circular(14)'));
    expect(reports,contains('SafeArea(top:false'));
  });
}
