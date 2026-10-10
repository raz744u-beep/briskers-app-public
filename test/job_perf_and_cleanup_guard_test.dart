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

  test('owner cascade remains an explicit server-side opt-in', () async {
    final source=await File('lib/services/briskers_api.dart').readAsString();
    expect(source,contains('briskers_job_delete_plan'));
    expect(source,contains('briskers_delete_job_with_unpaid_v1'));
    expect(source,contains('briskers_delete_invoice_managed_v1'));
    expect(source,contains('deleteJob: false'));
  });
}
