import 'package:flutter/material.dart';
import '../core/job_status_style.dart';
import '../services/job_task_summary.dart';

Color approvedJobListStatusColor(Map<String, dynamic> job) {
  final status = job['status']?.toString().trim().toLowerCase().replaceAll(' ', '_');
  return switch (status) {
    'open' || 'not_started' => const Color(0xFF0066FF),
    'in_progress' => const Color(0xFF0066FF),
    'awaiting_parts' || 'waiting_parts' => const Color(0xFFF58A00),
    'awaiting_payment' => const Color(0xFF7A16EE),
    'completed' || 'complete' || 'closed' => const Color(0xFF008F35),
    _ => colorFromHex(job['status_color']?.toString()),
  };
}

/// Owner-approved Bugs 35 shared Jobs, Service Tasks and Invoices card.
class JobListApprovedCard extends StatelessWidget {
  const JobListApprovedCard({
    super.key,
    required this.job,
    required this.number,
    required this.customer,
    required this.invoiceNumber,
    required this.vehicle,
    required this.description,
    required this.mechanic,
    required this.employee,
    required this.mechanicMinutes,
    required this.progress,
    required this.statusControl,
    this.onOpen,
    this.onLongPress,
    this.onOpenInvoice,
    this.financialSummary,
    this.expandedDetails,
    this.footer,
  });
  final Map<String, dynamic> job;
  final String number,
      customer,
      invoiceNumber,
      vehicle,
      description,
      mechanic,
      employee;
  final Map<String, int>? mechanicMinutes;
  final JobTaskProgress? progress;
  final Widget statusControl;
  final Widget? financialSummary, expandedDetails, footer;
  final VoidCallback? onOpen, onLongPress, onOpenInvoice;

  String hours(int minutes) {
    final value = minutes / 60;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  @override
  Widget build(BuildContext context) {
    const slate = Color(0xFF526171);
    const black = Color(0xFF101010);
    final color = approvedJobListStatusColor(job);
    final total = progress?.total ?? 0;
    final done = progress?.done ?? 0;
    final fraction = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final extra =
        int.tryParse(job['additional_work_count']?.toString() ?? '') ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: const Color(0x22344466),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 9, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          number,
                          customer,
                        ].where((s) => s.isNotEmpty).join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    if (invoiceNumber.isNotEmpty)
                      Semantics(
                        link: true,
                        child: InkWell(
                          onTap: onOpenInvoice,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Invoice #${invoiceNumber.replaceFirst(RegExp(r'^(?:#|I-)'), '')}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: slate,
                                    decoration: TextDecoration.underline,
                                    decorationColor: slate,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      const Text(
                        'No invoice yet',
                        style: TextStyle(fontSize: 12, color: slate),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        vehicle.isEmpty ? 'No vehicle' : vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    statusControl,
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.build_outlined,
                        size: 16,
                        color: Color(0xFF18234B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        description.isEmpty ? 'No description' : description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: black,
                        ),
                      ),
                    ),
                  ],
                ),
                if (extra > 0)
                  Text(
                    '+$extra more',
                    style: const TextStyle(fontSize: 11, color: slate),
                  ),
                const SizedBox(height: 2),
                if (financialSummary != null)
                  financialSummary!
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          progress == null
                              ? 'Loading saved tasks…'
                              : total == 0
                              ? 'No tasks yet'
                              : '$done of $total tasks completed',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: black,
                          ),
                        ),
                      ),
                      if (progress != null)
                        Text(
                          '${(fraction * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: black,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(8),
                    color: fraction == 1 ? const Color(0xFF008F35) : color,
                    backgroundColor: const Color(0xFFDFE1EC),
                  ),
                ],
                const Divider(
                  height: 9,
                  thickness: 0.5,
                  color: Color(0xFFDDE0EB),
                ),
                if (footer != null)
                  footer!
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 18,
                        color: Color(0xFF18234B),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 2,
                          children: [
                            if (mechanicMinutes == null ||
                                mechanicMinutes!.isEmpty)
                              Text(
                                mechanic,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: slate,
                                ),
                              )
                            else
                              for (final entry in mechanicMinutes!.entries)
                                Text(
                                  '${entry.key == employee ? mechanic : entry.key} · ${hours(entry.value)} hrs',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: slate,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ?expandedDetails,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One badge treatment; callers retain their existing status meaning/actions.
class ApprovedListStatusBadge extends StatelessWidget {
  const ApprovedListStatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 155),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const {'Paid', 'Closed', 'Done'}.contains(label) ? color : color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const {'Paid', 'Closed', 'Done'}.contains(label) ? Colors.white : color),
        const SizedBox(width: 4),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: const {'Paid', 'Closed', 'Done'}.contains(label) ? Colors.white : color,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
