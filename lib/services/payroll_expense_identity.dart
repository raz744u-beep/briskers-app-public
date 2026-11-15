/// Stable, business-scoped identity for a financial projection of an immutable
/// verified payroll settlement. This is NOT a second payroll operation.
class PayrollExpenseIdentity {
  const PayrollExpenseIdentity._();

  static String transactionId(String businessId, String operationId) {
    if (businessId.trim().isEmpty || operationId.trim().isEmpty) {
      throw ArgumentError('Verified payroll business and operation required.');
    }
    // Both IDs are length-prefixed so concatenation cannot collide.
    return 'payroll-expense-${businessId.length}:$businessId-${operationId.length}:$operationId';
  }

  static int verifiedNetCents(Map<String, dynamic> payment) {
    final operation = payment['operation_id'];
    final net = payment['net'];
    final gross = payment['gross'];
    final repayment = payment['repayment'];
    final date = payment['verified_date'];
    if (operation is! String || operation.trim().isEmpty ||
        date is! String || DateTime.tryParse(date) == null ||
        net is! int || net < 0 || gross is! int || gross < 0 ||
        repayment is! int || repayment < 0 || gross - repayment != net) {
      throw StateError('Not a valid verified payroll settlement.');
    }
    return net;
  }
}
