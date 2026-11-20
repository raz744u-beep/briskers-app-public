import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice Labor row uses TEST full-width header on narrow phones', () {
    final source=File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    final start=source.indexOf('// TEST parity: title and mechanic badges');
    final end=source.indexOf('if (description.isNotEmpty)',start);
    expect(start,greaterThanOrEqualTo(0));
    expect(end,greaterThan(start));
    final layout=source.substring(start,end);
    expect(layout,contains('crossAxisAlignment: CrossAxisAlignment.stretch'));
    expect(layout,contains('alignment: Alignment.centerRight'));
    expect(layout,contains('child: JobTasksAccess('));
    expect(layout,contains('crossAxisAlignment: CrossAxisAlignment.center'));
    expect(source,isNot(contains("Padding(padding:const EdgeInsets.all(12),child:JobTasksAccess(")));

    expect(layout,contains('Qty and Amount occupy their own'));
    expect(layout,isNot(contains('limits.maxWidth>=300')));
  });

  test('saved mechanic name/hours keep inline emphasis and manager remains editable', () {
    final source=File('lib/screens/payroll/job_tasks_access.dart').readAsStringSync();
    expect(source,contains('Row(mainAxisSize:MainAxisSize.max,children:['));
    expect(source,isNot(contains('Icons.engineering_outlined')));
    expect(source,contains('maxLines:1'));
    expect(source,contains('softWrap:false'));
    expect(source,contains('overflow:TextOverflow.ellipsis'));
    expect(source,contains('textAlign:TextAlign.end'));
    expect(source,isNot(contains('alignment:WrapAlignment.end')));
    expect(source,contains('fontSize:15,color:Color(0xFF00897E)'));
    expect(source,contains('fontWeight:FontWeight.w800'));
    expect(source,contains('Icons.edit_outlined'));
    // Settlement locks each allocation inside the manager, not access to it.
    final manager=File('lib/screens/payroll/owner_payroll_screen.dart').readAsStringSync();
    expect(manager,contains('if (paid) const Icon(Icons.lock_outline'));
    expect(manager,contains('Paid · Locked'));
    expect(source,isNot(contains("busy || linePeople.every((p)=>p['paid']==true)")));
    expect(source,contains("'Edit or split mechanic labor'"));
    expect(source,contains("linePeople.map((p) =>"));
    expect(source,contains(").join(' · ')"));
  });
}
