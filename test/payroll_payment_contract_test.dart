import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/payroll_payment_contract.dart';

void main() {
  const shop = 'shop-a';
  const methodCash = PayrollPaymentMethod(
    id: 'cash-id',
    businessId: shop,
    label: 'Cash',
    kind: PayrollPaymentMethodKind.cash,
    enabled: true,
    sortOrder: 10,
    version: 1,
  );
  const methodCheck = PayrollPaymentMethod(
    id: 'check-id',
    businessId: shop,
    label: 'Company Check', // Renamed method: proof requirement persists.
    kind: PayrollPaymentMethodKind.check,
    enabled: true,
    sortOrder: 20,
    version: 2,
  );
  const methodZelle = PayrollPaymentMethod(
    id: 'zelle-id',
    businessId: shop,
    label: 'Zelle',
    kind: PayrollPaymentMethodKind.zelle,
    enabled: true,
    sortOrder: 30,
    version: 1,
  );
  const methodAch = PayrollPaymentMethod(
    id: 'ach-id',
    businessId: shop,
    label: 'ACH / Bank Transfer',
    kind: PayrollPaymentMethodKind.ach,
    enabled: true,
    sortOrder: 40,
    version: 1,
  );
  const methodOtherShop = PayrollPaymentMethod(
    id: 'other-shop',
    businessId: 'shop-b',
    label: 'Cash',
    kind: PayrollPaymentMethodKind.cash,
    enabled: true,
    sortOrder: 10,
    version: 1,
  );
  const disabled = PayrollPaymentMethod(
    id: 'disabled',
    businessId: shop,
    label: 'Old Bank',
    kind: PayrollPaymentMethodKind.custom,
    enabled: false,
    sortOrder: 50,
    version: 4,
  );

  PayrollPaymentDraft draft({
    String businessId = shop,
    String employeeId = 'employee-chris',
    String operationId = 'stable-operation-uuid',
    String methodId = 'cash-id',
    String methodLabelSnapshot = 'Cash',
    int amountCents = 70000,
    String payrollWeekKey = '2026-W43',
    String? sourceAccountId = 'bank-9858',
    String? checkProofAttachmentId,
    bool checkProofDurablyStored = false,
    int? checkProofSizeBytes,
    String? checkProofSha256,
  }) =>
      PayrollPaymentDraft(
        businessId: businessId,
        employeeId: employeeId,
        operationId: operationId,
        methodId: methodId,
        methodLabelSnapshot: methodLabelSnapshot,
        amountCents: amountCents,
        paymentDate: DateTime(2026, 10, 22),
        payrollWeekKey: payrollWeekKey,
        sourceAccountId: sourceAccountId,
        checkProofAttachmentId: checkProofAttachmentId,
        checkProofDurablyStored: checkProofDurablyStored,
        checkProofSizeBytes: checkProofSizeBytes,
        checkProofSha256: checkProofSha256,
      );

  group('Payroll method selection', () {
    test('uses saved employee default when no payment override', () {
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: shop,
          methods: [methodCash, methodCheck],
          employeeDefaultId: methodCash.id,
        )?.id,
        'cash-id',
      );
    });

    test('one-time override does not rewrite employee default', () {
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: shop,
          methods: [methodCash, methodCheck],
          employeeDefaultId: methodCash.id,
          paymentOverrideId: methodCheck.id,
        )?.id,
        'check-id',
      );
    });

    test('supports all four seeded kinds', () {
      expect(
        [methodCash, methodCheck, methodZelle, methodAch]
            .map((m) => m.kind)
            .toSet(),
        PayrollPaymentMethodKind.values.take(4).toSet(),
      );
    });

    test('does not silently fall back when employee default missing', () {
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: shop,
          methods: [methodCash],
          employeeDefaultId: 'no-longer-exists',
        ),
        isNull,
      );
    });

    test('never selects disabled method for a new payment', () {
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: shop,
          methods: [methodCash, disabled],
          employeeDefaultId: disabled.id,
        ),
        isNull,
      );
    });

    test('does not select another shop method', () {
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: shop,
          methods: [methodOtherShop],
          employeeDefaultId: methodOtherShop.id,
        ),
        isNull,
      );
    });

    test('duplicate method IDs fail closed instead of guessing', () {
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: shop,
          methods: [methodCash, methodCash],
          employeeDefaultId: methodCash.id,
        ),
        isNull,
      );
    });
  });

  group('Payroll payment draft validation', () {
    test('allows positive cents, stable operation and selected Cash', () {
      expect(draft().validateForSubmission(methodCash), isEmpty);
    });

    test('Cash, Zelle and ACH do not require Check photo', () {
      for (final m in [methodCash, methodZelle, methodAch]) {
        expect(
          draft(methodId: m.id, methodLabelSnapshot: m.label)
              .validateForSubmission(m),
          isEmpty,
        );
      }
    });

    test('renaming Check does not bypass proof requirement', () {
      final problems = draft(
        methodId: methodCheck.id,
        methodLabelSnapshot: 'Company Check',
      ).validateForSubmission(methodCheck);
      expect(problems, contains(PayrollDraftProblem.checkProofNotDurable));
      expect(problems, contains(PayrollDraftProblem.checkProofInvalid));
    });

    test('refuses Check proof held only in temporary picker URI', () {
      final problems = draft(
        methodId: methodCheck.id,
        methodLabelSnapshot: 'Company Check',
        checkProofAttachmentId: '/tmp/picked.jpg',
        checkProofSizeBytes: 60,
        checkProofSha256: 'a' * 64,
      ).validateForSubmission(methodCheck);
      expect(problems, contains(PayrollDraftProblem.checkProofNotDurable));
    });

    test('accepts durable private Check proof with checksum metadata', () {
      expect(
        draft(
          methodId: methodCheck.id,
          methodLabelSnapshot: 'Check', // Immutable at payment time.
          checkProofAttachmentId: 'private-attachment-id',
          checkProofDurablyStored: true,
          checkProofSizeBytes: 125000,
          checkProofSha256: 'F' * 64,
        ).validateForSubmission(methodCheck),
        isEmpty,
      );
    });

    test('rejects missing or malformed Check proof checksum', () {
      expect(
        draft(
          methodId: methodCheck.id,
          methodLabelSnapshot: 'Check',
          checkProofAttachmentId: 'proof-id',
          checkProofDurablyStored: true,
          checkProofSizeBytes: 150,
          checkProofSha256: 'short',
        ).validateForSubmission(methodCheck),
        contains(PayrollDraftProblem.checkProofInvalid),
      );
    });

    test('rejects zero or negative pay rather than creating bogus expense', () {
      expect(
        draft(amountCents: 0).validateForSubmission(methodCash),
        contains(PayrollDraftProblem.invalidAmount),
      );
      expect(
        draft(amountCents: -100).validateForSubmission(methodCash),
        contains(PayrollDraftProblem.invalidAmount),
      );
    });

    test('requires employee, operation ID and payroll week', () {
      final problems = draft(
        employeeId: '',
        operationId: '',
        payrollWeekKey: '',
      ).validateForSubmission(methodCash);
      expect(problems, contains(PayrollDraftProblem.missingEmployee));
      expect(problems, contains(PayrollDraftProblem.missingOperationId));
      expect(problems, contains(PayrollDraftProblem.missingPayrollWeek));
    });

    test('rejects mismatched method IDs and cross-shop payment', () {
      expect(
        draft(methodId: 'check-id').validateForSubmission(methodCash),
        contains(PayrollDraftProblem.paymentMethodUnavailable),
      );
      expect(
        draft().validateForSubmission(methodOtherShop),
        contains(PayrollDraftProblem.wrongShop),
      );
    });

    test('payment method, account and Payroll category are independent', () {
      final p = draft(sourceAccountId: 'bank-9858');
      expect(p.methodId, methodCash.id);
      expect(p.sourceAccountId, 'bank-9858');
      expect(p.methodLabelSnapshot, 'Cash');
    });

    test('method label is historical snapshot, not live method label', () {
      final p = draft(
        methodId: methodCheck.id,
        methodLabelSnapshot: 'Check',
        checkProofAttachmentId: 'proof',
        checkProofDurablyStored: true,
        checkProofSizeBytes: 1024,
        checkProofSha256: '0' * 64,
      );
      expect(p.methodLabelSnapshot, 'Check');
      expect(methodCheck.label, 'Company Check');
      expect(p.validateForSubmission(methodCheck), isEmpty);
    });

    test('same operation ID remains stable for replay', () {
      final before = draft();
      final afterRestart = draft();
      expect(before.operationId, afterRestart.operationId);
      // Backend and outbox must enforce uniqueness; the model alone cannot.
    });
  });
}
