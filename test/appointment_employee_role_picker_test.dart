import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/widgets/employee_role_menu_item.dart';
import 'package:briskers_app/core/employee_role_style.dart';

void main() {
  testWidgets('Appointment employee row shows matching role icon and labels',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 350,
          child: EmployeeRoleMenuItem(name: 'Chris', position: 'Mechanic'),
        ),
      ),
    ));
    expect(find.byIcon(Icons.build_outlined), findsOneWidget);
    expect(find.textContaining('Chris'), findsOneWidget);
    expect(find.textContaining('Mechanic'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.build_outlined));
    expect(icon.color, employeeRoleStyle('Mechanic').color);
  });

  test('both Appointment create and edit use the shared role menu widget',
      () {
    for (final file in [
      'lib/screens/appointments/appointment_create_screen.dart',
      'lib/screens/appointments/appointment_manage_screen.dart',
    ]) {
      final source = File(file).readAsStringSync();
      expect(source, contains("import '../../widgets/employee_role_menu_item.dart';"));
      expect(source, contains('EmployeeRoleMenuItem('));
      expect(source, contains("employee['position_name']"));
      expect(source, contains("value: employee['id']?.toString()"));
      expect(source, contains('onChanged: (value) => setState(() => _employeeId = value)'));
      expect(source, contains("Text('Unassigned')"));
    }
  });
}
