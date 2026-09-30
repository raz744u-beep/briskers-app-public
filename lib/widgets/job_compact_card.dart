import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../core/employee_role_style.dart';
import '../core/job_status_style.dart';

class JobCompactCard extends StatelessWidget {
  const JobCompactCard({
    super.key,
    required this.job,
    required this.statusControl,
    required this.onOpen,
    this.canOpen = true,
  });

  final Map<String, dynamic> job;
  final Widget statusControl;
  final VoidCallback onOpen;
  final bool canOpen;

  String _hours(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  String _firstName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Unassigned' : parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final number = job['job_number']?.toString().trim() ?? '';
    final customer = (job['customer_name'] ?? job['customer'])
            ?.toString()
            .trim() ??
        '';
    final requested = job['requested_work']?.toString().trim() ?? '';
    final title = job['title']?.toString().trim() ?? '';
    final description = requested.isNotEmpty ? requested : title;
    final vehicle = job['vehicle']?.toString().trim() ?? '';
    final employee = (job['assigned_employee'] ?? job['mechanic'])
            ?.toString()
            .trim() ??
        '';
    final position =
        job['assigned_position']?.toString().trim().isNotEmpty == true
            ? job['assigned_position'].toString().trim()
            : 'Employee';
    final roleStyle = employeeRoleStyle(position);
    final firstName = employee.isEmpty ? 'Unassigned' : _firstName(employee);
    final findings =
        int.tryParse(job['open_findings']?.toString() ?? '') ?? 0;
    final requests =
        int.tryParse(job['pending_requests']?.toString() ?? '') ?? 0;
    final statusColor = colorFromHex(job['status_color']?.toString());
    final paymentState = job['status']?.toString() == 'completed'
        ? job['payment_state']?.toString()
        : null;
    final paymentLabel = switch (paymentState) {
      'paid' => 'Paid',
      'awaiting_clearance' => 'Awaiting clearance',
      'awaiting_payment' => 'Awaiting payment',
      _ => null,
    };
    final paymentColor = paymentState == 'paid'
        ? const Color(0xFF169B62)
        : const Color(0xFFE58A00);

    final vehicleFlex = (3 + (vehicle.length / 8).ceil()).clamp(3, 7).toInt();
    final employeeFlex =
        (3 + (firstName.length / 5).ceil()).clamp(3, 6).toInt();

    final cardTint = Color.alphaBlend(
      statusColor.withValues(alpha: 0.11),
      const Color(0xFFF7FAF9),
    );

    Widget separator() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: statusColor.withValues(alpha: 0.30),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardTint,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpen ? onOpen : null,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.72,
                    heightFactor: 0.88,
                    child: Opacity(
                      opacity: 0.30,
                      child: Image.asset(
                        'assets/job_car_watermark.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          <String>[
                            if (number.isNotEmpty) number,
                            if (customer.isNotEmpty) customer,
                          ].join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      statusControl,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          description.isEmpty ? 'No description' : description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 13.5,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (paymentLabel != null) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: paymentColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: paymentColor.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            paymentLabel,
                            style: TextStyle(
                              color: paymentColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      if (findings > 0) ...[
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: Colors.deepOrange,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$findings',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (requests > 0) ...[
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 15,
                          color: BriskersColors.jobs,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$requests',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 24),
                    ],
                  ),
                  Divider(
                    height: 13,
                    color: statusColor.withValues(alpha: 0.22),
                  ),
                  Row(
                    children: [
                      Expanded(
                        flex: vehicleFlex,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            vehicle.isEmpty ? 'No vehicle' : vehicle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      separator(),
                      Expanded(
                        flex: employeeFlex,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                roleStyle.icon,
                                size: 17,
                                color: roleStyle.color,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  firstName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      separator(),
                      SizedBox(
                        width: 82,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${_hours(job['planned_hours'])} hr',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.timer_outlined,
                              size: 17,
                              color: BriskersColors.jobs,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
