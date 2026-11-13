import '../../widgets/owner_confirmation_dialog.dart';
import '../../core/job_display_description.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../../services/local_task_schedule.dart';
import 'task_selection_dialog.dart';

class TaskMechanicDraft {
  TaskMechanicDraft(
    this.employee,
    this.minutes, {
    this.originalEmployee,
    this.locked = false,
  });
  String employee;
  int minutes;
  final String? originalEmployee;
  final bool locked;
}

class ServiceTaskDraft {
  ServiceTaskDraft({
    required this.job,
    required this.description,
    required this.mechanics,
    required this.start,
    required this.end,
    required this.priority,
    required this.status,
    required this.treatment,
    this.newCustomer,
    this.newVehicle,
  });
  final String job, description, start, end, priority, status, treatment;
  final List<TaskMechanicDraft> mechanics;
  final Map<String, dynamic>? newCustomer, newVehicle;
}

/// One editor and one save operation; neither a customer charge nor a payment.
class ServiceTaskEditor extends StatefulWidget {
  const ServiceTaskEditor({
    super.key,
    required this.jobs,
    required this.employees,
    required this.initial,
    required this.save,
    this.editing = false,
    this.invoiceLabor = false,
    this.statusLocked = false,
    this.payrollLocked = false,
    this.onLinkInvoiceLabor,
    this.pickCustomer,
    this.onOpenJob,
  });
  final List<Map<String, dynamic>> jobs, employees;
  final ServiceTaskDraft initial;
  final Future<void> Function(ServiceTaskDraft) save;
  final bool editing, invoiceLabor, statusLocked, payrollLocked;
  final VoidCallback? onLinkInvoiceLabor;
  final ValueChanged<String>? onOpenJob;
  final Future<Map<String, dynamic>?> Function()? pickCustomer;
  @override
  State<ServiceTaskEditor> createState() => _ServiceTaskEditorState();
}

