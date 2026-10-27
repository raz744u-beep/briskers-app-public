import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Unified employee page retains the four agreed top tabs', () {
    final source = File('lib/tasks_lab/employee_payroll_profile.dart')
      .readAsStringSync();
    expect(source, contains("Tab(text: 'Tasks')"));
    expect(source, contains("Tab(text: 'Payroll')"));
    expect(source, contains("Tab(text: 'Reports')"));
    expect(source, contains("Tab(text: 'Taxes')"));
    expect(source, contains('isScrollable: true'));
    expect(source, contains("'Details'"));
    expect(source, contains('WeeklyLaborReviewLab('));
    expect(source, contains('embedded: true'));
    expect(source, contains('onCancel: () => Navigator.of(context).pop()'));
    expect(source, contains('onPaymentSaved: _afterPaymentSaved'));
    expect(source, contains('employee-payroll-period-dropdown'));
    expect(source, isNot(contains('Widget _weekPicker()')));
    expect(source, contains('bool _advanceExpanded = false;'));
    expect(source, isNot(contains('_banner()')));
    expect(File('lib/tasks_lab/payroll_history_panel.dart').readAsStringSync(),
      contains('reports-fixed-payment-total'));
    expect(File('lib/tasks_lab/payroll_history_panel.dart').readAsStringSync(),
      contains("'Year to Date'"));
    final payroll = source.split('Widget _payrollTab() {').last
      .split('Widget _advancePanel() {').first;
    expect(payroll, isNot(contains('Payment History')));
    expect(payroll, contains('_advancePanel()'));
    final reports = source.split('Widget _reportsTab() {').last
      .split('Widget _taxesTab()').first;
    expect(reports, contains('LabPayrollHistoryPanel('));
    expect(File('lib/tasks_lab/payroll_history_panel.dart').readAsStringSync(),
      contains('Total paid'));
  });

  test('Weekly Labor screen fixes summary/actions while only tasks scroll', () {
    final source = File('lib/tasks_lab/weekly_labor_review_screen.dart')
      .readAsStringSync();
    expect(source, contains('Week of '));
    expect(source, contains('Select All'));
    expect(source, contains('weekly-labor-tasks-scroll-only'));
    expect(source, contains('weekly-labor-fixed-footer'));
    expect(source, contains('_compactWeekSelector()'));
    expect(source, contains('height: 43'));
    expect(source, contains('widget.embedded ? null : AppBar('));
    expect(source, contains('Timer(const Duration(seconds: 10)'));
    expect(source, contains('lab_weekly_labor_notes'));
    expect(source, contains('Widget build(BuildContext context)'));
    expect(source, contains('Weekly labor times'));
    expect(source, contains('Icons.engineering_outlined'));

    expect(source, contains("Text('Cancel')"));
    expect(source, contains("Text('Verify Payment')"));
    expect(source, contains('Tasks selected'));
    expect(source, contains('Selected this week'));
    expect(source, contains('Available hours'));
    expect(source, contains('Payment note (optional)'));
    expect(source, isNot(contains('Final amount override (TEST)')));
    expect(source, contains('lab_payroll_task_payments'));
    expect(source, contains('lab_weekly_payroll_drafts'));
    expect(source, contains('Payment not saved'));
    expect(source, isNot(contains('Supabase')));
    expect(source, isNot(contains('BriskersApi')));
  });

  test('Advance and repayment amounts select their full value when tapped', () {
    final source = File('lib/tasks_lab/employee_payroll_profile.dart')
        .readAsStringSync();
    final advancePanel = source.split('Widget _advancePanel() {').last
        .split('Widget _reportsTab()').first;
    expect(advancePanel, contains("labelText: 'Original amount owed'"));
    expect(advancePanel, contains("labelText: 'Amount'"));
    expect(advancePanel, contains('controller: _opening,'));
    expect(advancePanel, contains('controller: _repayment,'));
    expect(advancePanel, contains('onTapAlwaysCalled: true'));
    expect(advancePanel, contains('onTap: () => _selectAmount(_opening),'));
    expect(advancePanel, contains('onTap: () => _selectAmount(_repayment),'));
    expect(source, contains('controller.selection = TextSelection('));
    expect(source, contains('baseOffset: 0, extentOffset: controller.text.length'));
  });

  test('Legacy Payroll TEST ledger is no longer the employee landing', () {
    final source = File('lib/tasks_lab_main.dart').readAsStringSync();
    expect(source, isNot(contains("_sectionHeader('Payroll TEST ledger'")));
    expect(source, contains('LabPayrollOverviewScreen('));
    expect(source, contains('onOpenProfile:'));
    expect(source, contains('initialTab: 0'));
    expect(source, contains('BriskersColors.jobs'));
  });
}
