import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'task_selection_dialog.dart';

class GeneralTaskEditor extends StatefulWidget {
  const GeneralTaskEditor({
    super.key,
    required this.employees,
    required this.jobs,
    required this.initial,
    required this.save,
  });
  final List<Map<String, dynamic>> employees, jobs;
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

  Future<void> _save() async {
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
      if (mounted) Navigator.pop(context, true);
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
    final job = widget.jobs.where((j) => j['id'] == _job).firstOrNull;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            widget.initial['id'] == null
                ? 'New General Task'
                : 'Edit General Task',
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    TextField(
                      controller: _description,
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
                    DropdownButtonFormField<String>(
                      initialValue: _employee.isEmpty ? null : _employee,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Assignee'),
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
                      decoration: const InputDecoration(labelText: 'Category'),
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
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
                      contentPadding: EdgeInsets.zero,
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
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Remind me on this device'),
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
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving…' : 'Save General Task'),
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
