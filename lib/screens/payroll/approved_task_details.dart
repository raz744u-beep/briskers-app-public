import 'payroll_review_widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'approved_tasks_ui.dart';
import 'employee_work_review.dart';

/// A live view of the existing task. All mutations are delegated to the same
/// Owner operations used by the list/editor; this screen owns no records.
class ApprovedTaskDetails extends StatefulWidget {
  const ApprovedTaskDetails({
    super.key,
    this.sharedBottomNavigationBar,
    required this.initialTask,
    required this.allocations,
    required this.general,
    required this.employeeName,
    required this.reload,
    required this.onEdit,
    required this.onPriority,
    required this.onProgress,
    this.onEditDescription,
    this.onJob,
    this.onInvoice,
    this.onActions,
  });
  final Widget? sharedBottomNavigationBar;
  final Map<String, dynamic> initialTask;
  final List<Map<String, dynamic>> allocations;
  final bool general;
  final String Function(String?) employeeName;
  final Future<
    ({Map<String, dynamic> task, List<Map<String, dynamic>> allocations})
  >
  Function()
  reload;
  final Future<void> Function() onEdit;
  final Future<void> Function()? onEditDescription;
  final Future<void> Function(String) onPriority;
  final Future<void> Function(bool) onProgress;
  final VoidCallback? onJob, onInvoice, onActions;
  @override
  State<ApprovedTaskDetails> createState() => _ApprovedTaskDetailsState();
}

