/// Data-only foundation for #297 payroll payment methods.
///
/// This file deliberately does NOT post financial transactions, persist proof
/// photos, grant permissions, or implement sync. Those operations require the
/// reviewed shop-scoped backend contract described in
/// docs/payroll-methods-implementation-contract.md.
///
/// Method IDs are shop-scoped identities. A method's display name may change;
/// its [kind] must not be inferred from the name (especially for Check).
enum PayrollPaymentMethodKind { cash, check, zelle, ach, custom }

class PayrollPaymentMethod {
  const PayrollPaymentMethod({
    required this.id,
    required this.businessId,
    required this.label,
    required this.kind,
    required this.enabled,
    required this.sortOrder,
    required this.version,
  });

  final String id;
  final String businessId;
  final String label;
  final PayrollPaymentMethodKind kind;
  final bool enabled;
  final int sortOrder;
  final int version;

  bool get requiresCheckPhoto => kind == PayrollPaymentMethodKind.check;
}

/// Select a saved employee default, or a one-time payment-level override.
///
/// No automatic fallback: a deleted/disabled/missing default requires explicit
/// Owner choice. Existing historical payments keep their label snapshots.
class PayrollPaymentMethodChoice {
  const PayrollPaymentMethodChoice._();

  static PayrollPaymentMethod? resolve({
    required String businessId,
    required List<PayrollPaymentMethod> methods,
    String? employeeDefaultId,
    String? paymentOverrideId,
  }) {
    final id = paymentOverrideId ?? employeeDefaultId;
    if (id == null || id.trim().isEmpty) return null;

    final matches = methods
        .where((m) => m.id == id && m.businessId == businessId && m.enabled)
        .toList();
    // A duplicated ID is not a safe method choice.
    return matches.length == 1 ? matches.single : null;
  }
}

/// A partial allocation of one payout to an existing earned labor row.
/// Any unallocated remainder remains an advance/extra amount, not invented labor.
class PayrollLaborAllocation {
  const PayrollLaborAllocation({
    required this.laborId,
    required this.amountCents,
  });
  final String laborId;
  final int amountCents;
  Map<String, dynamic> toJson() => {
    'labor_id': laborId,
    'amount_cents': amountCents,
  };
  static PayrollLaborAllocation fromJson(Map<String, dynamic> value) =>
      PayrollLaborAllocation(
        laborId: value['labor_id'] as String,
        amountCents: value['amount_cents'] as int,
      );
}

enum PayrollDraftProblem {
  wrongShop,
  paymentMethodUnavailable,
  missingEmployee,
  missingOperationId,
  invalidAmount,
  invalidLaborAllocation,
  missingPayrollWeek,
  checkProofNotDurable,
  checkProofInvalid,
}

/// An intended payment, not proof that a payment has posted.
///
/// One stable operation ID must be reused on every offline replay. Persist the
/// method ID AND label snapshot so renamed methods preserve older records.
class PayrollPaymentDraft {
  const PayrollPaymentDraft({
    required this.businessId,
    required this.employeeId,
    required this.operationId,
    required this.methodId,
    required this.methodLabelSnapshot,
    required this.amountCents,
    required this.paymentDate,
    required this.payrollWeekKey,
    this.laborAllocations = const [],
    this.sourceAccountId,
    this.reference,
    this.checkProofAttachmentId,
    this.checkProofDurablyStored = false,
    this.checkProofSizeBytes,
    this.checkProofSha256,
  });

  final String businessId;
  final String employeeId;
  final String operationId;
  final String methodId;
  final String methodLabelSnapshot;
  final int amountCents;
  final DateTime paymentDate;
  final String payrollWeekKey;
  final List<PayrollLaborAllocation> laborAllocations;

  /// A bank/cash account is NOT a payment method or an expense category.
  final String? sourceAccountId;
  final String? reference;

  /// Identifiers for a proof already copied into durable private app storage.
  /// This contract does not itself read or upload attachment bytes.
  final String? checkProofAttachmentId;
  final bool checkProofDurablyStored;
  final int? checkProofSizeBytes;
  final String? checkProofSha256;

  /// A saved Check photo only describes these exact payment terms. A method
  /// rename is display-only; changes to the payee or payment require a new photo
  /// selection/reconfirmation. The caller must also verify the actual bytes.
  bool proofMatchesTerms({
    required String businessId,
    required String employeeId,
    required String operationId,
    required String methodId,
    required int amountCents,
    required DateTime paymentDate,
    required String payrollWeekKey,
    required String? sourceAccountId,
    required String? reference,
    List<PayrollLaborAllocation> laborAllocations = const [],
  }) {
    final oldDate = this.paymentDate.toLocal();
    final newDate = paymentDate.toLocal();
    return this.businessId == businessId &&
        this.employeeId == employeeId &&
        this.operationId == operationId &&
        this.methodId == methodId &&
        this.amountCents == amountCents &&
        this.payrollWeekKey == payrollWeekKey &&
        this.sourceAccountId == sourceAccountId &&
        this.reference == reference &&
        this.laborAllocations.length == laborAllocations.length &&
        this.laborAllocations.every(
          (a) => laborAllocations.any(
            (b) => a.laborId == b.laborId && a.amountCents == b.amountCents,
          ),
        ) &&
        oldDate.year == newDate.year &&
        oldDate.month == newDate.month &&
        oldDate.day == newDate.day;
  }

  List<PayrollDraftProblem> validateForSubmission(
    PayrollPaymentMethod? method,
  ) {
    final problems = <PayrollDraftProblem>[];
    if (businessId.trim().isEmpty ||
        (method != null && method.businessId != businessId)) {
      problems.add(PayrollDraftProblem.wrongShop);
    }
    if (method == null ||
        !method.enabled ||
        method.id != methodId ||
        methodLabelSnapshot.trim().isEmpty) {
      problems.add(PayrollDraftProblem.paymentMethodUnavailable);
    }
    if (employeeId.trim().isEmpty) {
      problems.add(PayrollDraftProblem.missingEmployee);
    }
    if (operationId.trim().isEmpty) {
      problems.add(PayrollDraftProblem.missingOperationId);
    }
    if (amountCents <= 0) {
      problems.add(PayrollDraftProblem.invalidAmount);
    }
    final laborIds = <String>{};
    if (laborAllocations.any(
          (a) =>
              a.amountCents <= 0 ||
              !RegExp(
                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
              ).hasMatch(a.laborId) ||
              !laborIds.add(a.laborId),
        ) ||
        laborAllocations.fold<int>(0, (n, a) => n + a.amountCents) >
            amountCents) {
      problems.add(PayrollDraftProblem.invalidLaborAllocation);
    }
    if (payrollWeekKey.trim().isEmpty) {
      problems.add(PayrollDraftProblem.missingPayrollWeek);
    }

    if (method?.requiresCheckPhoto == true) {
      if (!checkProofDurablyStored ||
          checkProofAttachmentId == null ||
          checkProofAttachmentId!.trim().isEmpty) {
        problems.add(PayrollDraftProblem.checkProofNotDurable);
      }
      if (checkProofSizeBytes == null ||
          checkProofSizeBytes! <= 0 ||
          checkProofSha256 == null ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(checkProofSha256!)) {
        problems.add(PayrollDraftProblem.checkProofInvalid);
      }
    }
    return List.unmodifiable(problems);
  }
}
