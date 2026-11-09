import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs cards show nickname and assigned hours once', () async {
    final card = await File('lib/widgets/job_compact_card.dart').readAsString();
    final summary = await File('lib/services/job_task_summary.dart').readAsString();
    expect(card, contains("job['assigned_employee_nickname']"));
    expect(card, contains('displayMechanic'));
    expect(card, contains('person.key'));
    expect(card, contains("person.value / 60"));
    expect(card, isNot(contains('mechanicMinutes!.values.fold')));
    expect(card, isNot(contains('Widget separator()')));
    expect(summary, contains('local_employee_nicknames'));
    expect(summary, contains('n.employee_id=p.employee_id'));
    expect(summary, contains('savedNickname.isNotEmpty'));
  });

  test('Job Details has equal compact controls and bold task and invoice labels',
      () async {
    final access = await File('lib/screens/payroll/job_tasks_access.dart')
        .readAsString();
    final detail = await File('lib/screens/jobs/job_detail_screen.dart')
        .readAsString();
    expect(access, contains("SizedBox(height:50,child:DropdownButtonFormField"));
    expect(access, contains("SizedBox(height:50,child:OutlinedButton.icon"));
    expect(access, contains("EmployeeNicknameStore.displayLabel"));
    expect(access, contains("fontWeight:FontWeight.w800,fontSize:15"));
    expect(detail, contains("fontWeight: FontWeight.w900, color: Color(0xFF07594D)"));
    expect(detail, contains("View Tasks (${progress.total})"));
    expect(detail, contains('_progressRow()'));
  });
}
