import 'package:flutter/material.dart';

class EmployeeRoleStyle {
  const EmployeeRoleStyle(this.icon, this.color);

  final IconData icon;
  final Color color;
}

EmployeeRoleStyle employeeRoleStyle(String? positionName) {
  final name = (positionName ?? '').trim().toLowerCase();

  if (name == 'owner') {
    return const EmployeeRoleStyle(
      Icons.workspace_premium_outlined,
      Color(0xFFD97706),
    );
  }
  if (name == 'shop foreman' || name == 'foreman') {
    return const EmployeeRoleStyle(
      Icons.engineering_outlined,
      Color(0xFF0F766E),
    );
  }
  if (name == 'mechanic' || name.contains('mechanic')) {
    return const EmployeeRoleStyle(
      Icons.build_outlined,
      Color(0xFF2563EB),
    );
  }
  if (name == 'secretary' || name.contains('secretary')) {
    return const EmployeeRoleStyle(
      Icons.support_agent_outlined,
      Color(0xFF7C3AED),
    );
  }
  if (name == 'porter' || name.contains('porter')) {
    return const EmployeeRoleStyle(
      Icons.local_shipping_outlined,
      Color(0xFFEA580C),
    );
  }

  return const EmployeeRoleStyle(
    Icons.badge_outlined,
    Color(0xFF64748B),
  );
}
