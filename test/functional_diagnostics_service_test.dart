import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/services/functional_diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('functional diagnostics sandbox passes all workflow checks', () async {
    SharedPreferences.setMockInitialValues({});
    const service = BriskersFunctionalDiagnosticsService();

    final report = await service.run();

    expect(report.checks, hasLength(15));
    final ids = report.checks.map((check) => check.id).toSet();
    expect(ids, containsAll(<String>['FUNC-019', 'FUNC-020', 'FUNC-021']));
    expect(ids.length, report.checks.length);
    expect(report.passed, 15);
    expect(report.warnings, 0);
    expect(report.failed, 0);
  });
}
