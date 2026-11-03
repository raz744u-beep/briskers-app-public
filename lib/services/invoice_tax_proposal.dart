/// Pure preview only. This class makes no database or payment changes.
/// Applying a rate across live invoice lines requires one audited server
/// transaction, not a series of independent document-line updates.
class InvoiceTaxProposal {
  const InvoiceTaxProposal._();

  static int _cents(num amount) => (amount * 100).round();
  static double _money(int cents) => cents / 100;

  /// Proposes the same rate for all ordinary taxable lines.
  /// Exempt/explicit custom rates are not changed. Records without an
  /// explicit classification are refused to avoid overriding exemptions.
  static Map<String, dynamic> preview({
    required List<Map<String, dynamic>> lines,
    required num rate,
  }) {
    if (!rate.isFinite || rate < 0 || rate > 1) {
      throw ArgumentError.value(rate, 'rate', 'Must be between 0 and 1');
    }
    var taxableNetCents = 0;
    var proposedTaxCents = 0;
    var currentTaxCents = 0;
    var preservedTaxCents = 0;
    var changedCount = 0;
    for (final line in lines) {
      if (line['line_kind']?.toString() == 'discount') {
        throw StateError('Discount tax ordering requires server verification.');
      }
      final mode = line['tax_mode']?.toString();
      if (mode != 'default' && mode != 'exempt' && mode != 'custom') {
        throw StateError('Tax classification must be verified before editing.');
      }
      final quantity = num.tryParse(line['quantity']?.toString() ?? '');
      final unit = num.tryParse(line['unit_price']?.toString() ?? '');
      final oldRate = num.tryParse(line['tax_rate']?.toString() ?? '');
      if (quantity == null || unit == null || oldRate == null ||
          !quantity.isFinite || !unit.isFinite || !oldRate.isFinite) {
        throw StateError('Cannot calculate an invoice line with missing amounts.');
      }
      final netCents = _cents(quantity * unit);
      final oldTaxCents = _cents(_money(netCents) * oldRate);
      currentTaxCents += oldTaxCents;
      if (mode == 'default') {
        taxableNetCents += netCents;
        proposedTaxCents += _cents(_money(netCents) * rate);
        if ((oldRate - rate).abs() > 0.0000001) changedCount++;
      } else {
        preservedTaxCents += oldTaxCents;
      }
    }
    final taxCents = proposedTaxCents + preservedTaxCents;
    final netCents = lines.fold<int>(0, (sum, line) =>
      sum + _cents((num.tryParse(line['quantity']?.toString() ?? '') ?? 0) *
          (num.tryParse(line['unit_price']?.toString() ?? '') ?? 0)));
    return {
      'rate': rate,
      'changed_count': changedCount,
      'taxable_subtotal': _money(taxableNetCents),
      'old_tax': _money(currentTaxCents),
      'new_tax': _money(taxCents),
      'new_total': _money(netCents + taxCents),
    };
  }
}
