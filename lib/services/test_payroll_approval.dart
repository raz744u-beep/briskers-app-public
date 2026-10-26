/// Pure approval gate for the isolated Tasks TEST payroll ledger.
/// Crediting hours is not authorization to disburse funds.
enum TestPayrollApprovalState { draft, approved, paid }

class TestPayrollApproval {
  const TestPayrollApproval({
    required this.state,
    required this.employeeId,
    required this.weekStart,
    required this.selectedMinutes,
    this.approvedBy,
    this.approvedAt,
  });

  final TestPayrollApprovalState state;
  final String employeeId;
  final DateTime weekStart;
  final int selectedMinutes;
  final String? approvedBy;
  final DateTime? approvedAt;

  TestPayrollApproval approve({
    required String ownerId,
    required DateTime at,
  }) {
    if (state != TestPayrollApprovalState.draft ||
        employeeId.isEmpty || ownerId.trim().isEmpty ||
        selectedMinutes <= 0 || weekStart.weekday != DateTime.monday) {
      throw StateError('Only a valid draft payroll selection can be approved');
    }
    return TestPayrollApproval(
      state: TestPayrollApprovalState.approved,
      employeeId: employeeId,
      weekStart: weekStart,
      selectedMinutes: selectedMinutes,
      approvedBy: ownerId,
      approvedAt: at,
    );
  }

  TestPayrollApproval markPaid() {
    if (state != TestPayrollApprovalState.approved ||
        approvedBy == null || approvedAt == null) {
      throw StateError('Payroll must be approved before payment');
    }
    return TestPayrollApproval(
      state: TestPayrollApprovalState.paid,
      employeeId: employeeId,
      weekStart: weekStart,
      selectedMinutes: selectedMinutes,
      approvedBy: approvedBy,
      approvedAt: approvedAt,
    );
  }
}
