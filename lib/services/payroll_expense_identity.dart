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

  /// Resolve a real cached financial option, never synthesize an account or
  /// category ID. Duplicate labels are ambiguous and require Owner review.
  static String? uniqueOptionId(
    List<Map<String, dynamic>> options,
    String expectedName,
  ) {
    final matches = options.where((row) {
      final name = (row['name'] ?? row['label'])?.toString().trim();
      return name != null &&
          name.toLowerCase() == expectedName.trim().toLowerCase() &&
          row['id']?.toString().trim().isNotEmpty == true;
    }).toList();
    if (matches.length != 1) return null;
    return matches.single['id'].toString();
  }

  /// Build a financial row only from an immutable, verified payment and
  /// already-resolved account/category identities. No cashflow is posted here.
  static Map<String, dynamic> expenseProjection({
    required String businessId,
    required Map<String, dynamic> payment,
    required String employeeName,
    required String accountId,
    required String categoryId,
  }) {
    final cents = verifiedNetCents(payment);
    if (businessId.trim().isEmpty || employeeName.trim().isEmpty ||
        accountId.trim().isEmpty || categoryId.trim().isEmpty ||
        cents == 0) {
      throw StateError('Payroll expense requires verified positive net and saved options.');
    }
    final operationId = payment['operation_id'] as String;
    final date = DateTime.parse(payment['verified_date'] as String);
    final dateText = date.toIso8601String().split('T').first;
    final amount = cents / 100;
    return <String, dynamic>{
      'id': transactionId(businessId, operationId),
      'business_id': businessId,
      'payroll_operation_id': operationId,
      'direction': 'expense',
      'amount': amount,
      'signed_amount': -amount,
      'date': dateText,
      'transaction_date': dateText,
      'counterparty': employeeName.trim(),
      'category': 'Payroll',
      'category_id': categoryId,
      'account': 'Business Checking – 9858',
      'account_id': accountId,
      'payment_method': payment['method'],
      'remarks': 'Verified payroll payment',
    };
  }

  /// Decide whether a verified settlement needs a financial projection.
  ///
  /// Existing expenses are matched by a durable operation link, never by
  /// employee name, date, or amount (those may coincide across payments).
  /// A conflicting or ambiguous link blocks posting for Owner review.
  static PayrollExpenseDecision classify({
    required String businessId,
    required Map<String, dynamic> payment,
    required List<Map<String, dynamic>> existingExpenses,
  }) {
    verifiedNetCents(payment);
    final operationId = payment['operation_id'] as String;
    final expectedId = transactionId(businessId, operationId);
    final linked = existingExpenses.where((expense) =>
        expense['payroll_operation_id'] == operationId ||
        expense['id'] == expectedId).toList();
    if (linked.isEmpty) return PayrollExpenseDecision.create;
    if (linked.length != 1) return PayrollExpenseDecision.review;
    final expense = linked.single;
    final linkedOperation = expense['payroll_operation_id'];
    if ((linkedOperation != null && linkedOperation != operationId) ||
        expense['direction'] != 'expense' ||
        expense['business_id'] != null && expense['business_id'] != businessId ||
        expense['amount'] is! num ||
        ((expense['amount'] as num) * 100).round() != payment['net']) {
      return PayrollExpenseDecision.review;
    }
    return PayrollExpenseDecision.alreadyLinked;
  }
}

enum PayrollExpenseDecision { create, alreadyLinked, review }
