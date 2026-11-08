import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_invoice_task_store.dart';

void main() {
  test('owner-confirmed paid November 2–8 stays historical', () {
    for (final day in [
      '2026-11-02','2026-11-03','2026-11-04',
      '2026-11-05','2026-11-06','2026-11-07','2026-11-08',
    ]) {
      expect(LocalInvoiceTaskStore.currentPayrollDate(day),isFalse,
        reason:'Previously paid invoice labor must stay out of new payroll: $day');
    }
    expect(LocalInvoiceTaskStore.currentPayrollDate('2026-11-09'),isTrue);
    expect(LocalInvoiceTaskStore.currentPayrollDate('2026-11-10'),isTrue);
    expect(LocalInvoiceTaskStore.currentPayrollDate(null),isFalse);
    expect(LocalInvoiceTaskStore.currentPayrollDate(''),isFalse);
  });
}
