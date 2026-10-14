/// Warranty receipt presentation. Invoice credit is always the actual amount
/// received; the processor pass-through is deducted only from retained receipts.
/// This helper never mutates a payment, invoice, tax allocation, or balance.
class WarrantyPaymentAmounts {
  const WarrantyPaymentAmounts({required this.grossCents, required this.feeCents});

  final int grossCents;
  final int feeCents;
  num get gross => grossCents / 100;
  num get fee => feeCents / 100;
  num get retained => (grossCents - feeCents) / 100;

  static int? cents(Object? value) {
    final amount = num.tryParse(value?.toString() ?? '');
    if (amount == null || !amount.isFinite || !(amount * 100).isFinite || amount < 0) return null;
    return (amount * 100).round();
  }

  static WarrantyPaymentAmounts? fromReceipt({
    required Object? gross,
    required Object? processorFee,
  }) {
    final received = cents(gross);
    final fee = cents(processorFee);
    if (received == null || fee == null || fee > received) return null;
    return WarrantyPaymentAmounts(grossCents: received, feeCents: fee);
  }

  static bool isLivePayment(Map<String, dynamic> payment) => const {
    'posted', 'finalized', 'pending',
  }.contains(payment['state']?.toString().toLowerCase());

  static bool matchesMethod(Map<String, dynamic> payment, bool check) {
    final name = payment['payment_method_name']?.toString().toLowerCase() ?? '';
    return check ? name.contains('check') : name.contains('credit') && name.contains('card');
  }

  /// Capture guard is deliberately broader than fee attribution. A legacy
  /// net receipt or split receipts require review, never another shortcut.
  static bool hasCandidateReceipt(Map<String, dynamic> warranty,
      Iterable<Map<String, dynamic>> payments) {
    if (warranty['extended_warranty'] != true) return false;
    final rate = num.tryParse(warranty['surcharge_rate']?.toString() ?? '') ?? 0;
    return payments.any((payment) => isLivePayment(payment) &&
      matchesMethod(payment, rate <= 0.000001));
  }

  /// Only a single eligible receipt within this exact invoice is attributable.
  /// Multiple card/check receipts are ambiguous; never deduct the fee per row.
  static Map<String, dynamic>? receipt(
    Map<String, dynamic> warranty,
    Iterable<Map<String, dynamic>> payments,
  ) {
    if (warranty['extended_warranty'] != true) return null;
    final rate = num.tryParse(warranty['surcharge_rate']?.toString() ?? '') ?? 0;
    final matches = payments.where((payment) => isLivePayment(payment) &&
      matchesMethod(payment, rate <= 0.000001) &&
      (cents(payment['amount']) ?? 0) > 0).toList();
    if (matches.length != 1) return null;
    final selected = matches.single;
    // A matching method is not sufficient for an arbitrary partial receipt.
    // Require the approved gross or the stored actual terminal amount too.
    final amount = cents(selected['amount']);
    final fee = cents(warranty['processor_fee']);
    final terminal = cents(warranty['terminal_amount']);
    final net = cents(warranty['net_applied']);
    final terminalIsActualGross = fee != null && terminal != null &&
      net != null && terminal - net == fee;
    if (amount != cents(warranty['approved_amount']) &&
        !(terminalIsActualGross && amount == terminal)) {
      return null;
    }
    return selected;
  }
}
