import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/test_payroll_approval.dart';

void main() {
  final monday = DateTime(2026, 10, 19);
  test('approval is explicit and retains approver', () {
    final draft = TestPayrollApproval(
      state: TestPayrollApprovalState.draft, employeeId: 'chris',
      weekStart: monday, selectedMinutes: 240,
    );
    expect(() => draft.markPaid(), throwsStateError);
    final approved = draft.approve(ownerId: 'owner', at: DateTime(2026, 10, 25));
    expect(approved.approvedBy, 'owner');
    expect(approved.markPaid().state, TestPayrollApprovalState.paid);
    expect(() => approved.approve(ownerId: 'owner', at: DateTime.now()),
      throwsStateError);
  });
  test('zero-minute payroll cannot be approved', () {
    final draft = TestPayrollApproval(
      state: TestPayrollApprovalState.draft, employeeId: 'chris',
      weekStart: monday, selectedMinutes: 0,
    );
    expect(() => draft.approve(ownerId: 'owner', at: DateTime.now()),
      throwsStateError);
  });
}
