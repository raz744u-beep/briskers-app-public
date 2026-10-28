import 'dart:io';

import 'package:briskers_app/tasks_lab/tasks_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Quick filters use a two-row layout, not clipped horizontal scrolling',
      () {
    final source=File('lib/tasks_lab/tasks_workspace.dart').readAsStringSync();
    final quick=source.split('// Two balanced rows on narrow Note 9 screens:')
      .last.split('Expanded(child:_general?_generalView():_serviceView())').first;
    expect(quick,contains("Expanded(child:_picker('Employee'"));
    expect(quick,contains("Expanded(child:_picker('Status'"));
    expect(quick,contains("Expanded(child:_picker(_general?'Category':'Task Type'"));
    expect(quick,contains("Expanded(child:_picker('Sort'"));
    expect(quick,isNot(contains('scrollDirection:Axis.horizontal')));
    expect(source,contains('Text(chosen,maxLines:1,overflow:TextOverflow.ellipsis'));
  });

  testWidgets('All four quick filters fit a 360px Note 9 width on both tabs',
      (tester) async {
    tester.view.devicePixelRatio=1;
    tester.view.physicalSize=const Size(360,800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home:Scaffold(body:TasksWorkspaceLab(
        serviceTasks:const [],
        generalTasks:const [],
        allocationsByLine:const {},
        employeeName:(id)=>id??'Unassigned',
        serviceTaskCard:(task)=>const SizedBox.shrink(),
        onAddService:(){},
        onAddGeneral:(){},
        onGeneralStatus:(id,status) async {},
        onOpenJob:(){},
      )),
    ));
    await tester.pumpAndSettle();
    for(final name in ['Employee','Status','Task Type','Sort',
      'All Types','Newest First']) {
      final item=find.text(name);
      expect(item,findsOneWidget);
      expect(tester.getTopLeft(item).dx,greaterThanOrEqualTo(0));
      expect(tester.getTopRight(item).dx,lessThan(360));
    }
    expect(tester.takeException(),isNull);
    // Sort isn't just legible; the same right-hand control can be operated.
    await tester.tap(find.text('Sort'));
    await tester.pumpAndSettle();
    expect(find.text('Oldest First'),findsOneWidget);
    await tester.tap(find.text('Oldest First'));
    await tester.pumpAndSettle();
    expect(find.text('Oldest First'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('general-tasks-tab')));
    await tester.pumpAndSettle();
    for(final name in ['Employee','Status','Category','Sort',
      'All Categories','Oldest First']) {
      final item=find.text(name);
      expect(item,findsOneWidget);
      expect(tester.getTopLeft(item).dx,greaterThanOrEqualTo(0));
      expect(tester.getTopRight(item).dx,lessThan(360));
    }
    expect(tester.takeException(),isNull);
  });
}
