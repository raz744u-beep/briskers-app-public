import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/services/functional_diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('functional diagnostics sandbox passes all workflow checks', () async {
    SharedPreferences.setMockInitialValues({});
    const service = BriskersFunctionalDiagnosticsService();

    final report = await service.run();

    expect(report.checks, hasLength(23));
    final ids = report.checks.map((check) => check.id).toSet();
    expect(ids, containsAll(<String>['FUNC-013', 'FUNC-014', 'FUNC-015', 'FUNC-016', 'FUNC-017', 'FUNC-018', 'FUNC-019', 'FUNC-020', 'FUNC-021', 'FUNC-JOB-CREATE']));
    expect(ids.length, report.checks.length);
    expect(report.passed, 23);
    expect(report.warnings, 0);
    expect(report.failed, 0);
  });
}
