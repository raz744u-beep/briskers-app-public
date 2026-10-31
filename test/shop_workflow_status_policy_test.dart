import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_workflow_status_policy.dart';

void main() {
  test('Main Job/Invoice statuses are only Open or confirmed Closed', () {
    expect(ShopWorkflowStatusPolicy.jobMain(closureConfirmed: false),
        ShopMainStatus.open);
    expect(ShopWorkflowStatusPolicy.invoiceMain(closureConfirmed: false),
        ShopMainStatus.open);
    expect(ShopWorkflowStatusPolicy.jobMain(closureConfirmed: true),
        ShopMainStatus.closed);
    expect(ShopWorkflowStatusPolicy.invoiceMain(closureConfirmed: true),
        ShopMainStatus.closed);
    expect(ShopMainStatus.values, hasLength(2));
  });

  test('Entered but unfinalized full receipt never creates Paid', () {
    const total = 301.81;
    expect(ShopWorkflowStatusPolicy.payment(
      invoiceTotal: total, finalizedPayments: 0),
      ShopPaymentStatus.unpaid);
    expect(ShopWorkflowStatusPolicy.payment(
      invoiceTotal: total, finalizedPayments: 200),
      ShopPaymentStatus.partial);
    expect(ShopWorkflowStatusPolicy.payment(
      invoiceTotal: total, finalizedPayments: total),
      ShopPaymentStatus.paid);
    expect(() => ShopWorkflowStatusPolicy.payment(
      invoiceTotal: -1, finalizedPayments: 0),
      throwsArgumentError);
  });

  test('Shared task Chris Done / Adam In Progress stays In Progress', () {
    expect(ShopWorkflowStatusPolicy.sharedTask([
      ShopTaskProgress.done, ShopTaskProgress.inProgress,
    ]), ShopTaskProgress.inProgress);
    expect(ShopWorkflowStatusPolicy.sharedTask([
      ShopTaskProgress.done, ShopTaskProgress.done,
    ]), ShopTaskProgress.done);
    expect(ShopWorkflowStatusPolicy.sharedTask([
      ShopTaskProgress.notStarted, ShopTaskProgress.notStarted,
    ]), ShopTaskProgress.notStarted);
    expect(ShopWorkflowStatusPolicy.sharedTask(const []),
      ShopTaskProgress.notStarted);
  });

  test('Payroll selects only completed unpaid mechanic portions once', () {
    bool eligible({
      bool owner = true,
      bool done = true,
      bool paid = false,
      bool selected = false,
    }) => ShopWorkflowStatusPolicy.eligibleForPayrollSelection(
      owner: owner,
      mechanicPortionDone: done,
      alreadyPaid: paid,
      alreadySelected: selected,
    );

    expect(eligible(), isTrue);
    expect(eligible(owner: false), isFalse);
    expect(eligible(done: false), isFalse);
    expect(eligible(paid: true), isFalse);
    expect(eligible(selected: true), isFalse);
    // Even if previously paid work is reopened and completed again,
    // its frozen payroll credit must never be offered for selection.
    expect(eligible(done: true, paid: true), isFalse);
  });

  test('Joint close requires Owner, finalized payment and finished work', () {
    bool allowed({bool owner = true, bool paid = true,
      bool unresolved = false, bool done = true}) =>
        ShopWorkflowStatusPolicy.eligibleForJointClose(
          owner: owner,
          fullFinalizedPayment: paid,
          unresolvedPayment: unresolved,
          workReady: done);
    expect(allowed(), isTrue);
    expect(allowed(owner: false), isFalse);
    expect(allowed(paid: false), isFalse);
    expect(allowed(unresolved: true), isFalse);
    expect(allowed(done: false), isFalse);
    // Pure eligibility is not a side effect; only backend confirmation
    // may set the main status Closed.
    expect(ShopWorkflowStatusPolicy.invoiceMain(closureConfirmed: false),
      ShopMainStatus.open);
  });
}
