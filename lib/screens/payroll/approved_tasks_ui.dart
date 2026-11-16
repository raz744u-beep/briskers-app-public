import '../../services/local_task_schedule.dart';
import 'package:flutter/material.dart';

const taskNavy = Color(0xFF052749);
const taskGreen = Color(0xFF008D10);
const taskBlue = Color(0xFF005BE8);
const taskAmber = Color(0xFFBD6500);
const taskCanvas = Color(0xFFF4F7FF);

String taskStatus(Object? value) => switch (value?.toString()) {
  'done' || 'Done' || 'completed' => 'Done',
  'in_progress' || 'In Progress' => 'In Progress',
  _ => 'Open',
};
Color taskStatusColor(Object? value) => switch (taskStatus(value)) {
  'Done' => taskGreen,
  'In Progress' => taskBlue,
  _ => taskAmber,
};
IconData taskStatusIcon(Object? value) => switch (taskStatus(value)) {
  'Done' => Icons.check_circle,
  'In Progress' => Icons.sync,
  _ => Icons.hourglass_top,
};
Color taskPriorityColor(String priority) => switch (priority) {
  'High' => const Color(0xFFD50016),
  'Low' => const Color(0xFF8D929B),
  _ => taskGreen,
};

/// Used only by the four Owner-approved Tasks surfaces.
class ApprovedTasksHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const ApprovedTasksHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  @override
  Size get preferredSize => const Size.fromHeight(82);
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF00182E), Color(0xFF06325A)]),
    ),
    child: SafeArea(
      bottom: false,
      child: CustomPaint(
        painter: _HeaderWave(),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
              SizedBox(
                width: 112,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRect(
                        child: SizedBox(
                          height: 25,
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            maxHeight: 33,
                            child: Image.asset(
                              'assets/briskers_header_logo.png',
                              width: 112,
                              height: 33,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const Text(
                        'FOREIGN AUTO REPAIR',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Roboto',
                          fontSize: 5.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 45,
                width: 1,
                color: Colors.white70,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                flex: 6,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: title == 'Employee Profile'
                            ? 18
                            : subtitle == null
                            ? 23
                            : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              ...?actions,
            ],
          ),
        ),
      ),
    ),
  );
}

class _HeaderWave extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height - 9)
      ..cubicTo(
        size.width * .24,
        size.height - 32,
        size.width * .65,
        size.height + 12,
        size.width,
        size.height - 18,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF087AF5));
    final top = Path()
      ..moveTo(0, size.height - 12)
      ..cubicTo(
        size.width * .24,
        size.height - 35,
        size.width * .65,
        size.height + 9,
        size.width,
        size.height - 21,
      );
    canvas.drawPath(
      top,
      Paint()
        ..color = const Color(0xFF00EAFA)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TaskStatusPill extends StatelessWidget {
  const TaskStatusPill(
    this.status, {
    super.key,
    this.icon = true,
    this.filled = false,
  });
  final Object? status;
  final bool icon, filled;
  @override
  Widget build(BuildContext context) {
    final label = taskStatus(status), color = taskStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: filled
            ? color
            : label == 'Done'
            ? taskGreen
            : label == 'Open'
            ? const Color(0xFFFFE9CA)
            : const Color(0xFFE0F2FF),
        borderRadius: BorderRadius.circular(20),
        border: label == 'In Progress' ? Border.all(color: taskBlue) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon) ...[
            Icon(
              taskStatusIcon(status),
              size: 17,
              color: filled || label == 'Done' ? Colors.white : color,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: filled || label == 'Done' ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

class TaskPriorityPill extends StatelessWidget {
  const TaskPriorityPill({
    super.key,
    required this.priority,
    this.onChanged,
    this.fullLabel = false,
  });
  final String priority;
  final ValueChanged<String>? onChanged;
  final bool fullLabel;
  @override
  Widget build(BuildContext context) {
    final color = taskPriorityColor(priority);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: priority == 'High'
            ? const Color(0xFFFFE0E4)
            : priority == 'Low'
            ? const Color(0xFFE9EAED)
            : const Color(0xFFE4F5D8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            '$priority${fullLabel ? ' Priority' : ''}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: color,
            ),
          ),
          if (onChanged != null)
            Icon(Icons.keyboard_arrow_down, size: 17, color: color),
        ],
      ),
    );
    if (onChanged == null) return content;
    return PopupMenuButton<String>(
      tooltip: 'Task priority',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final p in ['High', 'Normal', 'Low'])
          PopupMenuItem(
            value: p,
            child: Row(
              children: [
                Icon(Icons.flag, color: taskPriorityColor(p)),
                const SizedBox(width: 10),
                Text(p),
              ],
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Center(widthFactor: 1, heightFactor: 1, child: content),
      ),
    );
  }
}

