import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/services/functional_diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('functional diagnostics sandbox passes all workflow checks', () async {
    SharedPreferences.setMockInitialValues({});
    const service = BriskersFunctionalDiagnosticsService();

    final report = await service.run();

    expect(report.checks, hasLength(13));
    expect(report.passed, 13);
    expect(report.warnings, 0);
    expect(report.failed, 0);
    expect(report.checks.map((check) => check.id), contains('FUNC-019'));
  });
}
