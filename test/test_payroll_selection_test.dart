import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/test_payroll_selection.dart';

void main() {
  const work = TestPayrollWork(
    taskKey: 'invoice-1:line-2', employeeId: 'chris',
    creditedMinutes: 240, previouslyPaidMinutes: 60,
  );
  test('partially pay open work and carry remaining allocation', () {
    expect(TestPayrollSelection.selectMinutes(
      available: [work],
      requestedMinutesByTask: {'chris|invoice-1:line-2': 90},
    ), {'chris|invoice-1:line-2': 90});
    expect(work.unpaidMinutes, 180);
  });
  test('cannot pay the same time twice or overpay', () {
    expect(() => TestPayrollSelection.selectMinutes(
      available: [work],
      requestedMinutesByTask: {'chris|invoice-1:line-2': 181},
    ), throwsStateError);
    expect(() => TestPayrollSelection.selectMinutes(
      available: [work, work], requestedMinutesByTask: {},
    ), throwsStateError);
  });
  test('different mechanics on same task are separate allocations', () {
    const kam = TestPayrollWork(taskKey: 'invoice-1:line-2',
      employeeId: 'kam', creditedMinutes: 120, previouslyPaidMinutes: 0);
    expect(TestPayrollSelection.selectMinutes(
      available: [work, kam],
      requestedMinutesByTask: {
        'chris|invoice-1:line-2': 180,
        'kam|invoice-1:line-2': 120,
      },
    ).length, 2);
  });
}
