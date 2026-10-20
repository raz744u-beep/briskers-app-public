import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Approved Customer and Vehicle save actions share a stable dark-blue token', () {
    final colors = File('lib/core/briskers_colors.dart').readAsStringSync();
    final customer =
        File('lib/screens/customers/edit_customer_screen.dart').readAsStringSync();
    final vehicle =
        File('lib/screens/customers/new_vehicle_screen.dart').readAsStringSync();
    expect(colors, contains('static const customerSave = Color(0xFF18529A)'));
    final customerSave = customer.substring(customer.indexOf('FilledButton.icon('));
    final vehicleSave = vehicle.substring(vehicle.lastIndexOf('FilledButton.icon('));
    for (final widget in [customerSave, vehicleSave]) {
      expect(widget, contains('backgroundColor: BriskersColors.customerSave'));
      expect(widget, contains('foregroundColor: Colors.white'));
      expect(widget, contains('_busy ? null : _save'));
    }
    expect(customerSave, contains("'Save changes'"));
    expect(vehicleSave, contains("'Save vehicle'"));
  });

  test('Existing primary module Save actions keep their established colors', () {
    final expense = File('lib/screens/expenses/expense_entry_screen.dart')
        .readAsStringSync();
    final job = File('lib/screens/jobs/job_edit_screen.dart')
        .readAsStringSync();
    final newCustomer = File('lib/screens/customers/new_customer_screen.dart')
        .readAsStringSync();
    expect(expense, contains('backgroundColor: BriskersColors.expenses'));
    expect(job, contains('backgroundColor: BriskersColors.jobs'));
    expect(newCustomer, contains('backgroundColor: BriskersColors.customers'));
  });
  test('Customer notes, expense edit and vehicle findings use module colors', () {
    final notes = File('lib/screens/customers/customer_notes_section.dart')
        .readAsStringSync();
    final expenses = File('lib/screens/expenses/expense_detail_screen.dart')
        .readAsStringSync();
    final findings = File('lib/screens/customers/customer_vehicle_findings_section.dart')
        .readAsStringSync();
    expect(notes, contains('backgroundColor: BriskersColors.customerSave'));
    expect(notes, contains('backgroundColor: BriskersColors.customers'));
    expect(expenses, contains('backgroundColor: BriskersColors.expenses'));
    expect(findings, contains('backgroundColor: BriskersColors.vehicles'));
    // Delete actions retain the danger/error color, not a module save style.
    expect(expenses, contains('backgroundColor: Theme.of(context).colorScheme.error'));
  });

}
