import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:drift/native.dart';

void main() {
  test('Only actual labor invoice lines are mapped to tasks', () {
    final invoice = <String, dynamic>{
      'kind': 'invoice',
      'lines': [
        {'id': 'labor-a', 'name': 'Labor',
         'line_kind': 'item', 'description': 'Valve cover replacement',
         'quantity': 4.0},
        {'id': 'labor-b', 'name': 'Transmission repair',
         'line_kind': 'labor', 'description': 'Transmission and differential',
         'quantity': 5.5},
        {'id': 'part-a', 'name': 'Valve cover gasket',
         'line_kind': 'part', 'quantity': 1},
        {'id': 'discount', 'name': 'Labor', 'line_kind': 'discount'},
      ],
    };
    final tasks = LocalJobTasksLabStore.laborLines(invoice);
    expect(tasks.map((row) => row['id']).toList(),
        ['labor-a', 'labor-b']);
    expect(LocalJobTasksLabStore.laborLines({
      ...invoice, 'kind': 'estimate'
    }), isEmpty);
  });

  test('Employee nicknames use override, otherwise first name', () {
    expect(LocalJobTasksLabStore.displayName('Kamerron Smith', 'Kam'),
        'Kam');
    expect(LocalJobTasksLabStore.displayName('Chris Jones', null),
        'Chris');
  });

  test('Prototype has no server writes and keeps tasks separate', () {
    final store=File('lib/services/local_job_tasks_lab_store.dart')
        .readAsStringSync();
    final screen=File('lib/screens/jobs/job_tasks_lab_screen.dart')
        .readAsStringSync();
    expect(store, contains('local_job_tasks_lab'));
    expect(store, contains('completed_at'));
    expect(store, contains('employee_id'));
    expect(store, contains('source_missing'));
    expect(store, isNot(contains('sync_outbox')));
    expect(screen, contains('Assign'));
    expect(screen, contains('Work Log'));
    expect(screen, contains('Not synced to shop or payroll.'));
  });
  test('Local assignments survive invoice refresh and stay scoped to job', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    try {
      final invoice = <String,dynamic>{
        'kind':'invoice', 'lines': [
          {'id':'cover-labor','name':'Labor',
           'line_kind':'labor','description':'Valve cover work','quantity':4},
          {'id':'trans-labor','name':'Labor',
           'line_kind':'labor','description':'Transmission repair','quantity':5},
        ]};
      await store.reconcileDocument(businessId:'shop',jobId:'richard-job',
        documentId:'invoice',laborLines:LocalJobTasksLabStore.laborLines(invoice));
      var tasks = await store.list('shop','richard-job');
      expect(tasks.length,2);
      expect(tasks.every((t)=>t['status']=='planned'),isTrue);
      await store.editTask(
        businessId:'shop',jobId:'richard-job',documentId:'invoice',
        lineId:'cover-labor',employeeId:'kam-id',editEmployee:true,
        status:'done',description:'Replaced valve covers',editDescription:true,
        hours:4,editHours:true,
      );
      await store.editTask(
        businessId:'shop',jobId:'richard-job',documentId:'invoice',
        lineId:'trans-labor',employeeId:'chris-id',editEmployee:true,
        status:'in_progress',hours:5,editHours:true,
      );
      await store.saveNickname('shop','kam-id','Kam');
      await store.saveNickname('shop','chris-id','Chris');
      expect(await store.nicknames('shop'),
        {'kam-id':'Kam','chris-id':'Chris'});
      // A changed invoice description is not allowed to overwrite manual
      // completed-work wording, mechanic identity or timestamp.
      invoice['lines'] = [
        {'id':'cover-labor','name':'Labor','line_kind':'labor',
         'description':'Updated invoice billing text','quantity':6}
      ];
      await store.reconcileDocument(businessId:'shop',jobId:'richard-job',
        documentId:'invoice',laborLines:LocalJobTasksLabStore.laborLines(invoice));
      tasks=await store.list('shop','richard-job');
      final cover=tasks.singleWhere((t)=>t['line_id']=='cover-labor');
      final trans=tasks.singleWhere((t)=>t['line_id']=='trans-labor');
      expect(cover['employee_id'],'kam-id');
      expect(cover['source_description'],'Updated invoice billing text');
      expect(cover['custom_description'],'Replaced valve covers');
      expect(cover['payroll_hours'],4.0);
      expect(cover['status'],'done');
      expect(cover['completed_at'],isA<int>());
      expect(trans['employee_id'],'chris-id');
      expect(trans['source_missing'],1);
      expect(await store.list('other-shop','richard-job'),isEmpty);
      expect(await store.list('shop','unrelated-job'),isEmpty);
    } finally {
      await db.close();
    }
  });

}
