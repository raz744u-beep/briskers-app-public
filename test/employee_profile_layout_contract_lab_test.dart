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
    expect(source, contains('bool _advanceExpanded = false;'));
    expect(source, isNot(contains('_banner()')));
    expect(source, contains('reports-fixed-payment-total'));
    expect(source, contains("String _reportRange = 'Year to Date'"));
    final payroll = source.split('Widget _payrollTab() {').last
      .split('Widget _advancePanel() {').first;
    expect(payroll, isNot(contains('Payment History')));
    expect(payroll, contains('_advancePanel()'));
    final reports = source.split('Widget _reportsTab() {').last
      .split('Widget _taxesTab()').first;
    expect(reports, contains('Payment History'));
    expect(reports, contains('Total paid'));
  });

  test('Weekly Labor screen fixes summary/actions while only tasks scroll', () {
    final source = File('lib/tasks_lab/weekly_labor_review_screen.dart')
      .readAsStringSync();
    expect(source, contains('Weekly Labor Times'));
    expect(source, contains('Week of '));
    expect(source, contains('Select All'));
    expect(source, contains('weekly-labor-tasks-scroll-only'));
    expect(source, contains('weekly-labor-fixed-footer'));
    expect(source, contains("Text('Cancel')"));
    expect(source, contains("Text('Save Draft (TEST)')"));
    expect(source, contains('Final amount override'));
    expect(source, contains('hours > 0 && hours <= widget.hoursOf(task)'));
    expect(source, contains('lab_weekly_payroll_drafts'));
    expect(source, contains('ON CONFLICT'));
    expect(source, isNot(contains('Supabase')));
    expect(source, isNot(contains('BriskersApi')));
  });

  test('Legacy Payroll TEST ledger is no longer the employee landing', () {
    final source = File('lib/tasks_lab_main.dart').readAsStringSync();
    expect(source, isNot(contains("_sectionHeader('Payroll TEST ledger'")));
    expect(source, contains('Review Weekly Labor'));
    expect(source, contains('Open employee payroll'));
    expect(source, contains('initialTab: 1'));
    expect(source, contains('BriskersColors.jobs'));
  });
}
