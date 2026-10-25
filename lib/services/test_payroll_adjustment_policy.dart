/// Isolated payroll adjustment contract. A bonus or adjustment is a distinct,
/// auditable entry, never a silent alteration of credited task hours.
enum TestPayrollAdjustmentKind { bonus, correction }

class TestPayrollAdjustmentPolicy {
  const TestPayrollAdjustmentPolicy._();

  static void validate({
    required TestPayrollAdjustmentKind kind,
    required int signedCents,
    required String reason,
    required String approvedBy,
  }) {
    if (signedCents == 0 || signedCents.abs() > 100000000) {
      throw ArgumentError('Adjustment must be nonzero and bounded');
    }
    if (kind == TestPayrollAdjustmentKind.bonus && signedCents < 0) {
      throw ArgumentError('A bonus cannot be negative');
    }
    if (reason.trim().isEmpty || approvedBy.trim().isEmpty) {
      throw StateError('Adjustment reason and approver required');
    }
  }
}
