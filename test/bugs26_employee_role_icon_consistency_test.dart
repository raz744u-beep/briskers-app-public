import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/employee_role_style.dart';

void main() {
  test('role icons stay consistent between Jobs and Employees', () {
    expect(employeeRoleStyle('Mechanic').icon, Icons.build_outlined);
    expect(employeeRoleStyle('Secretary').icon, Icons.support_agent_outlined);
    expect(employeeRoleStyle('Shop Foreman').icon, Icons.engineering_outlined);
    expect(employeeRoleStyle('Porter').icon, Icons.local_shipping_outlined);
    expect(employeeRoleStyle('Owner').icon, Icons.workspace_premium_outlined);
  });
}
