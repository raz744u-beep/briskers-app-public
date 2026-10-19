import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/task_payroll_foundation.dart';

void main() {
  test('nickname prefers explicit value and falls back to first name', () {
    expect(EmployeeNickname.display(fullName: 'Kamerron Smith', nickname: ' Kam '), 'Kam');
    expect(EmployeeNickname.display(fullName: 'Chris Rideaux'), 'Chris');
  });

  test('job compact label counts additional unique mechanics', () {
    expect(EmployeeNickname.jobSummary(leadName: 'Kamerron Smith', leadNickname: 'Kam',
      additionalEmployeeIds: ['chris-id', 'chris-id']), 'Kam +1');
  });

  test('independent payroll hours do not alter customer hours', () {
    const hours = LaborHours(billedHours: 3, payrollHours: 3);
    expect(hours.withChangedPayroll(4).billedHours, 3);
    expect(hours.withChangedBilling(2).payrollHours, 3);
  });

  test('stable import link prevents document-number-based duplication', () {
    const link = TaskDocumentLink(taskId: 'task-1', jobId: 'job-12',
      sourceLineId: 'line-8', sourceKind: 'estimate');
    expect(link.importKey, 'job-12:estimate:line-8');
  });

  test('service catalog defaults can be overridden per item', () {
    expect(ServiceLaborDefaults.defaultFor('Service A'), 1);
    expect(ServiceLaborDefaults.defaultFor('Service B'), 3);
    expect(ServiceLaborDefaults.defaultFor('Service B', catalogHours: 3.5), 3.5);
  });
}