class _ApprovedTaskDetailsState extends State<ApprovedTaskDetails> {
  late Map<String, dynamic> task = widget.initialTask;
  late List<Map<String, dynamic>> allocations = widget.allocations;
  bool busy = false;
  String? error;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      final value = await widget.reload();
      if (mounted) {
        setState(() {
          task = value.task;
          allocations = value.allocations;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget info(IconData icon, String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 23, color: const Color(0xFF111820)),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Expanded(flex: 6, child: value),
      ],
    ),
  );
  Widget button(
    String label,
    IconData icon,
    Color? color,
    VoidCallback? action,
  ) => Expanded(
    child: color == null
        ? OutlinedButton.icon(
            onPressed: action,
            icon: Icon(icon, size: 23),
            label: FittedBox(child: Text(label)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF071A32),
              side: const BorderSide(color: Color(0xFF263749)),
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : FilledButton.icon(
            onPressed: action,
            icon: Icon(icon, size: 23),
            label: FittedBox(child: Text(label)),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
  );
  @override
  Widget build(BuildContext context) {
    final status = taskStatus(task['status']);
    final editable = allocations
        .where(
          (r) =>
              r['state'] != 'Done' &&
              r['archived_labor'] != 1 &&
              r['source_active'] != 0 &&
              r['assignment_conflict'] != 1 &&
              r['owner_prior_paid'] != 1 &&
              ((r['paid_minutes'] as int? ?? 0) == 0 ||
                  r['state'] == 'In Progress'),
        )
        .toList();
    final canProgress =
        status != 'Done' && (widget.general || editable.isNotEmpty);
    final canDone =
        canProgress &&
        (widget.general ||
            editable.every((r) => (r['estimated_minutes'] as int? ?? 0) > 0));
    final description =
        (task['custom_description'] ??
                task['source_description'] ??
                task['description'] ??
                'Task')
            .toString();
    final savedName = task['task_name']?.toString().trim() ?? '';
    final title = savedName.isEmpty ? description : savedName;
    final names = widget.general
        ? widget.employeeName(task['employee_id']?.toString())
        : allocations
              .map((r) => widget.employeeName(r['employee_id']?.toString()))
              .join(', ');
    final hours = allocations.fold<int>(
      0,
      (sum, r) => sum + (r['estimated_minutes'] as int? ?? 0),
    );
    final start = DateTime.tryParse(task['work_start_date']?.toString() ?? '');
    final end = DateTime.tryParse(task['work_end_date']?.toString() ?? '');
    final workDate = start == null
        ? 'Not recorded'
        : start == end
        ? DateFormat('MMM d, yyyy').format(start)
        : '${DateFormat('MMM d').format(start)} – ${end == null ? 'Not recorded' : DateFormat('MMM d, yyyy').format(end)}';
    return Scaffold(
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      backgroundColor: taskCanvas,
      appBar: ApprovedTasksHeader(
        title: task['job_id'] == null
            ? 'Task Details'
            : 'Job ${task['job_number'] ?? ''}',
        subtitle: task['customer_name']?.toString(),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'edit') {
                run(widget.onEdit);
              } else if (value == 'job') {
                widget.onJob?.call();
              } else {
                widget.onInvoice?.call();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Task')),
              if (widget.onJob != null)
                const PopupMenuItem(value: 'job', child: Text('View Job')),
              if (widget.onInvoice != null)
                const PopupMenuItem(
                  value: 'invoice',
                  child: Text('View Invoice'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (task['job_id'] != null) ...[
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: const Border(
                    left: BorderSide(color: taskGreen, width: 6),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26051D35),
                      offset: Offset(0, 2),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${task['job_number'] ?? 'Job'} · ${task['customer_name'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${task['vehicle_label'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF344054),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (task['job_status'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: task['job_status'] == 'closed'
                              ? const Color(0xFFE5E7EB)
                              : task['job_status'] == 'completed'
                              ? const Color(0xFFE0F5D8)
                              : task['job_status'] == 'in_progress'
                              ? const Color(0xFFDBEEFF)
                              : const Color(0xFFFFE3BD),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          task['job_status'] == 'closed'
                              ? 'Closed'
                              : task['job_status'] == 'completed'
                              ? 'Completed'
                              : task['job_status'] == 'in_progress'
                              ? 'In Progress'
                              : 'Open',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: task['job_status'] == 'closed'
                                ? const Color(0xFF4B5563)
                                : taskStatusColor(task['job_status']),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (widget.onInvoice != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EFFD),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, color: taskNavy),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Invoice #${task['invoice_number'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onInvoice,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                      ),
                      child: const Text(
                        'View Invoice',
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: const Border(
                  left: BorderSide(color: taskGreen, width: 6),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33051D35),
                    offset: Offset(0, 2),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFECF8EC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                    ),
                    key: const Key('task-details-header'),
                    child: Row(
                      children: [
                        const Icon(Icons.build_outlined, color: taskGreen, size: 28),
                        const SizedBox(width: 8),
                        const Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(
                          'Task Details',
                          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                        ))),
                        const SizedBox(width: 8),
                        TaskStatusPill(status, key: const Key('task-details-status'), filled: status == 'In Progress'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, box) => Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 7,
                            runSpacing: 6,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: box.maxWidth,
                                ),
                                child: Text(
                                  title,
                                  key: const Key('task-details-name'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              TaskPriorityPill(
                                priority:
                                    task['priority']?.toString() ?? 'Normal',
                                fullLabel: true,
                                onChanged: busy
                                    ? null
                                    : (p) => run(() => widget.onPriority(p)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        info(
                          Icons.person_outline,
                          widget.general
                              ? 'Assigned to:'
                              : 'Assigned Mechanic:',
                          Text(
                            names.isEmpty ? 'Unassigned' : names,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!widget.general)
                          info(
                            Icons.schedule,
                            'Assigned Hours:',
                            Text(
                              '${(hours / 60).toStringAsFixed(2)} h',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (!widget.general)
                          info(
                            Icons.assignment_outlined,
                            'Task Date:',
                            Text(
                              workDate,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        if (widget.general && task['due_at'] is int)
                          info(
                            Icons.event,
                            'Due:',
                            Text(
                              DateFormat('MMM d, yyyy · h:mm a').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                  task['due_at'] as int,
                                ),
                              ),
                            ),
                          ),
                        if (!widget.general) ...[
                          const Divider(height: 16),
                          for (final allocation in allocations)
                            Container(
                              key: ValueKey(
                                'labor-payment-${allocation['id']}',
                              ),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFDCE2EA),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.payments_outlined,
                                        color: taskGreen,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          allocations.length > 1
                                              ? 'Payroll · ${widget.employeeName(allocation['employee_id']?.toString())}'
                                              : 'Payroll (Labor Hours)',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  LaborBalanceTiles(
                                    compact: true,
                                    total:
                                        (allocation['estimated_minutes']
                                                as int? ??
                                            allocation['actual_minutes']
                                                as int? ??
                                            0) /
                                        60,
                                    paid:
                                        (allocation['paid_minutes'] as int? ??
                                            0) /
                                        60,
                                    remaining:
                                        allocation['owner_prior_paid'] == 1 ||
                                            allocation['paid'] == 1
                                        ? 0
                                        : (((allocation['estimated_minutes']
                                                              as int? ??
                                                          allocation['actual_minutes']
                                                              as int? ??
                                                          0) -
                                                      (allocation['paid_minutes']
                                                              as int? ??
                                                          0))
                                                  .clamp(0, 100000000)) /
                                              60,
                                  ),
                                  if ((allocation['payment_history'] as List? ??
                                          [])
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Last Payment: ${DateFormat.yMMMd().format(DateTime.parse((allocation['payment_history'] as List).first['verified_date'] as String))} · ${(((allocation['payment_history'] as List).first['minutes'] as int) / 60).toStringAsFixed(2)} h · ${payrollMoney((allocation['payment_history'] as List).first['amount'] as int)}',
                                      style: const TextStyle(
                                        color: taskGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if ((allocation['payment_history'] as List)
                                            .length >
                                        1)
                                      ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        title: const Text('Payment history'),
                                        children: [
                                          for (final payment
                                              in (allocation['payment_history']
                                                      as List)
                                                  .cast<Map>())
                                            ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                '${payment['verified_date']} · ${payment['method']}',
                                              ),
                                              subtitle: Text(
                                                '${((payment['minutes'] as int) / 60).toStringAsFixed(2)} h · ${payrollMoney(payment['amount'] as int)}',
                                              ),
                                            ),
                                        ],
                                      ),
                                  ] else
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        EmployeeWorkReview.paymentState(
                                          allocation,
                                        ),
                                        style: const TextStyle(
                                          color: taskAmber,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                        const Divider(height: 12),
                        Row(children: [
                          const Expanded(child: Text('Description', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                          IconButton(
                            tooltip: 'Edit description',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 22),
                            onPressed: busy ? null : () => run(widget.onEditDescription ?? widget.onEdit),
                          ),
                        ]),
                        Text(description, key: const Key('task-details-description'), style: const TextStyle(fontSize: 15)),
                        const SizedBox(height: 12),
                        if (error != null)
                          Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        if (busy) const LinearProgressIndicator(),
                        if (canProgress)
                          Row(
                            children: [
                              if (!widget.general) ...[
                                button(
                                  status == 'Open'
                                      ? 'Start Task'
                                      : 'Finish Task',
                                  Icons.play_arrow_outlined,
                                  taskBlue,
                                  busy
                                      ? null
                                      : () => run(
                                          () => widget.onProgress(
                                            status != 'Open',
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              button(
                                'Mark as Done',
                                Icons.check_circle_outline,
                                taskGreen,
                                busy || !canDone
                                    ? null
                                    : () => run(() => widget.onProgress(true)),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            button(
                              'Edit Task',
                              Icons.edit_outlined,
                              null,
                              busy ? null : () => run(widget.onEdit),
                            ),
                            if (widget.onJob != null) ...[
                              const SizedBox(width: 8),
                              button(
                                'View Job',
                                Icons.article_outlined,
                                null,
                                widget.onJob,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
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
