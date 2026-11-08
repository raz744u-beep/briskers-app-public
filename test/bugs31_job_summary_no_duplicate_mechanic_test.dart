import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Owner Job summary defers mechanics and hours to the Tasks workspace', () {
    final source=File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final marker=source.indexOf('// In restored Owner Tasks/Payroll');
    final end=source.indexOf('Future<void> _showFindingPhoto(',marker);
    expect(marker,greaterThanOrEqualTo(0));
    expect(end,greaterThan(marker));
    final summary=source.substring(marker,end);
    expect(summary,contains('if (!(OwnerPayrollScreen.enabled && _owner)) ...['));
    expect(summary,contains("label: 'Mechanic'"));
    expect(summary,contains("label: OwnerPayrollScreen.enabled?'Estimated labor':'Planned time'"));
    expect(source,contains('child:JobTasksAccess('));
    // Owner-approved progress row replaces the old duplicate completion card.
    expect(source,contains('if (_owner && OwnerPayrollScreen.enabled) _progressRow()'));
    expect(source,isNot(contains('CompletedWorkSection(business:widget.businessId')));

  });
}
