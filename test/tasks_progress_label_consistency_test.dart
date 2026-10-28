import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Service task card uses Not Started, In Progress and Done only', () {
    final main=File('lib/tasks_lab_main.dart').readAsStringSync();
    final card=main.split('Widget _taskCard(').last
      .split('Future<void> _editTask(').first;
    expect(card,contains("? 'In Progress'"));
    expect(card,contains(": 'Not Started'"));
    expect(card,contains("? 'Done'"));
    expect(card,contains("'Done · $stamp'"));
    expect(card,isNot(contains('In progress · Editable')));
    expect(card,isNot(contains('Planned · Editable')));
    expect(card,isNot(contains('Completed · read-only')));
    expect(card,isNot(contains('TextDecoration.lineThrough')));
  });

  test('Both task tabs and status filters share progress terminology', () {
    final source=File('lib/tasks_lab/tasks_workspace.dart').readAsStringSync();
    final profile=File('lib/tasks_lab/employee_payroll_profile.dart')
      .readAsStringSync();
    final main=File('lib/tasks_lab_main.dart').readAsStringSync();
    expect(source,contains("case 'done': return 'Done';"));
    expect(source,contains("default: return 'Not Started';"));
    expect(source,contains("case 'in_progress': return 'In Progress';"));
    expect(source,contains("(_status == 'Active' && status != 'Done')"));
    expect(source,contains(
      "['Active','All','Not Started','In Progress','Done']"));
    expect(source,isNot(contains("'Planned'")));
    expect(source,isNot(contains("'Complete'")));
    expect(profile,contains("task['status']=='done'?'Done'"));
    expect(profile,contains("'In Progress':'Not Started'"));
    expect(main,contains("status=='done' ? 'Done'"));
    expect(main,contains("'In Progress' : 'Not Started'"));
    expect(main,contains("title: Text('Done · '+completed.length.toString())"));
    // Persisted SQLite codes remain stable; this is display-only.
    expect(source,contains("value:'planned'"));
    expect(source,contains("value:'done'"));
  });
}
