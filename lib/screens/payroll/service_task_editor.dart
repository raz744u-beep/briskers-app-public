import '../../widgets/owner_confirmation_dialog.dart';
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
    this.newCustomer,this.newVehicle,
  });
  final String job, description, start, end, priority, status, treatment;
  final List<TaskMechanicDraft> mechanics;
  final Map<String,dynamic>? newCustomer,newVehicle;
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
  });
  final List<Map<String, dynamic>> jobs, employees;
  final ServiceTaskDraft initial;
  final Future<void> Function(ServiceTaskDraft) save;
  final bool editing, invoiceLabor, statusLocked, payrollLocked;
  final VoidCallback? onLinkInvoiceLabor;
  final Future<Map<String,dynamic>?> Function()? pickCustomer;
  @override
  State<ServiceTaskEditor> createState() => _ServiceTaskEditorState();
}

class _ServiceTaskEditorState extends State<ServiceTaskEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _description;
  late String _job, _priority, _status, _treatment;
  late DateTime _start, _end;
  late List<TaskMechanicDraft> _mechanics;
  Map<String,dynamic>? _customer,_vehicle;
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

  String _label(Map<String, dynamic> j) => [
    j['job_number'],
    j['customer_name'],
    j['vehicle_label'],
    j['title'],
  ].where((s) => s != null && s.toString().isNotEmpty).join(' · ');
  Future<void> _date(bool start) async {
    final d = await showDatePicker(
      context: context,
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
    if (_job.isEmpty || (_job=='new' && _customer==null) ||
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
      if(_treatment=='paid') {
        final confirmed=await showDialog<bool>(context:context,builder:(_)=>OwnerConfirmationDialog(title:'Mark as Already Paid',confirm:'Confirm historical payment',sections:[
          Text(_description.text.trim(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:18)),
          const SizedBox(height:8),
          for(final m in _mechanics)Text('${widget.employees.where((e)=>e['id']==m.employee).firstOrNull?['name']??m.employee} · ${(m.minutes/60).toStringAsFixed(2)} hours'),
          const Divider(height:24),
          const Text('Confirm these wages were already paid.\n\n• Marks these task portions Done and already paid.\n• Excludes these hours from future unpaid payroll.\n• Keeps existing tasks and financial history.\n• Does not create a payment or expense.\n• Does not charge the customer or reopen an invoice.'),
        ]));
        if(confirmed!=true){if(mounted)setState(()=>_saving=false);return;}
      }
      await widget.save(
        ServiceTaskDraft(
          job: _job,
        newCustomer:_customer,newVehicle:_vehicle,
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
  Widget build(BuildContext context) {
    final job = widget.jobs.where((j) => j['id'] == _job).firstOrNull;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            widget.editing ? 'Edit Service Task' : 'New Service Task',
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Job'),
                        subtitle: Text(
                          job == null ? 'Choose a job' : _label(job),
                        ),
                        trailing: const Icon(Icons.expand_more),
                        onTap: widget.editing || _saving
                            ? null
                            : () async {
                                final selected = await showJobTaskSelection(
                                  context,
                                  widget.jobs,
                                  allowNew: widget.pickCustomer!=null,
                                );
                                if (selected != null && mounted) {
                                  setState(() {
                                    _job = selected;
                                    final lead = widget.jobs
                                        .where((j) => j['id'] == selected)
                                        .firstOrNull?['assigned_employee_id'];
                                    if (lead is String &&
                                        widget.employees.any(
                                          (e) => e['id'] == lead,
                                        ) &&
                                        _mechanics.length == 1) {
                                      _mechanics = [
                                        TaskMechanicDraft(
                                          lead,
                                          _mechanics.single.minutes,
                                        ),
                                      ];
                                    }
                                  });
                                }
                              },
                      ),
                      if(widget.onLinkInvoiceLabor!=null && !widget.editing)TextButton(onPressed:_saving?null:widget.onLinkInvoiceLabor,child:const Text('Use saved invoice labor')),
                      if(_job=='new')...[
                        ListTile(contentPadding:EdgeInsets.zero,title:const Text('Customer for new job'),subtitle:Text((_customer?['display_name']??_customer?['name']??'Choose customer').toString()),onTap:_saving||widget.pickCustomer==null?null:()async{final c=await widget.pickCustomer!();if(c!=null && mounted)setState((){_customer=c;_vehicle=null;});}),
                        if(_customer!=null)DropdownButtonFormField<String>(key:ValueKey(_customer!['id']),isExpanded:true,decoration:const InputDecoration(labelText:'Vehicle (optional)'),items:[const DropdownMenuItem(value:'',child:Text('No vehicle')),for(final raw in _customer!['vehicles'] as List? ?? [])if(raw is Map)DropdownMenuItem(value:raw['id'].toString(),child:Text('${raw['year']??''} ${raw['make']??''} ${raw['model']??''}'))],onChanged:_saving?null:(id)=>setState(()=>_vehicle=(_customer!['vehicles'] as List? ?? []).whereType<Map>().where((v)=>v['id']==id).map(Map<String,dynamic>.from).firstOrNull)),
                        const Text('Creates a new job with this task. No customer invoice charge.'),
                      ],
                      TextFormField(
                        controller: _description,
                        readOnly: widget.invoiceLabor || _saving,
                        minLines: 2,
                        maxLines: 4,
                        autocorrect: true,
                        enableSuggestions: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Task description',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a task description'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Mechanic assignments',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      for (var i = 0; i < _mechanics.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
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
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Assigned hours',
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
                              if (_mechanics[i].locked)
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Paid labor: mechanic and hours are retained.',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (!widget.editing || _mechanics.isEmpty)
                        TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () =>
                                      _mechanics.add(TaskMechanicDraft('', 0)),
                                ),
                          icon: const Icon(Icons.person_add_outlined),
                          label: const Text('Add mechanic'),
                        ),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving ? null : () => _date(true),
                            icon: const Icon(Icons.calendar_month),
                            label: Text(
                              'Start Date: ${LocalTaskSchedule.day(_start)}',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : () => _date(false),
                            icon: const Icon(Icons.event),
                            label: Text(
                              'End Date: ${LocalTaskSchedule.day(_end)}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: [
                          for (final p in ['High', 'Normal', 'Low'])
                            DropdownMenuItem(value: p, child: Text(p)),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _priority = v!),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Work status',
                        ),
                        items: [
                          for (final p in ['Open', 'In Progress', 'Done'])
                            DropdownMenuItem(
                              value: p,
                              child: Text(p == 'Open' ? 'Not Started' : p),
                            ),
                        ],
                        onChanged: _saving || widget.statusLocked
                            ? null
                            : (v) => setState(() => _status = v!),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _treatment,
                        decoration: const InputDecoration(
                          labelText: 'Payroll treatment',
                        ),
                        items: const [
                          DropdownMenuItem(value:'preserve',child:Text('Retain existing paid/unpaid status')),
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
                        onChanged: _saving || widget.payrollLocked
                            ? null
                            : (v) => setState(() => _treatment = v!),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Task dates do not change customer charges or record a payroll payment.',
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
