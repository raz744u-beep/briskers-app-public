/// Pure cents-based weekly payroll preview. No ledger or network writes.
/// Persistence, authorization, and atomic Verify Payment remain separate.
class ShopPayrollAllocation {
  const ShopPayrollAllocation({
    required this.id,
    required this.employeeId,
    required this.hoursHundredths,
    required this.rateCentsPerHour,
    required this.completed,
    required this.alreadyPaid,
  });

  final String id;
  final String employeeId;
  final int hoursHundredths;
  final int rateCentsPerHour;
  final bool completed;
  final bool alreadyPaid;

  int get grossCents {
    if (hoursHundredths < 0 || rateCentsPerHour < 0) {
      throw ArgumentError('Negative hours or rate');
    }
    // Half-up integer rounding from hundredths of an hour.
    return (hoursHundredths * rateCentsPerHour + 50) ~/ 100;
  }
}

class ShopPayrollPreview {
  const ShopPayrollPreview._();

  /// Fail closed: invalid, duplicate, incomplete, or already-paid allocations
  /// must not appear in a proposed payment.
  static int grossCents({
    required bool owner,
    required String employeeId,
    required Iterable<ShopPayrollAllocation> selected,
  }) {
    if (!owner || employeeId.trim().isEmpty) {
      throw StateError('Owner and employee required');
    }
    final ids = <String>{};
    var total = 0;
    for (final item in selected) {
      if (item.id.trim().isEmpty ||
          !ids.add(item.id) ||
          item.employeeId != employeeId ||
          !item.completed ||
          item.alreadyPaid) {
        throw StateError('Invalid payroll selection');
      }
      total += item.grossCents;
    }
    return total;
  }

  /// A preview is not a payment receipt. Verify Payment must explicitly
  /// specify the payment method and confirm against authoritative state.
  static bool canVerifyPayment({
    required bool owner,
    required bool hasSelectedWork,
    required bool localAllocationsCurrent,
    required bool methodSelected,
    required bool alreadyCommitted,
  }) => owner &&
      hasSelectedWork &&
      localAllocationsCurrent &&
      methodSelected &&
      !alreadyCommitted;

  /// A payroll deduction never changes gross taxable work credit.
  /// A deduction above gross is rejected rather than generating negative pay.
  static int netCents({
    required int grossCents,
    required int repaymentCents,
  }) {
    if (grossCents < 0 || repaymentCents < 0 || repaymentCents > grossCents) {
      throw ArgumentError('Invalid payroll deduction');
    }
    return grossCents - repaymentCents;
  }
}
