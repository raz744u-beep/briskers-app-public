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
    expect(source, contains("linePeople.map((p) =>"));
    expect(source, contains(").join(' · ')"));
    expect(source, contains("fontSize:15,color:Color(0xFF00897E)"));
    expect(source, contains("'Edit or split mechanic labor'"));
    // A single assigned mechanic must not trap the pencil in the
    // estimated-hours-only dialog; it also needs Add/Split.
    expect(source, isNot(contains('linePeople.length==1')));
    expect(source, contains('? null : open,'));
    expect(source, contains('focusLineId:widget.line'));
  });
}
