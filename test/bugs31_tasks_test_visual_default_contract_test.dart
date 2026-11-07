import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TEST global Tasks preserves white job task cards and unclipped list', () {
    final source = File('lib/screens/payroll/tasks_workspace.dart').readAsStringSync();
    expect(source, contains('color: Colors.white'));
    expect(source, contains('child: widget.serviceTaskCard(task)'));
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

  test('completion suggests assigned hours instead of zero actual time', () {
    final source = File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<void> _recordTaskProgress(');
    final end = source.indexOf('Future<void> _editEstimated(', start);
    final progress = source.substring(start, end);
    expect(progress, contains('final priorActual ='));
    expect(progress, contains("row['estimated_minutes'] as int? ?? 0"));
    expect(progress, contains('priorActual > 0 ? priorActual : estimated'));
    expect(progress, contains('initialValue:(suggestedActual/60).toStringAsFixed(2)'));
    expect(progress, contains('suggested from assigned hours; edit if different'));
    expect(progress, contains('if (next == \'Done\')'));
    expect(progress, contains('initialValue:(credited/60).toStringAsFixed(2)'));
  });

  test('mechanic time default is planning, never earned on Start', () {
    final screen = File('lib/screens/payroll/owner_payroll_screen.dart').readAsStringSync();
    final start = screen.indexOf('Future<void> _recordTaskProgress(');
    final end = screen.indexOf('Future<void> _editEstimated(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final progress = screen.substring(start, end);
    expect(progress, contains("next == 'Done' && plannedMinutes > 0"));
    expect(progress, contains("initialValue:(credited/60).toStringAsFixed(2)"));
    expect(progress, contains('_taskEditRepository.recordAllocatedTime('));
    expect(progress, contains("final next = markDone ? 'Done'"));
  });
  test('direct Mark Done from Open keeps paid labor locked', () {
    final source = File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsStringSync();
    expect(source, contains("label:const Text('Mark Done')"));
    expect(source, contains('_recordTaskProgress(row,markDone:true)'));
    expect(source, contains("final canProgress = !paid && !conflict && !removed && !_busy;"));
    expect(source, contains("color: const Color(0xFFF0F5F8)"));
    expect(source, contains("label:const Text('Mark Done')"));
    expect(source, contains('Credited mechanic labor'));
  });

}
