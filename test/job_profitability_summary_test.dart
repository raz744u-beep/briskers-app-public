import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/services/job_profitability_summary.dart';

void main() {
  Map<String, dynamic> totals({
    num revenue = 1000,
    num tax = 80,
    num direct = 400,
    num labor = 200,
  }) => {
    'revenue': revenue,
    'sales_tax': tax,
    'gross_billed': revenue + tax,
    'direct_cost': direct,
    'mechanic_cost': labor,
    'total_cost': direct + labor,
  };

  test('tax is excluded once and profit is computed from pre-tax revenue', () {
    final data = totals()..['profit'] = 480; // A stale gross-based projection.
    final result = JobProfitabilitySummary.fromRpc(data)!;
    expect(result.revenue, 1000);
    expect(result.salesTax, 80);
    expect(result.totalCost, 600);
    expect(result.profit, 400);
    expect(result.marginPercent, 40);
    expect(data['profit'], 480); // Read-only projection preserves the input.
  });

  test('mixed taxable/non-taxable aggregate is not reverse-taxed', () {
    final result = JobProfitabilitySummary.fromRpc(
      totals(revenue: 1200, tax: 80, direct: 600),
    )!;
    expect(result.profit, 400);
    expect(result.marginPercent, closeTo(100 / 3, 0.000001));
  });

  test('discount-adjusted document net amount remains authoritative', () {
    final result = JobProfitabilitySummary.fromRpc(
      totals(revenue: 900, tax: 72),
    )!;
    expect(result.profit, 300);
    expect(result.revenue, 900);
  });

  test('zero-tax invoices have the same pre-tax formula', () {
    final result = JobProfitabilitySummary.fromRpc(totals(tax: 0))!;
    expect(result.profit, 400);
    expect(result.salesTax, 0);
  });

  test('gross fallback subtracts tax only when revenue is absent', () {
    final data = totals()..remove('revenue');
    expect(JobProfitabilitySummary.fromRpc(data)!.profit, 400);
    data['revenue'] = 0;
    final zero = JobProfitabilitySummary.fromRpc(data)!;
    expect(zero.revenue, 0);
    expect(zero.profit, -600);
    expect(zero.marginPercent, isNull);
  });

  test(
    'customer-covered processor fee and unpaid balance are not job costs',
    () {
      final data = totals()
        ..['processor_fee'] = 20
        ..['warranty_processor_fee'] = 20
        ..['pending_payment'] = 300
        ..['balance_due'] = 500;
      expect(JobProfitabilitySummary.fromRpc(data)!.profit, 400);
    },
  );

  test(
    'processing cost already included in authoritative total is counted once',
    () {
      final data = totals()
        ..['total_cost'] = 620
        ..['processor_fee'] = 20;
      final result = JobProfitabilitySummary.fromRpc(data)!;
      expect(result.totalCost, 620);
      expect(result.profit, 380);
    },
  );

  test('already adjusted revenue and refunded costs retain their signs', () {
    // Tests arithmetic on supplied aggregates, not backend credit-note support.
    final adjusted = JobProfitabilitySummary.fromRpc(
      totals(revenue: 800, tax: 64, direct: 300),
    )!;
    expect(adjusted.profit, 300);
    final returned = JobProfitabilitySummary.fromRpc(
      totals(revenue: -100, tax: -8, direct: -30, labor: 0),
    )!;
    expect(returned.profit, -70);
    expect(returned.marginPercent, isNull);
  });

  test('negative profit and cents are preserved', () {
    final result = JobProfitabilitySummary.fromRpc(
      totals(revenue: 99.99, tax: 8, direct: 100, labor: 50),
    )!;
    expect(result.profit, -50.01);
    expect(result.marginPercent, lessThan(0));
  });

  test('numeric strings work while missing/nonfinite amounts fail closed', () {
    final data = totals().map((key, value) => MapEntry(key, '$value'));
    expect(JobProfitabilitySummary.fromRpc(data)!.profit, 400);
    for (final value in [double.nan, double.infinity, 'bad']) {
      expect(
        JobProfitabilitySummary.fromRpc({...totals(), 'revenue': value}),
        isNull,
      );
    }
    expect(JobProfitabilitySummary.fromRpc({}), isNull);
  });

  test('invalid authoritative total cost cannot become partial costs', () {
    final data = totals()..['total_cost'] = 'unavailable';
    expect(JobProfitabilitySummary.fromRpc(data), isNull);
  });
}
