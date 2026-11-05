/// Settlement totals use payroll week identity. Unpaid balances use remaining
/// credit coverage, so a partial payment never counts the same hours twice.
class PayrollPeriodTotals {
  const PayrollPeriodTotals({
    required this.hours, required this.grossCents, required this.paidCents,
    required this.balanceCents, required this.hasRecords,
  });
  final double hours;
  final int? grossCents;
  final int paidCents;
  final int? balanceCents;
  final bool hasRecords;

  static PayrollPeriodTotals calculate({
    required Iterable<Map<String, dynamic>> work,
    required Iterable<Map<String, dynamic>> payments,
    required DateTime from,
    required DateTime until,
  }) {
    bool within(Object? raw) {
      final date = DateTime.tryParse(raw?.toString() ?? '');
      return date != null && !date.isBefore(from) && date.isBefore(until);
    }
    final earned = work.where((row) =>
      row['state'] == 'Done' && row['paid'] != 1 && within(row['completed_date'])).toList();
    final settled = payments.where((row) => within(row['week'])).toList();
    final unpaid = earned.fold<int>(0, (sum, row) =>
      sum + (row['remaining_cents'] as int? ?? row['gross_cents'] as int));
    final gross = settled.fold<int>(0, (sum, row) => sum + (row['gross'] as int));
    final net = settled.fold<int>(0, (sum, row) => sum + (row['net'] as int));
    final unpaidMinutes = earned.fold<int>(0, (sum, row) =>
      sum + (row['remaining_minutes'] as int? ?? row['actual_minutes'] as int));
    final paidMinutes = settled.expand((row) => row['work'] as List<Map<String, dynamic>>)
      .fold<int>(0, (sum, row) => sum + (row['actual_minutes'] as int? ?? 0));
    final known = earned.isNotEmpty || settled.isNotEmpty;
    return PayrollPeriodTotals(
      hours: (unpaidMinutes + paidMinutes) / 60,
      grossCents: known ? unpaid + gross : null, paidCents: net,
      balanceCents: known ? unpaid : null, hasRecords: known,
    );
  }
}
