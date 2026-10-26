/// Integer-cent TEST payroll reconciliation; selected/credited hours are not
/// themselves proof of a payment. Do not infer cash paid from task status.
class TestPayrollBalance {
  const TestPayrollBalance._();

  static int remainingCents({
    required int earnedCents,
    required int adjustmentCents,
    required int paidCents,
  }) {
    if (earnedCents < 0 || paidCents < 0) {
      throw ArgumentError('Earned and paid totals cannot be negative');
    }
    final total = earnedCents + adjustmentCents - paidCents;
    if (total.abs() > 100000000000) {
      throw StateError('Payroll balance outside supported range');
    }
    return total;
  }
}