class _ServiceTaskEditorState extends State<ServiceTaskEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _description;
  late String _job, _priority, _status, _treatment;
  late DateTime _start, _end;
  late List<TaskMechanicDraft> _mechanics;
  Map<String, dynamic>? _customer, _vehicle;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _description = TextEditingController(text: v.description);
    _job = v.job;
    _start = LocalTaskSchedule.parse(v.start)!;
    _end = LocalTaskSchedule.parse(v.end)!;
    _priority = v.priority;
    _status = v.status;
    _treatment = v.treatment;
    _mechanics = v.mechanics
        .map(
          (m) => TaskMechanicDraft(
            m.employee,
            m.minutes,
            originalEmployee: m.originalEmployee,
            locked: m.locked,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  static const _green = Color(0xFF08752B);
  static const _ink = Color(0xFF171D19);
  static const _pale = Color(0xFFF0F8EF);

  ThemeData _editorTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: _green).copyWith(
        primary: _green,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: _ink,
        surfaceTint: Colors.transparent,
      ),
      scaffoldBackgroundColor: Colors.white,
      disabledColor: const Color(0xFF606A62),
      textTheme: base.textTheme.apply(bodyColor: _ink, displayColor: _ink),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF909A92)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: _green, width: 2),
        ),
        labelStyle: TextStyle(color: _ink),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _green,
        selectionHandleColor: _green,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _green),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _green,
          side: const BorderSide(color: _green),
          minimumSize: const Size(0, 52),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
    ),
  );

  // Keep the approved paired fields on phones, but allow large text to wrap
  // into full-width controls instead of clipping or shrinking readable text.
  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 330 ||
          MediaQuery.textScalerOf(context).scale(16) > 21) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 14), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _dateField(bool start) => InkWell(
    key: ValueKey(start ? 'task-start-date' : 'task-end-date'),
    borderRadius: BorderRadius.circular(8),
    onTap: _saving ? null : () => _date(start),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: start ? 'Start Date' : 'End Date',
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined, size: 22, color: _green),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              DateFormat('MMM d, yyyy').format(start ? _start : _end),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  Color _priorityColor(String value) => switch (value) {
    'High' => const Color(0xFFCA2B27),
    'Low' => const Color(0xFFCBD5E1),
    _ => _green,
  };
  Widget _priorityValue(String value) => Row(
    children: [
      Icon(Icons.flag, size: 20, color: _priorityColor(value)),
      const SizedBox(width: 7),
      Flexible(child: Text(value)),
    ],
  );
  Widget _statusValue(String value) => Row(
    children: [
      Icon(
        value == 'Done'
            ? Icons.check_circle
            : value == 'In Progress'
            ? Icons.build_circle_outlined
            : Icons.hourglass_empty,
        size: 20,
        color: value == 'Done'
            ? _green
            : value == 'In Progress'
            ? const Color(0xFF1976D2)
            : const Color(0xFFA66B00),
      ),
      const SizedBox(width: 7),
      Flexible(child: Text(value == 'Open' ? 'Not Started' : value)),
    ],
  );

  Future<void> _chooseJob() async {
    final selected = await showJobTaskSelection(
      context,
      widget.jobs,
      allowNew: widget.pickCustomer != null,
    );
    if (selected != null && mounted) {
      setState(() {
        _job = selected;
        final lead = widget.jobs
            .where((j) => j['id'] == selected)
            .firstOrNull?['assigned_employee_id'];
        if (lead is String &&
            widget.employees.any((e) => e['id'] == lead) &&
            _mechanics.length == 1) {
          _mechanics = [TaskMechanicDraft(lead, _mechanics.single.minutes)];
        }
      });
    }
  }

  Widget _jobHeader(Map<String, dynamic>? job) {
    final description = job == null ? '' : jobDisplayDescription(job);
    return Material(
      color: _pale,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD3E5D3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('service-task-job'),
        onTap: _saving
            ? null
            : widget.editing
            ? (widget.onOpenJob == null || job == null
                  ? null
                  : () => widget.onOpenJob!(_job))
            : _chooseJob,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(
                Icons.directions_car_outlined,
                color: _green,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job == null
                          ? 'Choose a job'
                          : [job['job_number'], job['customer_name']]
                                .where(
                                  (v) => v != null && v.toString().isNotEmpty,
                                )
                                .join(' · '),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((job?['vehicle_label'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        job!['vehicle_label'].toString(),
                        style: const TextStyle(fontSize: 15),
                      ),
                    ],
                    if (!widget.editing && description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!widget.editing || widget.onOpenJob != null)
                const Icon(Icons.chevron_right, color: _green),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _date(bool start) async {
    final d = await showDatePicker(
      context: context,
      builder: (context, child) =>
          Theme(data: _editorTheme(context), child: child!),
      initialDate: start ? _start : _end,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) {
      setState(() {
        if (start) {
          _start = d;
        } else {
          _end = d;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_job.isEmpty ||
        (_job == 'new' && _customer == null) ||
        (!widget.editing && _mechanics.isEmpty) ||
        _mechanics.any((m) => m.employee.isEmpty) ||
        _mechanics.map((m) => m.employee).toSet().length != _mechanics.length ||
        _end.isBefore(_start)) {
      setState(
        () => _error =
            'Select a job and distinct mechanics, and an End Date on or after Start Date.',
      );
      return;
    }
    if (((_status == 'Done' && !widget.statusLocked) || _treatment == 'paid') &&
        _mechanics.any((m) => m.minutes <= 0)) {
      setState(
        () =>
            _error = 'Completed labor needs assigned hours for each mechanic.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_treatment == 'paid') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => OwnerConfirmationDialog(
            title: 'Mark as Already Paid',
            confirm: 'Confirm historical payment',
            sections: [
              Text(
                _description.text.trim(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              for (final m in _mechanics)
                Text(
                  '${widget.employees.where((e) => e['id'] == m.employee).firstOrNull?['name'] ?? m.employee} · ${(m.minutes / 60).toStringAsFixed(2)} hours',
                ),
              const Divider(height: 24),
              const Text(
                'Confirm these wages were already paid.\n\n• Marks these task portions Done and already paid.\n• Excludes these hours from future unpaid payroll.\n• Keeps existing tasks and financial history.\n• Does not create a payment or expense.\n• Does not charge the customer or reopen an invoice.',
              ),
            ],
          ),
        );
        if (confirmed != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
      await widget.save(
        ServiceTaskDraft(
          job: _job,
          newCustomer: _customer,
          newVehicle: _vehicle,
          description: _description.text.trim(),
          mechanics: _mechanics,
          start: LocalTaskSchedule.day(_start),
          end: LocalTaskSchedule.day(_end),
          priority: _priority,
          status: _treatment == 'paid' ? 'Done' : _status,
          treatment: _treatment,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: _editorTheme(context),
    child: Builder(builder: _buildEditor),
  );

  Widget _buildEditor(BuildContext context) {
    final job = widget.jobs.where((j) => j['id'] == _job).firstOrNull;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
          title: Text(
            widget.editing ? 'Edit Service Task' : 'New Service Task',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      _jobHeader(job),
                      if (widget.onLinkInvoiceLabor != null && !widget.editing)
                        TextButton(
                          onPressed: _saving ? null : widget.onLinkInvoiceLabor,
                          child: const Text('Use saved invoice labor'),
                        ),
                      if (_job == 'new') ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Customer for new job'),
                          subtitle: Text(
                            (_customer?['display_name'] ??
                                    _customer?['name'] ??
                                    'Choose customer')
                                .toString(),
                          ),
                          onTap: _saving || widget.pickCustomer == null
                              ? null
                              : () async {
                                  final c = await widget.pickCustomer!();
                                  if (c != null && mounted) {
                                    setState(() {
                                      _customer = c;
                                      _vehicle = null;
                                    });
                                  }
                                },
                        ),
                        if (_customer != null)
                          DropdownButtonFormField<String>(
                            key: ValueKey(_customer!['id']),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Vehicle (optional)',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('No vehicle'),
                              ),
                              for (final raw
                                  in _customer!['vehicles'] as List? ?? [])
                                if (raw is Map)
                                  DropdownMenuItem(
                                    value: raw['id'].toString(),
                                    child: Text(
                                      '${raw['year'] ?? ''} ${raw['make'] ?? ''} ${raw['model'] ?? ''}',
                                    ),
                                  ),
                            ],
                            onChanged: _saving
                                ? null
                                : (id) => setState(
                                    () => _vehicle =
                                        (_customer!['vehicles'] as List? ?? [])
                                            .whereType<Map>()
                                            .where((v) => v['id'] == id)
                                            .map(Map<String, dynamic>.from)
                                            .firstOrNull,
                                  ),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Creates a new job with this task. No customer invoice charge.',
                        ),
                      ],
                      const SizedBox(height: 16),
                      _heading('Task Description'),
                      TextFormField(
                        key: const ValueKey('task-description'),
                        controller: _description,
                        readOnly: widget.invoiceLabor || _saving,
                        minLines: 2,
                        maxLines: 4,
                        autocorrect: true,
                        enableSuggestions: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Describe the work',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a task description'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _heading('Mechanic Assignment'),
                      for (var i = 0; i < _mechanics.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _pair(
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'mechanic-$i-${_mechanics[i].employee}',
                            ),
                            initialValue: _mechanics[i].employee.isEmpty
                                ? null
                                : _mechanics[i].employee,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Mechanic',
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                            items: [
                              for (final e in widget.employees)
                                DropdownMenuItem(
                                  value: e['id'] as String,
                                  child: Text(
                                    (e['nickname'] ?? e['name'] ?? e['id'])
                                        .toString(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _saving || _mechanics[i].locked
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(
                                        () => _mechanics[i].employee = v,
                                      );
                                    }
                                  },
                          ),
                          TextFormField(
                            key: ValueKey('hours-$i'),
                            initialValue: (_mechanics[i].minutes / 60)
                                .toStringAsFixed(2),
                            readOnly: _saving || _mechanics[i].locked,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Assigned Hours',
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                            validator: (v) {
                              final h = double.tryParse(v ?? '');
                              return h == null ||
                                      !h.isFinite ||
                                      h < 0 ||
                                      h > 10000
                                  ? 'Enter valid assigned hours'
                                  : null;
                            },
                            onChanged: (v) {
                              final h = double.tryParse(v);
                              if (h != null && h.isFinite) {
                                _mechanics[i].minutes = (h * 60).round();
                              }
                            },
                          ),
                        ),
                      ],
                      if (!widget.editing || _mechanics.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () => setState(
                                    () => _mechanics.add(
                                      TaskMechanicDraft('', 0),
                                    ),
                                  ),
                            icon: const Icon(Icons.person_add_outlined),
                            label: const Text('Add mechanic'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _heading('Work Dates'),
                      _pair(_dateField(true), _dateField(false)),
                      const SizedBox(height: 16),
                      _pair(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _heading('Priority'),
                            DropdownButtonFormField<String>(
                              key: const ValueKey('task-priority'),
                              initialValue: _priority,
                              isExpanded: true,
                              decoration: const InputDecoration(),
                              items: [
                                for (final p in ['High', 'Normal', 'Low'])
                                  DropdownMenuItem(
                                    value: p,
                                    child: _priorityValue(p),
                                  ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _priority = v!),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _heading('Work Status'),
                            DropdownButtonFormField<String>(
                              key: const ValueKey('task-status'),
                              initialValue: _status,
                              isExpanded: true,
                              decoration: const InputDecoration(),
                              items: [
                                for (final p in ['Open', 'In Progress', 'Done'])
                                  DropdownMenuItem(
                                    value: p,
                                    child: _statusValue(p),
                                  ),
                              ],
                              onChanged: _saving || widget.statusLocked
                                  ? null
                                  : (v) => setState(() => _status = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _heading('Payroll Treatment'),
                      if (widget.payrollLocked)
                        const InputDecorator(
                          decoration: InputDecoration(
                            fillColor: Color(0xFFF2F4F2),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 20,
                                color: Color(0xFF606A62),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Paid labor: retain existing status',
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: const ValueKey('task-payroll-treatment'),
                          isDense:
                              MediaQuery.textScalerOf(context).scale(16) <= 21,
                          itemHeight: null,
                          initialValue: _treatment,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'preserve',
                              child: Text('Retain existing paid/unpaid status'),
                            ),
                            DropdownMenuItem(
                              value: 'unpaid',
                              child: Text('Unpaid when completed'),
                            ),
                            DropdownMenuItem(
                              value: 'paid',
                              child: Text('Already paid — historical'),
                            ),
                            DropdownMenuItem(
                              value: 'review',
                              child: Text('Needs review — not payable'),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _treatment = v!),
                        ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _pale,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: _green,
                              size: 23,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.payrollLocked
                                    ? 'Paid labor stays paid. Editing work dates and priority does not change payments.'
                                    : 'Task dates do not change customer charges or record a payroll payment.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving…' : 'Save Task'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
