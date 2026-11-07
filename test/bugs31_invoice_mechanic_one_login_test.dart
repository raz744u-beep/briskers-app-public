import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice mechanic picker and hour edits use one Owner login', () {
    final source = File('lib/screens/payroll/job_tasks_access.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<LocalPayrollRepository> unlock()');
    final end = source.indexOf('Future<void> chooseMain(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final grant = source.substring(start, end);
    expect(grant, contains('authorizeSession(widget.business)'));
    expect(grant, isNot(contains('authorizeLocal(widget.business)')));
    expect(grant, contains('scope?.debugAllowOwnerView==true'));
    expect(source, contains('Paid mechanic labor is locked.'));
    expect(source, contains('regular_payroll_work_coverage'));
    expect(source, contains('estimated_minutes'));
  });
}
