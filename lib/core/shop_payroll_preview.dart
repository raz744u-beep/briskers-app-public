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

  /// A repayment is applied only during explicit verification. The amount
  /// must not exceed either the gross payroll or the employee's outstanding
  /// advance balance. The preview never mutates that balance.
  static int verifiedRepaymentCents({
    required int grossCents,
    required int outstandingAdvanceCents,
    required int requestedRepaymentCents,
  }) {
    if (grossCents < 0 ||
        outstandingAdvanceCents < 0 ||
        requestedRepaymentCents < 0 ||
        requestedRepaymentCents > grossCents ||
        requestedRepaymentCents > outstandingAdvanceCents) {
      throw ArgumentError('Invalid repayment against outstanding advance');
    }
    return requestedRepaymentCents;
  }

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

/// Immutable local Verify Payment proposal; not a posted payment.
/// A repository transaction must atomically persist the operation ID, credits,
/// repayment and paid-work ledger before the UI may show Paid.
class ShopPayrollPaymentProposal {
  ShopPayrollPaymentProposal({
    required this.operationId,
    required this.employeeId,
    required List<String> allocationIds,
    required this.grossCents,
    required this.repaymentCents,
    required this.method,
  }) : allocationIds = List<String>.unmodifiable(allocationIds),
       netCents = ShopPayrollPreview.netCents(
          grossCents: grossCents, repaymentCents: repaymentCents) {
    if (operationId.trim().isEmpty || employeeId.trim().isEmpty ||
        method.trim().isEmpty || allocationIds.isEmpty ||
        allocationIds.any((id) => id.trim().isEmpty) ||
        allocationIds.toSet().length != allocationIds.length) {
      throw ArgumentError('Invalid payroll proposal identity or selection');
    }
  }

  final String operationId;
  final String employeeId;
  final List<String> allocationIds;
  final int grossCents;
  final int repaymentCents;
  final int netCents;
  final String method;
}

