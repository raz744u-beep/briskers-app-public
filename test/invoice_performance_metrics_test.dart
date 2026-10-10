import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/invoice_performance_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PERF-001 records real bounded timings in shop-local preferences', () async {
    SharedPreferences.setMockInitialValues({});
    const metrics = InvoicePerformanceMetrics();
    for (var i = 0; i < 30; i++) {
      await metrics.record('shop-1', documentId: '6321',
          stage: 'pdf_data', milliseconds: i + 100);
    }
    final samples = await metrics.recent('shop-1');
    expect(samples.length, 25);
    expect(samples.first['ms'], 105);
    expect(samples.last['ms'], 129);
    expect(await metrics.recent('shop-2'), isEmpty);
  });
}
