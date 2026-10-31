import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const business = 'briskers-tasks-test-only';
  const job = 'lab-job-richard-j24';

  test('Legacy Note 9 NOT NULL estimated_minutes accepts new General Tasks',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalJobTasksLabStore(db);
    try {
      // Mimics the pre-2026 General Tasks table on the TEST handset.
      // Unlike the current schema, it has mandatory estimated_minutes.
      await db.customStatement('''
        CREATE TABLE local_shop_tasks_lab (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          business_id TEXT NOT NULL, description TEXT NOT NULL,
          employee_id TEXT, status TEXT NOT NULL DEFAULT 'planned',
          estimated_minutes INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.customStatement(
        "INSERT INTO local_shop_tasks_lab "
        "(business_id,description,employee_id,status,estimated_minutes,created_at) "
        "VALUES ('briskers-tasks-test-only','Existing test chore',"
        "'lab-chris','planned',25,1761510000000)");
      await store.addShopTask(
        businessId:business, description:'Clean break room',
        employeeId:'lab-adam',category:'Cleaning',
        dueDate:DateTime(2026,10,30));
      final entries=await store.shopTasks(business);
      expect(entries,hasLength(2));
      expect(entries.any((x)=>x['description']=='Existing test chore'),isTrue);
      final previous=await db.customSelect(
        "SELECT estimated_minutes FROM local_shop_tasks_lab "
        "WHERE description='Existing test chore'").getSingle();
      expect(previous.read<int>('estimated_minutes'),25);
      final newRow=await db.customSelect(
        "SELECT estimated_minutes FROM local_shop_tasks_lab "
        "WHERE description='Clean break room'").getSingle();
      expect(newRow.read<int>('estimated_minutes'),0);
      expect(entries.singleWhere((r)=>r['description']=='Clean break room')
        ['category'],'Cleaning');
      expect(entries.singleWhere((r)=>r['description']=='Clean break room')
        ['due_at'],DateTime(2026,10,30).millisecondsSinceEpoch);
      await LocalJobTasksLabStore.ensureTables(db);
      expect((await store.shopTasks(business)).length,2);
    } finally {
      await db.close();
    }
  });

  test('Move zero-hour recheck to General Tasks atomically on older schema',
      () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final store=LocalJobTasksLabStore(db);
    try {
      await db.customStatement('''
        CREATE TABLE local_shop_tasks_lab (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          business_id TEXT NOT NULL, description TEXT NOT NULL,
          employee_id TEXT, status TEXT NOT NULL DEFAULT 'planned',
          estimated_minutes INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      final line=await store.addRecheckTask(
        businessId:business,jobId:job,
        description:'Clean up your desk!',hours:0,
        employeeId:'lab-chris');
      expect((await store.list(business,job))
        .any((r)=>r['line_id']==line),isTrue);
      await store.moveUnpaidRecheckToShop(
        businessId:business,jobId:job,lineId:line);
      final entries=await store.shopTasks(business);
      expect(entries,hasLength(1));
      expect(entries.single['description'],'Clean up your desk!');
      expect(entries.single['employee_id'],'lab-chris');
      expect(entries.single['status'],'planned');
      expect((await store.list(business,job))
        .any((r)=>r['line_id']==line),isFalse);
      final legacy=await db.customSelect(
        'SELECT estimated_minutes FROM local_shop_tasks_lab').getSingle();
      expect(legacy.read<int>('estimated_minutes'),0);
      // A paid/allocated original recheck may not be moved or erased.
      final protected=await store.addRecheckTask(
        businessId:business,jobId:job,
        description:'Actual paid repair',hours:1.0,
        employeeId:'lab-chris');
      await expectLater(store.moveUnpaidRecheckToShop(
        businessId:business,jobId:job,lineId:protected),throwsStateError);
      expect((await store.list(business,job))
        .any((r)=>r['line_id']==protected),isTrue);
      expect((await store.shopTasks(business)),hasLength(1));
    } finally { await db.close(); }
  });

  test('Edit and Lead sheets keep Save above the Android navigation bar', () {
    final main=File('lib/tasks_lab_main.dart').readAsStringSync();
    final edit=main.split('Future<void> _editTask(').last
      .split('Future<void> _editEmployeeNames()').first;
    final lead=main.split('Future<void> _assignLeadMechanic()').last
      .split('Widget _customerPage()').first;
    for(final modal in [edit,lead]) {
      expect(modal,contains('MediaQuery.viewPaddingOf('));
      expect(modal,contains('MediaQuery.viewInsetsOf('));
      expect(modal,contains('.bottom + 30'));
    }
    expect(lead,contains('isScrollControlled: true'));
    expect(lead,contains('SingleChildScrollView('));
  });
}
