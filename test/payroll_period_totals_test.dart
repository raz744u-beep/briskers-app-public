import 'package:briskers_app/services/payroll_period_totals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('partial paid hours and unpaid remainder reconcile once in summary', () {
    final totals = PayrollPeriodTotals.calculate(
      from: DateTime(2026, 11, 2), until: DateTime(2026, 11, 9),
      work: const [
        {'state': 'Done', 'paid': 0, 'completed_date': '2026-11-04',
          'actual_minutes': 60, 'remaining_minutes': 40,
          'gross_cents': 1001, 'remaining_cents': 667},
      ],
      payments: const [
        {'week': '2026-11-02', 'gross': 334, 'net': 234,
          'work': <Map<String, dynamic>>[{'actual_minutes': 20}]},
        {'week': '2026-10-26', 'gross': 900, 'net': 900,
          'work': <Map<String, dynamic>>[{'actual_minutes': 60}]},
      ],
    );
    expect(totals.hours, 1);
    expect(totals.grossCents, 1001);
    expect(totals.paidCents, 234);
    expect(totals.balanceCents, 667);
  });
}
