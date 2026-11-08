import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TEST global Tasks preserves white job task cards and unclipped list', () {
    final source = File('lib/screens/payroll/tasks_workspace.dart').readAsStringSync();
    expect(source, contains('color: Colors.white'));
    expect(source, contains('widget.serviceTaskCard(task)'));
    expect(source, contains('Expanded(child:ClipRect(child:'));
    expect(source, contains(r'Invoice #$invoice'));
    expect(source, contains('widget.onRecoverHistory!()'));
  });

  test('both TEST task circles reflect saved In Progress and Done states', () {
    final screen=File('lib/screens/payroll/owner_payroll_screen.dart').readAsStringSync();
    expect(screen, contains("case 'In Progress':"));
    expect(screen, contains('return Icons.timelapse;'));
    expect(screen, contains('_workStatusIcon(state)'));
    expect(screen, contains('_workStatusIcon(state, inner: true)'));
    expect(screen, contains('_workStatusColor(state)'));
    expect(screen, contains('case \'Done\':'));
  });

  test('Job labor completion stays next to In Progress and off nav bar', () {
    final source=File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();
    expect(source, contains("if (state == 'In Progress')"));
    expect(source, contains("const Expanded(child: Text('In Progress'"));
    expect(source, contains('padding: const EdgeInsets.fromLTRB(16, 16, 16, 112)'));
    expect(source, contains('_recordTaskProgress(row,markDone:true)'));
  });

  test('approved small hour badges are prominent on task and mechanic rows', () {
    final screen=File('lib/screens/payroll/owner_payroll_screen.dart').readAsStringSync();
    expect(screen, contains('Widget _compactPlannedHours(double hours)'));
    expect(screen, contains('fontSize: 13.5'));
    expect(screen, contains('fontWeight: FontWeight.w800'));
    expect(screen.split('_compactPlannedHours(planned)').length, 3);
  });

  test('Mark Done uses assigned hours once, without additional dialogs', () {
    final screen = File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();
    final start = screen.indexOf('Future<void> _recordTaskProgress(');
    final end = screen.indexOf('Future<void> _editEstimated(', start);
    final action = screen.substring(start, end);
    expect(action, contains("final assignedMinutes = row['estimated_minutes']"));
    expect(action, contains("next == 'Done' && assignedMinutes <= 0"));
    expect(action, contains("next == 'Done' ? assignedMinutes : previousMinutes"));
    expect(action, contains('completedMinutes, completedMinutes'));
    expect(action, contains('_taskEditRepository.recordAllocatedTime('));
    expect(action, contains("final next = markDone ? 'Done'"));
    expect(action, isNot(contains('payrollLanInput(')));
    expect(action, isNot(contains('Credited mechanic labor')));
  });

  test('starting work never earns the assigned hours', () {
    final screen = File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();
    final start = screen.indexOf('Future<void> _recordTaskProgress(');
    final end = screen.indexOf('Future<void> _editEstimated(', start);
    final action = screen.substring(start, end);
    expect(action, contains("row['state'] == 'Open' ? 'In Progress' : 'Done'"));
    expect(action, contains("next == 'Done' ? assignedMinutes : previousMinutes"));
    expect(action, contains("if (row['state'] == 'Done' || (row['paid_minutes'] as int? ?? 0) > 0) return;"));
  });

  test('direct Mark Done from Open keeps paid labor locked', () {
    final source = File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();
    expect(source, contains("label:const Text('Mark Done')"));
    expect(source, contains('_recordTaskProgress(row,markDone:true)'));
    expect(source, contains("final canProgress = !paid && !conflict && !removed && !_busy;"));
    expect(source, contains("color: const Color(0xFFF0F5F8)"));
    expect(source, contains("label:const Text('Mark Done')"));
    expect(source, contains('Assign mechanic hours with the pencil before marking Done.'));
  });

}
