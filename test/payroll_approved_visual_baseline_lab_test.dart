import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Owner reference image phone 1: Payroll overview is ALL employees', () {
    final main = File('lib/tasks_lab_main.dart').readAsStringSync();
    final overview = File('lib/tasks_lab/payroll_overview_screen.dart')
        .readAsStringSync();
    expect(main, contains('LabPayrollOverviewScreen('));
    expect(main, contains('onReviewWeek: _reviewEmployeeWeek'));
    for (final label in [
      'Payroll', 'Week of', 'Hours', 'Gross', 'Paid', 'Balance',
      'Outstanding from previous weeks', 'Review Weekly Labor',
      'Total Hours', 'Total Gross', 'Total Paid', 'Total Balance',
      'payroll-overview-fixed-totals',
    ]) {
      expect(overview, contains(label), reason: label);
    }
    expect(overview, contains("e['role'] != 'owner'"));
  });

  test('Owner reference image phone 2: detail summaries and actions', () {
    final profile = File('lib/tasks_lab/employee_payroll_profile.dart')
        .readAsStringSync();
    for (final label in [
      'Outstanding balance (all weeks)',
      'Previous weeks', 'Selected week', 'Total amount owed',
      'Review Weekly Labor',
      'Advances & Repayments',
      "Tab(text: 'Tasks')", "Tab(text: 'Payroll')",
      "Tab(text: 'Reports')", "Tab(text: 'Taxes')",
      'LabPayrollHistoryPanel(',
    ]) {
      expect(profile, contains(label), reason: label);
    }
    expect(profile, contains('bool _advanceExpanded = false'));
  });

  test('Owner reference image phone 3: week-based history under Reports', () {
    final report = File('lib/tasks_lab/payroll_history_panel.dart')
        .readAsStringSync();
    for (final label in [
      'Payroll History', 'Week of', 'Paid', 'Partial',
      "'All'", "'2026'", "'2025'", "'Custom'",
      "'This Month'", "'Last Month'",
      "'Last 3 Months'", "'Last 6 Months'", "'Year to Date'",
      'Hours', 'Gross', 'Paid', 'Balance',
      'reports-fixed-payment-total',
    ]) {
      expect(report, contains(label), reason: label);
    }
    expect(report, contains('_showTaskHistory(week)'));
  });

  test('Separate Weekly Labor Times has approved fixed 3-column footer', () {
    final review = File('lib/tasks_lab/weekly_labor_review_screen.dart')
        .readAsStringSync();
    expect(review, contains('Tasks selected'));
    expect(review, contains('Selected this week'));
    expect(review, contains('Available hours'));
    expect(review, contains('Payment note (optional)'));
    expect(review, contains('Verify Payment'));
    expect(review, contains('weekly-labor-tasks-scroll-only'));
    expect(review, contains('weekly-labor-fixed-footer'));
    expect(review, contains('Timer(const Duration(seconds: 10)'));
    expect(review, contains('lab_weekly_labor_notes'));
    expect(review, isNot(contains('Final amount override (TEST)')));
  });
}
