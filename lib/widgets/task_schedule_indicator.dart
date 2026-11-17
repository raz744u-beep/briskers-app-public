import 'package:flutter/material.dart';
import '../services/local_task_schedule.dart';

/// Trailing decoration keeps the title's left edge and card height unchanged.
class TaskScheduleIndicator extends StatelessWidget {
  const TaskScheduleIndicator(this.task, {super.key});
  final Map<String, dynamic> task;
  @override
  Widget build(BuildContext context) {
    final priority = task['priority'] as String? ?? 'Normal';
    final overdue = LocalTaskSchedule.overdue(task);
    return Tooltip(
      message: '$priority priority${overdue ? ' · Overdue' : ''}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (overdue)
            const Text(
              'Overdue',
              style: TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          Icon(
            Icons.flag,
            size: 16,
            color: switch (priority) {
              'High' => const Color(0xFFDC2626),
              'Low' => const Color(0xFFCBD5E1),
              _ => const Color(0xFF16A34A),
            },
          ),
        ],
      ),
    );
  }
}
