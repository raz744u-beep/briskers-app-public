import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
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

  test('Shared work credits finished mechanic before coworkers finish', () {
    expect(ShopWorkflowStatusPolicy.sharedTask([
      ShopTaskProgress.done, ShopTaskProgress.inProgress,
    ]), ShopTaskProgress.inProgress);
    expect(ShopWorkflowStatusPolicy.eligibleSharedTaskPortionForPayroll(
      owner: true,
      mechanicProgress: ShopTaskProgress.done,
      alreadyPaid: false,
      alreadySelected: false,
    ), isTrue);
    expect(ShopWorkflowStatusPolicy.eligibleSharedTaskPortionForPayroll(
      owner: true,
      mechanicProgress: ShopTaskProgress.inProgress,
      alreadyPaid: false,
      alreadySelected: false,
    ), isFalse);
    expect(ShopWorkflowStatusPolicy.eligibleSharedTaskPortionForPayroll(
      owner: true,
      mechanicProgress: ShopTaskProgress.done,
      alreadyPaid: true,
      alreadySelected: false,
    ), isFalse);
    expect(ShopWorkflowStatusPolicy.eligibleSharedTaskPortionForPayroll(
      owner: false,
      mechanicProgress: ShopTaskProgress.done,
      alreadyPaid: false,
      alreadySelected: false,
    ), isFalse);
  });

  test('Weekly payroll cannot contain duplicate or blank allocation IDs', () {
    expect(ShopWorkflowStatusPolicy.hasUniquePayrollAllocationIds([
      'job-1/chris', 'job-1/kam', 'job-2/chris',
    ]), isTrue);
    expect(ShopWorkflowStatusPolicy.hasUniquePayrollAllocationIds([
      'job-1/chris', 'job-1/chris',
    ]), isFalse);
    expect(ShopWorkflowStatusPolicy.hasUniquePayrollAllocationIds(['  ']),
        isFalse);
  });

  test('Payroll preview calculates gross and repayment in cents', () {
    const work = ShopPayrollAllocation(
      id: 'credit-1', employeeId: 'mechanic-1',
      hoursHundredths: 250, rateCentsPerHour: 4000,
      completed: true, alreadyPaid: false,
    );
    expect(work.grossCents, 10000);
    expect(ShopPayrollPreview.grossCents(
      owner: true, employeeId: 'mechanic-1', selected: [work],
    ), 10000);
    expect(ShopPayrollPreview.netCents(
      grossCents: 10500, repaymentCents: 2000,
    ), 8500);
    expect(() => ShopPayrollPreview.grossCents(
      owner: true, employeeId: 'mechanic-1', selected: [work, work],
    ), throwsStateError);
    expect(() => ShopPayrollPreview.grossCents(
      owner: false, employeeId: 'mechanic-1', selected: [work],
    ), throwsStateError);
    expect(() => ShopPayrollPreview.netCents(
      grossCents: 1000, repaymentCents: 1001,
    ), throwsArgumentError);
  });

  test('Verify Payment requires selected work, Owner and method', () {
    bool allowed({
      bool owner = true,
      bool hasWork = true,
      bool current = true,
      bool method = true,
      bool committed = false,
    }) => ShopPayrollPreview.canVerifyPayment(
      owner: owner,
      hasSelectedWork: hasWork,
      localAllocationsCurrent: current,
      methodSelected: method,
      alreadyCommitted: committed,
    );
    expect(allowed(), isTrue);
    expect(allowed(owner: false), isFalse);
    expect(allowed(hasWork: false), isFalse);
    expect(allowed(current: false), isFalse);
    expect(allowed(method: false), isFalse);
    expect(allowed(committed: true), isFalse);
  });

  test('Repayment cannot exceed current advance or gross pay', () {
    expect(ShopPayrollPreview.verifiedRepaymentCents(
      grossCents: 10500,
      outstandingAdvanceCents: 3000,
      requestedRepaymentCents: 2000,
    ), 2000);
    expect(() => ShopPayrollPreview.verifiedRepaymentCents(
      grossCents: 10500,
      outstandingAdvanceCents: 1000,
      requestedRepaymentCents: 2000,
    ), throwsArgumentError);
    expect(() => ShopPayrollPreview.verifiedRepaymentCents(
      grossCents: 1000,
      outstandingAdvanceCents: 3000,
      requestedRepaymentCents: 2000,
    ), throwsArgumentError);
  });

  test('Verify Payment proposal freezes allocation IDs and net amount', () {
    final ids = <String>['credit-a'];
    final proposal = ShopPayrollPaymentProposal(
      operationId: 'local-op-1', employeeId: 'mechanic-1',
      allocationIds: ids, grossCents: 10500, repaymentCents: 2000,
      method: 'Zelle',
    );
    ids.add('credit-b');
    expect(proposal.allocationIds, ['credit-a']);
    expect(proposal.netCents, 8500);
    expect(() => proposal.allocationIds.add('credit-c'), throwsUnsupportedError);
    expect(() => ShopPayrollPaymentProposal(
      operationId: 'local-op-2', employeeId: 'mechanic-1',
      allocationIds: ['a', 'a'], grossCents: 10000,
      repaymentCents: 0, method: 'Zelle',
    ), throwsArgumentError);
  });

  test('Exact payroll retry is recognized; changed retry conflicts', () {
    ShopPayrollPaymentProposal proposal({
      String operationId = 'op-1',
      List<String> credits = const ['a', 'b'],
      int repayment = 2000,
      String method = 'Zelle',
    }) => ShopPayrollPaymentProposal(
      operationId: operationId,
      employeeId: 'mechanic-1',
      allocationIds: credits,
      grossCents: 10500,
      repaymentCents: repayment,
      method: method,
    );
    final saved = proposal();
    expect(ShopPayrollReplayPolicy.sameProposal(
      saved, proposal(credits: ['b', 'a'])), isTrue);
    expect(ShopPayrollReplayPolicy.conflictingReplay(
      saved, proposal(repayment: 1000)), isTrue);
    expect(ShopPayrollReplayPolicy.conflictingReplay(
      saved, proposal(method: 'Cash')), isTrue);
    expect(ShopPayrollReplayPolicy.conflictingReplay(
      saved, proposal(credits: ['a'])), isTrue);
    expect(ShopPayrollReplayPolicy.conflictingReplay(
      saved, proposal(operationId: 'op-2')), isFalse);
  });

  test('Transaction preflight rejects mismatched amounts and paid work', () {
    const credit = ShopPayrollAllocation(
      id: 'credit-a', employeeId: 'mechanic',
      hoursHundredths: 250, rateCentsPerHour: 4000,
      completed: true, alreadyPaid: false,
    );
    ShopPayrollPaymentProposal proposal({int gross = 10000}) =>
        ShopPayrollPaymentProposal(
          operationId: 'op1', employeeId: 'mechanic',
          allocationIds: ['credit-a'], grossCents: gross,
          repaymentCents: 2000, method: 'Zelle',
        );
    bool valid({bool owner = true, bool unused = true, int gross = 10000,
      int advance = 3000}) => ShopPayrollTransactionPreflight.isValid(
        owner: owner, proposal: proposal(gross: gross),
        selectedCredits: [credit], outstandingAdvanceCents: advance,
        operationIdUnused: unused,
      );
    expect(valid(), isTrue);
    expect(valid(owner: false), isFalse);
    expect(valid(unused: false), isFalse);
    expect(valid(gross: 9900), isFalse);
    expect(valid(advance: 1000), isFalse);
    expect(ShopPayrollTransactionPreflight.isValid(
      owner: true, proposal: proposal(),
      selectedCredits: const [], outstandingAdvanceCents: 3000,
      operationIdUnused: true,
    ), isFalse);
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
