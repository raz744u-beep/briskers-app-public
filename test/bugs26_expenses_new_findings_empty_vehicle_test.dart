import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Expenses New action works while saved list hydrates', () {
    final source = File('lib/screens/expenses_screen.dart').readAsStringSync();
    expect(source, contains('onPressed: _importing ? null : _showAddMenu,'));
    expect(source, isNot(contains(
      'onPressed: _importing || _loading ? null : _showAddMenu,',
    )));
    expect(source, contains('ExpenseEntryScreen('));
    expect(source, contains("Opening saved transactions on this device"));
  });

  test('Customer Add Finding explains missing vehicle instead of silent tap', () {
    final source =
        File('lib/screens/customers/customer_vehicle_findings_section.dart')
            .readAsStringSync();
    expect(source, contains('if (vehicles.isEmpty) {'));
    expect(source, contains(
      'Add a vehicle to this customer before recording a finding.',
    ));
    expect(source, contains('if (vehicles.length == 1) return vehicles.first;'));
    expect(source, contains('await _offlineWrites.createFinding('));
  });
}
