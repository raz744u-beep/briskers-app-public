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
    expect(card,contains(r"'Done · $stamp'"));
    expect(card,isNot(contains('In progress · Editable')));
    expect(card,isNot(contains('Planned · Editable')));
    expect(card,isNot(contains('Completed · read-only')));
    expect(card,isNot(contains('TextDecoration.lineThrough')));
  });

  test('Task card uses tap to expand and pencil without a redundant arrow', () {
    final source = File('lib/tasks_lab_main.dart').readAsStringSync();
    final card = source.split('Widget _taskCard(').last
      .split('Future<void> _editTask(').first;
    expect(card, contains('onTap: () => setState(() {'));
    expect(card, contains('expandedTaskKeys.remove(id)'));
    expect(card, contains('expandedTaskKeys.add(id)'));
    expect(card, contains("tooltip: 'Edit task'"));
    expect(card, contains('Icons.edit_outlined'));
    // Pencil is the final child in the card header row, flush right inside
    // its existing outer padding: removing the chevron must not leave a slot.
    expect(RegExp(r'width:\s*34,\s*height:\s*38\)\),\s*\],\s*\),')
      .hasMatch(card), isTrue,
      reason: 'Edit pencil must be the last right-side header control');
    expect(card, isNot(contains('Icons.expand_less')));
    expect(card, isNot(contains('Icons.expand_more')));
    expect(card, isNot(contains('Icons.chevron_right')));
  });

  test('Mechanic names bold and hours regular in both task sections', () {
    final main=File('lib/tasks_lab_main.dart').readAsStringSync();
    final card=main.split('Widget _taskCard(').last
      .split('Future<void> _editTask(').first;
    final controls=main.split('Widget _mechanicProgressControls(').last
      .split('Map<String, dynamic>? _firstCompletion(').first;
    expect(card,contains('Expanded(child: Text(credit.mechanics,'));
    expect(card,contains('fontSize: 13.5,\n'
      '                              fontWeight: FontWeight.w700,'));
    expect(card,contains('Text(credit.hours,\n'
      '                            style: const TextStyle(fontSize: 12.5,\n'
      '                              fontWeight: FontWeight.w400,'));
    expect(controls,contains('Text(_employeeName(mechanicId)'));
    expect(controls,contains('fontWeight:FontWeight.w700'));
    expect(controls,contains('final statusLabel=current=='));
    expect(controls,contains("fontSize:13,"));
    expect(controls,contains("fontWeight:FontWeight.w700,color:statusColor"));
    expect(controls,contains("fontSize:12,"));
    expect(controls,contains("label:const Text('Mark Done'"));
    expect(controls,contains("OutlinedButton.icon("));
    expect(controls,contains("mechanic-status-"));
  });

  test('Approved allocation footer is bold original gray with total', () {
    final main=File('lib/tasks_lab_main.dart').readAsStringSync();
    final card=main.split('Widget _taskCard(').last
      .split('Future<void> _editTask(').first;
    expect(card,contains("if (splitCount > 1)"));
    expect(card,contains(r"· Total: ${credit.hours}"));
    expect(card,contains('style: const TextStyle(fontSize: 12.5,\n'
      '                            fontWeight: FontWeight.w700,\n'
      '                            color: Color(0xFF526273))'));
    expect(card,contains('_completedAssignment(record)'));
    expect(card,contains('_laborAssignment(task)'));
    // Names/hours in the mechanic rows are not changed by this request.
    expect(card,contains('Text(credit.hours,'));
  });

  test('Both task tabs and status filters share progress terminology', () {
    final source=File('lib/tasks_lab/tasks_workspace.dart').readAsStringSync();
    final profile=File('lib/tasks_lab/employee_payroll_profile.dart')
      .readAsStringSync();
    final main=File('lib/tasks_lab_main.dart').readAsStringSync();
    final weekly=File('lib/tasks_lab/weekly_labor_review_screen.dart')
      .readAsStringSync();
    expect(weekly,contains("case 'done': return 'Done';"));
    expect(weekly,contains("default: return 'Not Started';"));
    expect(weekly,isNot(contains("return 'Complete';")));
    expect(weekly,isNot(contains("return 'Planned';")));
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
