/// Presentation of the permission-checked job profitability RPC.
///
/// `revenue` is already the sum of invoice net amounts, after the document's
/// discounts and excluding sales tax. Neither tax nor a warranty fee should be
/// deducted from it again. Costs must come from the accounting source, not from
/// an unpaid customer balance or an inferred processor charge.
class JobProfitabilitySummary {
  const JobProfitabilitySummary._({
    required this.revenue,
    required this.salesTax,
    required this.directCost,
    required this.mechanicCost,
    required this.totalCost,
    required this.profit,
    required this.marginPercent,
  });

  final num revenue;
  final num salesTax;
  final num directCost;
  final num mechanicCost;
  final num totalCost;
  final num profit;
  final num? marginPercent;

  static int? _cents(dynamic raw) {
    final value = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    if (value == null || !value.isFinite || !(value * 100).isFinite) {
      return null;
    }
    return (value * 100).round();
  }

  /// Missing or invalid accounting amounts do not become a reassuring zero.
  /// Gross less tax is only a compatibility fallback when pre-tax revenue is
  /// absent. An explicit zero revenue remains zero.
  static JobProfitabilitySummary? fromRpc(Map<String, dynamic> data) {
    final tax = _cents(data['sales_tax']);
    final gross = _cents(data['gross_billed']);
    final hasRevenue = data['revenue'] != null;
    final revenue = hasRevenue
        ? _cents(data['revenue'])
        : gross != null && tax != null
        ? gross - tax
        : null;
    final direct = _cents(data['direct_cost']);
    final mechanic = _cents(data['mechanic_cost']);
    if (revenue == null || tax == null || direct == null || mechanic == null) {
      return null;
    }
    final hasTotalCost = data['total_cost'] != null;
    final cost = hasTotalCost ? _cents(data['total_cost']) : direct + mechanic;
    if (cost == null) return null;
    final profit = revenue - cost;
    return JobProfitabilitySummary._(
      revenue: revenue / 100,
      salesTax: tax / 100,
      directCost: direct / 100,
      mechanicCost: mechanic / 100,
      totalCost: cost / 100,
      profit: profit / 100,
      marginPercent: revenue > 0 ? profit * 100 / revenue : null,
    );
  }
}
