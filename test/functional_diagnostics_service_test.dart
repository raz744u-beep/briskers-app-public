import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/services/functional_diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('functional diagnostics sandbox passes all workflow checks', () async {
    SharedPreferences.setMockInitialValues({});
    const service = BriskersFunctionalDiagnosticsService();

    final report = await service.run();

    expect(report.checks, hasLength(16));
    expect(report.passed, 16);
    expect(report.warnings, 0);
    expect(report.failed, 0);
    expect(report.checks.map((c) => c.id), containsAll(['FUNC-013', 'FUNC-014', 'FUNC-015', 'FUNC-016']));
  });
}
