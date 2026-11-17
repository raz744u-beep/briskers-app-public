import 'package:flutter/material.dart';
import '../../core/briskers_colors.dart';
import '../../core/employee_role_style.dart';
import '../../services/employee_nickname_store.dart';

/// The roster's two visual lines; compensation is supplied by the existing
/// authorized local-pay lookup, never inferred from a name or a role.
class EmployeeListTile extends StatelessWidget {
  const EmployeeListTile({
    super.key,
    required this.employee,
    required this.pay,
    required this.onOpen,
    required this.onLongPress,
  });
  final Map<String, dynamic> employee;
  final String pay;
  final VoidCallback onOpen, onLongPress;
  @override
  Widget build(BuildContext context) {
    final active = employee['active'] != false;
    final nickname = EmployeeNicknameStore.displayName(employee);
    final legal = employee['name']?.toString() ?? '';
    final position =
        (employee['position'] ?? employee['position_name'])?.toString() ??
        'No position';
    final role = employeeRoleStyle(position);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        minVerticalPadding: 8,
        leading: CircleAvatar(
          backgroundColor: (active ? role.color : Colors.grey).withValues(
            alpha: .14,
          ),
          child: Icon(
            active ? role.icon : Icons.person_off_outlined,
            color: active ? role.color : Colors.grey,
          ),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nickname, style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: active ? const Color(0xFF17202A) : Colors.grey,
            )),
            if (legal.isNotEmpty && legal != nickname) ...[
              const SizedBox(width: 12),
              Expanded(child: Text(legal,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 15,
                  color: active ? const Color(0xFF17202A) : Colors.grey),
              )),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(
                '$position${active ? '' : ' · Inactive'}',
                style: TextStyle(fontSize: 13,
                  color: active ? role.color : Colors.grey,
                  fontWeight: FontWeight.w600),
              )),
              const SizedBox(width: 12),
              Text(pay, textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: Color(0xFF414852))),
            ],
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: BriskersColors.settings,
        ),
        onTap: onOpen,
        onLongPress: onLongPress,
      ),
    );
  }
}
