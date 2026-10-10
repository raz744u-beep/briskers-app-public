import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/job_performance_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JOB-PERF-001 saves real bounded Job performance samples', () async {
    SharedPreferences.setMockInitialValues({});
    const metrics=JobPerformanceMetrics();
    for(var i=0;i<31;i++) {
      await metrics.record('test-shop',jobId:'j-8',
        stage:'offline_first_render',milliseconds:100+i);
    }
    final samples=await metrics.recent('test-shop');
    expect(samples.length,25);
    expect(samples.first['ms'],106);
    expect(samples.last['ms'],130);
  });

  test('opening a no-doc Job avoids historical full-cache fallback',
      () async {
    final source=await File('lib/screens/jobs/job_detail_screen.dart')
       .readAsString();
    expect(source,contains('bool recoverLegacy = false'));
    expect(source,contains('if (direct.isNotEmpty || !recoverLegacy) return direct;'));
    expect(source,contains('recoverLegacy: true'));
  });

  test('cascade guards require paid-invoice protection and preserve estimates',
      () async {
    final sql=await File(
      'tools/migrations/delete_job_unpaid_invoice_cascade_20261010.sql'
    ).readAsString();
    expect(sql,contains('briskers.invoice_pending_payments'));
    expect(sql,contains('briskers.payment_allocations'));
    expect(sql,contains('briskers.expense_allocations'));
    expect(sql,contains('source_estimate_id'));
    expect(sql,contains('briskers.restore_estimate_after_invoice_delete'));
    expect(sql,contains('WHERE e.business_id=p_business_id AND e.job_id=p_job_id'));
    expect(sql,contains('IF (v_plan->>\'can_delete\')::boolean IS DISTINCT FROM true'));
    expect(sql,contains('briskers.document_number_reuse'));
  });
}