class ApprovedTaskListCard extends StatelessWidget {
  const ApprovedTaskListCard({
    super.key,
    required this.task,
    required this.assignment,
    required this.onTap,
    required this.onLongPress,
    this.general = false,
    this.jobScoped = false,
    this.onPriority,
  });
  final Map<String, dynamic> task;
  final String assignment;
  final VoidCallback onTap, onLongPress;
  final bool general, jobScoped;
  final ValueChanged<String>? onPriority;
  @override
  Widget build(BuildContext context) {
    final priority = task['priority']?.toString() ?? 'Normal';
    final status = task['status'];
    final overdue = general
        ? taskStatus(status) != 'Done' &&
              task['due_at'] is int &&
              DateTime.fromMillisecondsSinceEpoch(
                task['due_at'] as int,
              ).isBefore(DateTime.now())
        : LocalTaskSchedule.overdue(task);
    final title =
        (task['custom_description'] ??
                task['source_description'] ??
                task['description'] ??
                'Task')
            .toString();
    return ApprovedTaskCardSurface(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(
                left: BorderSide(
                  width: 5,
                  color: jobScoped
                      ? taskStatusColor(status)
                      : taskPriorityColor(priority),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(11, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  jobScoped
                      ? taskStatusIcon(status)
                      : general
                      ? Icons.assignment_outlined
                      : Icons.build_outlined,
                  color: jobScoped ? taskStatusColor(status) : taskNavy,
                  size: 27,
                ),
                if (jobScoped)
                  Container(
                    height: 36,
                    width: 1,
                    color: const Color(0xFFD1D5DB),
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                  )
                else
                  const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF10151B),
                        ),
                      ),
                      if (!jobScoped && task['job_id'] != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${task['job_number'] ?? 'Job'} · ${task['customer_name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF202832),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              assignment,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: jobScoped
                                    ? const Color(0xFF52616A)
                                    : const Color(0xFF202832),
                                fontWeight: jobScoped
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (overdue)
                            const Padding(
                              padding: EdgeInsets.only(left: 3),
                              child: Text(
                                'Overdue',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TaskPriorityPill(priority: priority, onChanged: onPriority),
                    TaskStatusPill(status, icon: !jobScoped),
                  ],
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF344054),
                  size: 25,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const payrollSectionHeaderGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF31A9D9), Color(0xFF2075BC), Color(0xFF174B92)],
);

class ApprovedProfileTabs extends StatelessWidget {
  const ApprovedProfileTabs({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    const entries = [
      ('Work', Color(0xFF2479C6)),
      ('Payroll', Color(0xFF176B40)),
      ('Reports', Color(0xFF6942A2)),
      ('Taxes', Color(0xFF697586)),
    ];
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 0,
            // The shared stripe below the tab row is the only selection indicator.
            indicator: const BoxDecoration(),
            labelPadding: EdgeInsets.zero,
            dividerHeight: 0,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF111820),
            tabs: [
              for (final (i, entry) in entries.indexed)
                Tab(
                  height: 40,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipPath(
                        clipper: _ProfileTabClip(),
                        child: Container(
                          key: ValueKey('profile-tab-${entry.$1}'),
                          alignment: Alignment.center,
                          decoration: controller.index == i
                              ? BoxDecoration(color: entry.$2)
                              : const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFFEAEDF3),
                                      Color(0xFFDCE2EB),
                                    ],
                                  ),
                                ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                children: [
                                  Icon(
                                    [
                                      Icons.layers_outlined,
                                      Icons.payments_outlined,
                                      Icons.bar_chart,
                                      Icons.description_outlined,
                                    ][i],
                                    size: 16,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    entry.$1,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            height: 3,
            child: ColoredBox(
              key: const ValueKey('profile-tabs-stripe'),
              // Use the same theme value as the selected tab background.
              color: entries[controller.index].$2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTabClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, s.height)
    ..lineTo(8, 10)
    ..quadraticBezierTo(11, 0, 21, 0)
    ..lineTo(s.width - 21, 0)
    ..quadraticBezierTo(s.width - 11, 0, s.width - 8, 10)
    ..lineTo(s.width, s.height)
    ..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class ApprovedEmployeeIdentity extends StatelessWidget {
  const ApprovedEmployeeIdentity({
    super.key,
    required this.name,
    required this.role,
    required this.active,
    this.onDetails,
  });
  final String name, role;
  final bool active;
  final VoidCallback? onDetails;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const CircleAvatar(
        radius: 28,
        backgroundColor: Color(0xFFDDF1FC),
        child: Icon(Icons.build_outlined, size: 30, color: Color(0xFF16865A)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$role · ', style: const TextStyle(fontSize: 14)),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFBDF5A9)
                        : const Color(0xFFE4E7EC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    active ? 'Active' : 'Inactive',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF175720),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: onDetails,
        icon: const Icon(Icons.person_outline),
        label: const Text(
          'Details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF123A7E),
          side: const BorderSide(color: Color(0xFF344054)),
        ),
      ),
    ],
  );
}

/// Shared approved white compact task-card surface, also used for paid history.
class ApprovedTaskCardSurface extends StatelessWidget {
  const ApprovedTaskCardSurface({
    super.key,
    required this.child,
    this.borderColor,
  });
  final Widget child;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE1E9)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22051D35),
          offset: Offset(0, 2),
          blurRadius: 2,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          border: borderColor == null
              ? null
              : Border(left: BorderSide(width: 5, color: borderColor!)),
        ),
        child: child,
      ),
    ),
  );
}
