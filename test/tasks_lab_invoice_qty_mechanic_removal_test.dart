import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:briskers_app/tasks_lab/fixture.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer invoice Qty is independent from mechanic allocations',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    const shop = BriskersLabFixture.businessId;
    const job = BriskersLabFixture.jobId;
    const invoice = BriskersLabFixture.invoiceId;
    try {
      Future<void> reconcile() => store.reconcileDocument(
        businessId: shop, jobId: job, documentId: invoice,
        laborLines: LocalJobTasksLabStore.laborLines(BriskersLabFixture.invoice));
      await reconcile();
      await store.saveAllocations(businessId: shop, jobId: job,
        documentId: invoice, lineId: 'lab-transmission',
        hoursByEmployee: {'lab-chris': 1.0, 'lab-kam': 0.5});
      await store.saveTestBilledLaborHours(
        businessId: shop, jobId: job, documentId: invoice,
        lineId: 'lab-transmission', hours: 2.5);
      await reconcile();
      var task = (await store.list(shop, job))
        .singleWhere((row) => row['line_id'] == 'lab-transmission');
      expect(task['billed_hours_override'], 2.5);
      expect(task['source_invoice_hours'], 1.5);
      expect((await store.allocations(businessId: shop, jobId: job,
        documentId: invoice, lineId: 'lab-transmission')).length, 2);
      // Removing one mechanic leaves the other and does not change billed Qty.
      await store.saveAllocations(businessId: shop, jobId: job,
        documentId: invoice, lineId: 'lab-transmission',
        hoursByEmployee: {'lab-kam': 0.5});
      task = (await store.list(shop, job))
        .singleWhere((row) => row['line_id'] == 'lab-transmission');
      expect(task['billed_hours_override'], 2.5);
      expect(task['payroll_hours'], 0.5);
      expect((await store.allocations(businessId: shop, jobId: job,
        documentId: invoice, lineId: 'lab-transmission'))
        .single['employee_id'], 'lab-kam');
    } finally {
      await db.close();
    }
  });
}
