import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('job cards retain status colors and separate tap navigation from long press',()async{
  final source=await File('lib/screens/payroll/job_scoped_tasks.dart').readAsString();
  final card=await File('lib/screens/payroll/approved_tasks_ui.dart').readAsString();
  expect(source,contains('ApprovedTaskListCard('));
  expect(source,contains('onTap: () => widget.onOpenTask?.call(row, general)'));
  expect(source,contains('onLongPress: () => _longPress(key, row, general)'));
  expect(card,contains('TaskStatusPill(status, icon: !jobScoped)'));
  expect(card,contains('TaskPriorityPill('));
  expect(card,contains('Icons.chevron_right'));
 });
}
