import 'package:briskers_app/screens/payroll/service_task_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Owner partially-paid planned hours opens numeric IME while mechanic stays locked', (tester) async {
    tester.view.physicalSize = const Size(360,740); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ServiceTaskEditor(
      editing:true, payrollLocked:true,
      jobs:const [{'id':'test-job','title':'Synthetic repair','status':'in_progress'}],
      employees:const [{'id':'test-mechanic','name':'Synthetic mechanic'}],
      initial:ServiceTaskDraft(job:'test-job', description:'Synthetic engine replacement',
        mechanics:[TaskMechanicDraft('test-mechanic',1200,locked:true,hoursEditable:true)],
        start:'2026-11-12',end:'2026-11-19',priority:'Normal',status:'In Progress',treatment:'preserve'),
      save:(_) async {},
    )));
    final hours = find.byKey(const ValueKey('hours-0'));
    await tester.ensureVisible(hours); await tester.pumpAndSettle();
    await tester.tap(hours); await tester.pump();
    expect(tester.testTextInput.isVisible,isTrue);
    expect(tester.widget<TextFormField>(hours).enabled,isNot(false));
    await tester.enterText(hours,'26'); await tester.pump();
    expect(find.text('26'),findsOneWidget);
    final field = tester.widget<EditableText>(find.descendant(of:hours,matching:find.byType(EditableText)));
    expect(field.readOnly,isFalse);
    expect(field.keyboardType,const TextInputType.numberWithOptions(decimal:true));
    expect(tester.takeException(),isNull);
  });
}
