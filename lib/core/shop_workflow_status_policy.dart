/// Pure status contract for the unified Briskers Tasks/Payroll TEST candidate.
///
/// Main customer-facing Job/Invoice status is *only* Open or Closed. Financial
/// receipt finalization, mechanic task progress and internal attention flags
/// must never create a third main status or silently finalize money.
enum ShopMainStatus { open, closed }

enum ShopPaymentStatus { unpaid, partial, paid }

enum ShopTaskProgress { notStarted, inProgress, done }

class ShopWorkflowStatusPolicy {
  const ShopWorkflowStatusPolicy._();

  static ShopMainStatus jobMain({required bool closureConfirmed}) =>
      closureConfirmed ? ShopMainStatus.closed : ShopMainStatus.open;

  static ShopMainStatus invoiceMain({required bool closureConfirmed}) =>
      closureConfirmed ? ShopMainStatus.closed : ShopMainStatus.open;

  /// Only posted/finalized payments can yield Paid. An entered but
  /// unfinalized receipt must remain outside this calculation.
  static ShopPaymentStatus payment({
    required num invoiceTotal,
    required num finalizedPayments,
  }) {
    if (!invoiceTotal.isFinite ||
        !finalizedPayments.isFinite ||
        invoiceTotal < 0 ||
        finalizedPayments < 0) {
      throw ArgumentError('Invalid invoice total or finalized payments');
    }
    if (invoiceTotal <= 0 || finalizedPayments < 0.005) {
      return ShopPaymentStatus.unpaid;
    }
    if (finalizedPayments >= invoiceTotal - 0.005) {
      return ShopPaymentStatus.paid;
    }
    return ShopPaymentStatus.partial;
  }

  /// Individual mechanic progress is independent. The overall task is Done
  /// only when ALL assigned mechanics are Done. A missing assignment cannot
  /// certify completion.
  static ShopTaskProgress sharedTask(
      Iterable<ShopTaskProgress> mechanics) {
    final portions = mechanics.toList(growable: false);
    if (portions.isEmpty) return ShopTaskProgress.notStarted;
    if (portions.every((progress) => progress == ShopTaskProgress.done)) {
      return ShopTaskProgress.done;
    }
    if (portions.any(
      (progress) => progress != ShopTaskProgress.notStarted,
    )) {
      return ShopTaskProgress.inProgress;
    }
    return ShopTaskProgress.notStarted;
  }

  /// Internal eligibility for the Owner's Complete Job action.
  /// This does NOT close anything: the backend must independently verify
  /// payment, durable task/job state, permission and an acknowledged close.
  static bool eligibleForJointClose({
    required bool owner,
    required bool fullFinalizedPayment,
    required bool unresolvedPayment,
    required bool workReady,
  }) =>
      owner && fullFinalizedPayment && !unresolvedPayment && workReady;
}
