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
  });
}
