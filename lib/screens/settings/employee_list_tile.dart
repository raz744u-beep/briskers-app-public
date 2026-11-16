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
        title: Tooltip(
        triggerMode: TooltipTriggerMode.manual,
          message: '$nickname${legal == nickname ? '' : ' · $legal'}',
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: nickname,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (legal.isNotEmpty && legal != nickname)
                  TextSpan(
                    text: ' · $legal',
                    style: const TextStyle(fontWeight: FontWeight.w400),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: active ? const Color(0xFF17202A) : Colors.grey,
            ),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  '$position${active ? '' : ' · Inactive'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? role.color : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Text(' · ', style: TextStyle(fontSize: 13)),
              Flexible(
                flex: 3,
                child: Tooltip(
        triggerMode: TooltipTriggerMode.manual,
                  message: pay,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      pay,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF414852),
                      ),
                    ),
                  ),
                ),
              ),
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
