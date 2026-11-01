import '../core/shop_payroll_preview.dart';
import 'test_payroll_credit_repository.dart';

/// TEST-only adapter for one mechanic's completion event. This is intentionally
/// not attached to live Jobs or server task status operations.
class TestMechanicCompletionBridge {
  TestMechanicCompletionBridge({TestPayrollCreditRepository? credits})
      : _credits = credits ?? TestPayrollCreditRepository();

  final TestPayrollCreditRepository _credits;

  Future<bool> completeSyntheticWork({
    required String businessId,
    required String allocationId,
    required String employeeId,
    required int hoursHundredths,
    required int rateCentsPerHour,
  }) async {
    if (businessId.trim().isEmpty || allocationId.trim().isEmpty ||
        employeeId.trim().isEmpty) {
      throw ArgumentError('Missing TEST work identity');
    }
    final allocation = ShopPayrollAllocation(
      id: allocationId,
      employeeId: employeeId,
      hoursHundredths: hoursHundredths,
      rateCentsPerHour: rateCentsPerHour,
      completed: false,
      alreadyPaid: false,
    );
    allocation.grossCents;
    // The credit must already exist as an explicit assignment. Completion
    // never creates a new payroll allocation or guesses worked hours.
    return _credits.markSyntheticPortionDone(
      businessId: businessId,
      employeeId: employeeId,
      allocationId: allocationId,
    );
  }
}
