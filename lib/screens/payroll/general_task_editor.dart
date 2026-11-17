import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'task_selection_dialog.dart';
import 'approved_tasks_ui.dart';
import '../../widgets/briskers_module_dock.dart';

class GeneralTaskEditor extends StatefulWidget {
  const GeneralTaskEditor({
    super.key,
    required this.employees,
    required this.jobs,
    required this.initial,
    required this.save,
    this.sharedBottomNavigationBar,
  });
  final List<Map<String, dynamic>> employees, jobs;
  final Widget? sharedBottomNavigationBar;
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<GeneralTaskEditor> createState() => _GeneralTaskEditorState();
}

class _GeneralTaskEditorState extends State<GeneralTaskEditor> {
  late TextEditingController _description;
  late String _employee, _category;
  String? _job, _error;
  DateTime? _due;
  bool _reminder = false, _saving = false;
  int _minutes = 0;
  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _description = TextEditingController(
      text: v['description'] as String? ?? '',
    );
    _employee = v['employee_id'] as String? ?? '';
    _category = v['category'] as String? ?? 'General';
    _job = v['job_id'] as String?;
    _due = v['due_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(v['due_at'] as int);
    _reminder = v['reminder_enabled'] == 1;
    _minutes = v['reminder_minutes'] as int? ?? 0;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _description.text != (widget.initial['description'] ?? '') ||
      _employee != (widget.initial['employee_id'] ?? '') ||
      _category != (widget.initial['category'] ?? 'General') ||
      _job != widget.initial['job_id'] ||
      _due?.millisecondsSinceEpoch != widget.initial['due_at'] ||
      _reminder != (widget.initial['reminder_enabled'] == 1) ||
      _minutes != (widget.initial['reminder_minutes'] ?? 0);

  Future<void> _leave([VoidCallback? navigate]) async {
    if (_saving) return;
    if (!_dirty) {
      if (navigate == null) {
        Navigator.pop(context, false);
      } else {
        navigate();
      }
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this task?'),
        content: const Text('Choose how to handle your unsaved changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save and leave')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'discard') {
      if (navigate == null) {
        Navigator.pop(context, false);
      } else {
        navigate();
      }
    }
    if (action == 'save') await _save(navigate);
  }

  Future<void> _save([VoidCallback? navigate]) async {
    if (_saving) return;
    if (_employee.isEmpty ||
        _description.text.trim().isEmpty ||
        (_reminder &&
            (_due == null ||
                !_due!
                    .subtract(Duration(minutes: _minutes))
                    .isAfter(DateTime.now())))) {
      setState(
        () => _error =
            'Choose an assignee, enter a description, and use a future reminder time.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save({
        'employee_id': _employee,
        'description': _description.text.trim(),
        'category': _category,
        'job_id': _job,
        'due_at': _due?.millisecondsSinceEpoch,
        'reminder_enabled': _reminder ? 1 : 0,
        'reminder_minutes': _minutes,
      });
      if (mounted) {
        if (navigate == null) {
          Navigator.pop(context, true);
        } else {
          navigate();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dock = widget.sharedBottomNavigationBar;
    final job = widget.jobs.where((j) => j['id'] == _job).firstOrNull;
    return PopScope(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) _leave(); },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: taskCanvas,
        bottomNavigationBar: dock is BriskersModuleDock
            ? BriskersModuleDock(
                selectedIndex: dock.selectedIndex, destinations: dock.destinations,
                onSelected: (index) => _leave(() => dock.onSelected(index)),
                onBadgeSelected: (index) => _leave(() => (dock.onBadgeSelected ?? dock.onSelected)(index)),
              )
            : null,
        appBar: ApprovedTasksHeader(
          title: widget.initial['id'] == null ? 'New General Task' : 'Edit General Task',
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Card(child: ListTile(
                      leading: Icon(Icons.assignment_outlined, color: taskGreen),
                      title: Text('General Task', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('Create a non-labor task, reminder, or follow-up.'),
                    )),
                    const SizedBox(height: 8),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    TextField(
                      controller: _description,
                      onChanged: (_) => setState(() {}),
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 5,
                      autocorrect: true,
                      enableSuggestions: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Task description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final fields = [
                    DropdownButtonFormField<String>(
                      initialValue: _employee.isEmpty ? null : _employee,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Assignee', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                      items: [
                        for (final e in widget.employees)
                          DropdownMenuItem(
                            value: e['id'] as String,
                            child: Text(
                              (e['nickname'] ?? e['name'] ?? e['id'])
                                  .toString(),
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _employee = v!),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.sell_outlined), border: OutlineInputBorder()),
                      items: [
                        for (final c in {
                          _category,
                          'General',
                          'Cleaning',
                          'Inventory',
                          'Office',
                          'Maintenance',
                          'Yard',
                          'Errands',
                        })
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _category = v!),
                    ),
                      ];
                      return constraints.maxWidth < 340
                          ? Column(children: [fields[0], const SizedBox(height: 8), fields[1]])
                          : Row(children: [
                              Expanded(child: fields[0]), const SizedBox(width: 8),
                              Expanded(child: fields[1]),
                            ]);
                    }),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.directions_car_outlined, color: taskNavy),
                      title: const Text('Job (optional)'),
                      subtitle: Text(
                        job == null
                            ? 'No linked job'
                            : '${job['job_number']} · ${job['customer_name']}\n${job['vehicle_label'] ?? ''}',
                      ),
                      trailing: _job == null
                          ? const Icon(Icons.expand_more)
                          : IconButton(
                              tooltip: 'Remove job link',
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _job = null),
                              icon: const Icon(Icons.close),
                            ),
                      onTap: _saving
                          ? null
                          : () async {
                              final id = await showJobTaskSelection(
                                context,
                                widget.jobs,
                                allowNew: false,
                              );
                              if (id != null && mounted) {
                                setState(() => _job = id);
                              }
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_month_outlined, color: taskNavy),
                      title: const Text('Due date and time'),
                      subtitle: Text(
                        _due == null
                            ? 'Not set'
                            : DateFormat.yMMMd().add_jm().format(_due!),
                      ),
                      trailing: const Icon(Icons.event),
                      onTap: _saving
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _due ?? DateTime.now(),
                                firstDate: DateTime(1990),
                                lastDate: DateTime(2100),
                              );
                              if (date == null || !context.mounted) return;
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(
                                  _due ?? DateTime.now(),
                                ),
                              );
                              if (time != null && mounted) {
                                setState(
                                  () => _due = DateTime(
                                    date.year,
                                    date.month,
                                    date.day,
                                    time.hour,
                                    time.minute,
                                  ),
                                );
                              }
                            },
                    ),
                    if (_due != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _due = null;
                                _reminder = false;
                              }),
                        child: const Text('Clear due date'),
                      ),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_none, color: taskNavy),
                      title: const Text('Phone Reminder'),
                      activeThumbColor: taskGreen,
                      subtitle: const Text(
                        'Works offline. Android may delay reminders while the phone is idle.',
                      ),
                      value: _reminder,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _reminder = v),
                    ),
                    if (_reminder)
                      DropdownButtonFormField<int>(
                        initialValue: _minutes,
                        decoration: const InputDecoration(
                          labelText: 'Reminder time',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('At due time'),
                          ),
                          DropdownMenuItem(
                            value: 15,
                            child: Text('15 minutes before'),
                          ),
                          DropdownMenuItem(
                            value: 60,
                            child: Text('1 hour before'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _minutes = v!),
                      ),
                  ],
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
                            : _leave,
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: taskGreen),
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: FittedBox(fit: BoxFit.scaleDown,
                          child: Text(_saving ? 'Saving…' : 'Save General Task')),
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
