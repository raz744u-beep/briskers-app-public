/// Fail-closed validation for simulated payroll disbursements.
/// No real money or production ledger writes are performed here.
class TestPayrollPaymentPolicy {
  const TestPayrollPaymentPolicy._();

  static void validate({
    required int cents,
    required String method,
    required String kind,
    String? checkProofReference,
    String? overrideReason,
    bool amountOverridden = false,
  }) {
    if (cents <= 0 || cents > 100000000) {
      throw ArgumentError('Invalid payment amount');
    }
    if (!const {'cash', 'check', 'zelle', 'ach', 'card', 'other'}
        .contains(method)) {
      throw ArgumentError('Unsupported payment method');
    }
    if (!const {'pay', 'advance'}.contains(kind)) {
      throw ArgumentError('Unsupported payment type');
    }
    if (method == 'check' &&
        (checkProofReference == null || checkProofReference.trim().isEmpty)) {
      throw StateError('Check proof is required');
    }
    if (amountOverridden &&
        (overrideReason == null || overrideReason.trim().isEmpty)) {
      throw StateError('Payroll amount override requires a reason');
    }
  }
}
