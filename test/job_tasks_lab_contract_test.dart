import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/local_job_tasks_lab_store.dart';

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
}
