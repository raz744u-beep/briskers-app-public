import 'package:flutter/material.dart';

import '../core/employee_role_style.dart';

/// Shared read-only *presentation* for an eligible assignment choice.
/// Selection and queued appointment mutations remain owned by the caller.
class EmployeeRoleMenuItem extends StatelessWidget {
  const EmployeeRoleMenuItem({
    super.key,
    required this.name,
    required this.position,
  });

  final String name;
  final String position;

  @override
  Widget build(BuildContext context) {
    final role = employeeRoleStyle(position);
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: role.color.withValues(alpha: 0.14),
          child: Icon(role.icon, color: role.color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: name),
                TextSpan(
                  text: ' — $position',
                  style: TextStyle(
                    color: role.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
