// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/service_task_order.dart';

/// Tasks workspace. Only customer/job-linked records appear
/// under Service Tasks. General Tasks can reference a job without billing it.
class TasksWorkspace extends StatefulWidget {
  const TasksWorkspace({
    super.key,
    required this.serviceTasks,
    required this.generalTasks,
    required this.allocationsByLine,
    required this.employeeName,
    required this.employeeIds,
    required this.serviceTaskCard,
    required this.onAddGeneral,
    required this.onGeneralStatus,
    required this.onOpenJob,
    required this.onEmployeeTap,
    this.initialGeneral = false,
    this.scopedJob,
    this.onAddService,
    this.onAddRecheck,
    this.onRecoverHistory,
  });

  final List<Map<String, dynamic>> serviceTasks;
  final List<Map<String, dynamic>> generalTasks;
  final Map<String, List<Map<String, dynamic>>> allocationsByLine;
  final String Function(String?) employeeName;
  final List<String> employeeIds;
  final Widget Function(Map<String,dynamic>) serviceTaskCard;
  final VoidCallback onAddGeneral;
  final VoidCallback? onAddService;
  final ValueChanged<String>? onAddRecheck;
  final VoidCallback? onRecoverHistory;
  final Future<void> Function(int taskId, String status) onGeneralStatus;
  final ValueChanged<String> onOpenJob;
  final ValueChanged<String> onEmployeeTap;
  final bool initialGeneral;
  final String? scopedJob;

  @override
  State<TasksWorkspace> createState() => _TasksWorkspaceState();
}

class _TasksWorkspaceState extends State<TasksWorkspace> {
  late bool _general;
  final _search = TextEditingController();
  String _employee = '';
  String _status = 'Active';
  String _kind = 'All Types';
  String _category = 'All Categories';
  String _job = 'All Jobs';
  String _date = 'Any';
  String _servicePeriod = 'Any time';
  String _sort = 'Newest First';
  final Set<String> _expandedJobs = <String>{};

  @override
  void initState() {
    super.initState();
    _general = widget.initialGeneral;
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() { if (mounted) setState(() {}); }

  String _statusName(Object? v) {
    switch (v?.toString()) {
      case 'in_progress': return 'In Progress';
      case 'done': return 'Done';
      default: return 'Not Started';
    }
  }

  bool _matchesStatus(Map<String,dynamic> row) {
    final status = _statusName(row['status']);
    if (_status == 'Unpaid') {
      return status == 'Done' &&
          (row['remaining_minutes'] as int? ?? 0) > 0;
    }
    if (_status == 'Paid') {
      return status == 'Done' && row['paid'] == 1;
    }
    return _status == 'All' ||
      (_status == 'Active' && status != 'Done') ||
      status == _status;
  }

  bool _matchesEmployee(Map<String,dynamic> row, {required bool general}) {
    if (_employee.isEmpty) return true;
    if (general) return row['employee_id']?.toString() == _employee;
    final line = row['line_id']?.toString() ?? '';
    final allocations = widget.allocationsByLine[line] ?? const [];
    if (allocations.isNotEmpty) {
      return allocations.any((a) => a['employee_id']?.toString() == _employee);
    }
    return row['employee_id']?.toString() == _employee;
  }

  bool _matchesDate(Map<String,dynamic> row) {
    if (_date == 'Any') return true;
    final raw = row['due_at'];
    if (raw is! int) return false;
    final due = DateTime.fromMillisecondsSinceEpoch(raw);
    final now = DateTime.now();
    final day = DateTime(now.year,now.month,now.day);
    final date = DateTime(due.year,due.month,due.day);
    if (_date == 'Today') return date == day;
    if (_date == 'This Week') {
      final monday = day.subtract(Duration(days: day.weekday - 1));
      return !date.isBefore(monday) &&
        date.isBefore(monday.add(const Duration(days: 7)));
    }
    if (_date == 'Overdue') return date.isBefore(day);
    return true;
  }

  // Service periods use actual saved Job/invoice/completion dates—not
  // list position or invoice number. Unknown dates stay visible only when
  // the Owner chooses All time; this prevents fabricated recent activity.
  bool _matchesServicePeriod(Map<String,dynamic> row) {
    if (_servicePeriod == 'Any time') return true;
    final isDone = _statusName(row['status']) == 'Done';
    final completed = isDone
        ? ServiceTaskOrder.timestamp(row['completed_date']) : 0;
    final timestamp = completed > 0 ? completed :
        ServiceTaskOrder.timestamp(row['invoice_date'] ??
          row['invoice_created_at'] ?? row['job_created_at'] ??
          row['job_document_date']);
    if (timestamp <= 0) return false;
    final event = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final date = DateTime(event.year,event.month,event.day);
    final now=DateTime.now();
    final day=DateTime(now.year,now.month,now.day);
    final weekStart=day.subtract(Duration(days:day.weekday-1));
    switch (_servicePeriod) {
      case 'This week':
        return !date.isBefore(weekStart) &&
            date.isBefore(weekStart.add(const Duration(days:7)));
      case 'Last week':
        return !date.isBefore(weekStart.subtract(const Duration(days:7))) &&
            date.isBefore(weekStart);
      case 'Last 7 days':
        return !date.isBefore(day.subtract(const Duration(days:6))) &&
            !date.isAfter(day);
      case 'Last 30 days':
        return !date.isBefore(day.subtract(const Duration(days:29))) &&
            !date.isAfter(day);
      case 'Last 90 days':
        return !date.isBefore(day.subtract(const Duration(days:89))) &&
            !date.isAfter(day);
      default:
        return true;
    }
  }

  List<Map<String,dynamic>> get _service {
    final q = _search.text.toLowerCase().trim();
    final rows = widget.serviceTasks.where((task) {
      if(widget.scopedJob != null && task['job_id'] != widget.scopedJob) return false;
      final desc = (task['custom_description'] ??
        task['source_description'] ?? '').toString().toLowerCase();
      // Task-first Job work and rechecks both lack an invoice line. The
      // saved source kind distinguishes them; absence of an invoice alone
      // must not relabel ordinary Job work as a recheck.
      final sourceKind = task['source_kind']?.toString();
      final isInvoice = sourceKind == 'invoice' ||
          (sourceKind == null && task['document_id'] != null);
      if (_kind == 'Invoice Labor' && !isInvoice) return false;
      if (_kind == 'Rechecks' && sourceKind != 'recheck') return false;
      if (_job != 'All Jobs' &&
          task['job_id']?.toString() != _job) return false;
      return task['source_missing'] != 1 &&
        _matchesStatus(task) && _matchesEmployee(task,general:false) &&
        _matchesServicePeriod(task) &&
        (q.isEmpty || desc.contains(q) ||
          (task['job_number']?.toString().toLowerCase().contains(q) ?? false) ||
          widget.employeeName(task['employee_id']?.toString())
            .toLowerCase().contains(q));
    }).toList();
    rows.sort((a,b)=>ServiceTaskOrder.compareLines(a,b,newest:_sort!='Oldest First'));
    return rows;
  }

  List<Map<String,dynamic>> get _internal {
    final q = _search.text.toLowerCase().trim();
    final rows = widget.generalTasks.where((task) {
      if(widget.scopedJob != null && task['job_id'] != widget.scopedJob) return false;
      final description = task['description']?.toString().toLowerCase() ?? '';
      return _matchesStatus(task) &&
        _matchesEmployee(task,general:true) &&
        (_category == 'All Categories' ||
          task['category']?.toString() == _category) &&
        _matchesDate(task) &&
        (q.isEmpty || description.contains(q) ||
          widget.employeeName(task['employee_id']?.toString())
            .toLowerCase().contains(q));
    }).toList();
    rows.sort((a,b) {
      if (_sort == 'Due Date') {
        final left = a['due_at'] as int? ?? 9223372036854775807;
        final right = b['due_at'] as int? ?? 9223372036854775807;
        return left.compareTo(right);
      }
      final d = ((b['id'] as int?)??0).compareTo((a['id'] as int?)??0);
      return _sort == 'Oldest First' ? -d : d;
    });
    return rows;
  }

  Widget _picker(String title, String chosen, List<String> items,
      void Function(String) onChange) {
    return PopupMenuButton<String>(
      tooltip:title,
      onOpened: () => FocusManager.instance.primaryFocus?.unfocus(),
      onSelected: (value) {
        FocusManager.instance.primaryFocus?.unfocus();
        onChange(value);
      },
      itemBuilder: (_) => [
        for (final item in items)
          PopupMenuItem(value:item,child: Text(item)),
      ],
      child:Container(
        width:double.infinity,
        constraints:const BoxConstraints(minHeight:37),
        padding:const EdgeInsets.symmetric(horizontal:9,vertical:4),
        decoration:BoxDecoration(
          color: Colors.white,
          border: Border.all(color:const Color(0xFF8A9CAA),width:1.2),
          borderRadius:BorderRadius.circular(18)),
        child:Row(children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
            mainAxisSize:MainAxisSize.min,children:[
            Text(title,maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:11,
                fontWeight:FontWeight.w600,color:Color(0xFF475569))),
            const SizedBox(height:1),
            Text(chosen,maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:13,
                color:Color(0xFF1E293B),fontWeight:FontWeight.w800)),
          ])),
          const SizedBox(width:5),
          const Icon(Icons.keyboard_arrow_down,size:16),
        ]),
      ),
    );
  }

  List<String> get _employeeChoices =>
    ['All Employees',
     for (final id in widget.employeeIds) _employeeLabel(id)];

  String _employeeLabel(String id) {
    final name = widget.employeeName(id);
    final matching = widget.employeeIds.where((candidate) =>
        widget.employeeName(candidate) == name);
    return matching.length == 1 ? name : '$name · $id';
  }

  String _employeeIdForName(String name) {
    if (name == 'All Employees') return '';
    for (final id in widget.employeeIds) {
      if (_employeeLabel(id) == name) return id;
    }
    return '';
  }

  Future<void> _filters() async {
    var employee = _employee;
    var status = _status, type = _kind, category = _category;
    var job = _job, date = _date, sort = _sort, period = _servicePeriod;
    await showModalBottomSheet<void>(
      context:context,isScrollControlled:true,useSafeArea:true,
      showDragHandle:true,
      builder:(sheet)=>StatefulBuilder(builder:(context,refresh) {
        Widget dropdown(String name,String value,List<String> values,
            void Function(String) update) => Padding(
          padding:const EdgeInsets.only(bottom:10),
          child:DropdownButtonFormField<String>(
            initialValue:value,isExpanded:true,
            decoration:InputDecoration(labelText:name,
              border:OutlineInputBorder(
                borderRadius:BorderRadius.circular(14))),
            items:[for(final choice in values)
              DropdownMenuItem(value:choice,child:Text(choice,
                overflow:TextOverflow.ellipsis))],
            onChanged:(v){if(v!=null) refresh(()=>update(v));},
          ),
        );
        return Padding(
          padding:EdgeInsets.fromLTRB(16,8,16,
            MediaQuery.viewInsetsOf(context).bottom+16),
          child:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Row(children:[
                const Expanded(child:Text('Task Filters',
                  style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),
                TextButton(onPressed:()=>refresh((){
                  employee='';status='Active';type='All Types';
                  category='All Categories';job='All Jobs';
                  date='Any';sort='Newest First';period='Any time';
                }),child:const Text('Reset')),
              ]),
              dropdown('Employee',employee.isEmpty ? 'All Employees' :
                _employeeLabel(employee),_employeeChoices,
                (v)=>employee=_employeeIdForName(v)),
              if(!_general) ...[
                if(widget.scopedJob==null) dropdown('Job',job,['All Jobs',
                  for(final id in widget.serviceTasks
                    .map((t)=>t['job_id']?.toString()??'')
                    .where((e)=>e.isNotEmpty).toSet()) id],
                  (v)=>job=v),
                dropdown('Task Type',type,
                  ['All Types','Invoice Labor','Rechecks'],(v)=>type=v),
                dropdown('Period',period,
                  ['Any time','This week','Last week','Last 7 days',
                   'Last 30 days','Last 90 days'],(v)=>period=v),
              ] else ...[
                dropdown('Category',category,
                  ['All Categories','General','Cleaning','Inventory','Office',
                   'Maintenance','Yard','Errands'],(v)=>category=v),
                dropdown('Due Date',date,
                  ['Any','Today','This Week','Overdue'],(v)=>date=v),
              ],
              dropdown('Status',status,
                ['Active','Unpaid','Paid','All','Not Started','In Progress','Done'],
                (v)=>status=v),
              dropdown('Sort By',sort,
                ['Newest First','Oldest First','Due Date']
                  .where((s)=>_general||s!='Due Date').toList(),
                (v)=>sort=v),
              if (widget.onRecoverHistory != null) ...[
                const SizedBox(height:8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onRecoverHistory!();
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('Recover missing historical invoice tasks'),
                ),
              ],
              const SizedBox(height:8),
              FilledButton(
                onPressed:(){
                  setState((){
                    _employee=employee;_status=status;_kind=type;
                    _category=category;_job=job;_date=date;_sort=sort;
                    _servicePeriod=period;
                  });
                  Navigator.pop(context);
                },
                child:const Text('Apply Filters')),
            ],
          )),
        );
      }),
    );
  }

  Widget _serviceView() {
    final rows = _service;
    final byJob = <String,List<Map<String,dynamic>>>{};
    for(final task in rows) {
      final id=task['job_id']?.toString()??'Unlinked Job';
      byJob.putIfAbsent(id,()=>[]).add(task);
    }
    final entries=byJob.entries.toList()..sort((a,b)=>ServiceTaskOrder.compareJobs(a.value.first,b.value.first,newest:_sort!='Oldest First'));
    return ListView(
      key:const Key('service-tasks-list'),
      padding:const EdgeInsets.fromLTRB(12,8,12,28),
      children:[
        Row(children:[Expanded(child:Text('Jobs with Tasks · '+entries.length.toString(),
          style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15))),
          if(widget.scopedJob==null && widget.onAddService!=null)TextButton.icon(onPressed:widget.onAddService,icon:const Icon(Icons.add),label:const Text('New Task'))]),
        const SizedBox(height:9),
        if(entries.isEmpty)
          Padding(padding:const EdgeInsets.all(15),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text(widget.serviceTasks.isEmpty
                  ? 'No service tasks are available in this view. This does not mean invoice labor or payment history was deleted.'
                  : 'No service tasks match these filters. Your saved work may be completed, paid, or historical.'),
                if(_status!='All' && widget.serviceTasks.isNotEmpty)
                  TextButton.icon(
                    key:const Key('show-all-service-task-statuses'),
                    onPressed:()=>setState(()=>_status='All'),
                    icon:const Icon(Icons.history),
                    label:const Text('Show all task statuses'),
                  ),
              ])),
        for(final entry in entries) ...[
          Card(color:const Color(0xFFF0F5FA),margin:const EdgeInsets.only(bottom:9),
            child:Column(children:[
              ListTile(
                onTap:()=>setState((){
                  if(!_expandedJobs.add(entry.key)) {
                    _expandedJobs.remove(entry.key);
                  }
                }),
                title:Text(() {
                  final jobNumber = entry.value.first['job_number']?.toString() ?? 'Job';
                  final invoice = entry.value.map((row) =>
                    row['invoice_number']?.toString().trim()).whereType<String>()
                    .where((number) => number.isNotEmpty).firstOrNull;
                  return invoice == null ? jobNumber : '$jobNumber · Invoice #$invoice';
                }(),style:const TextStyle(fontWeight:FontWeight.w800)),
                subtitle:Text([
                  if (entry.value.first['customer_name'] case final String customer) customer,
                  if (entry.value.first['vehicle_label'] case final String vehicle) vehicle,
                  '${entry.value.length} tasks',
                ].join(' · ')),
                trailing:Icon(_expandedJobs.contains(entry.key)
                  ? Icons.expand_less:Icons.expand_more),
              ),
              if(_expandedJobs.contains(entry.key)) ...[
                const Divider(height:1),
                // Match the approved isolated Tasks TEST: a distinct white
                // rounded work card sits inside each tinted Job group.
                for(final task in entry.value)
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    margin: const EdgeInsets.fromLTRB(10,8,10,5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFD4DFE4)),
                    ),
                    child: ExpansionTile(
                      key: ValueKey(task['line_id']),
                      title: Text((task['source_description'] ?? task['description'] ?? 'Labor task').toString()),
                      children: [Builder(builder: (_) => widget.serviceTaskCard(task))],
                    ),
                  ),
                // A missing Job link is display-only. Never dispatch a
                // fabricated label as a canonical Job ID for a recheck.
                if (entry.key != 'Unlinked Job') ...[
                  TextButton.icon(onPressed:()=>widget.onOpenJob(entry.key),
                    icon:const Icon(Icons.open_in_new,size:17),
                    label:const Text('Open Job Details')),
                  if (widget.onAddRecheck != null)
                    TextButton.icon(
                      onPressed: () => widget.onAddRecheck!(entry.key),
                      icon: const Icon(Icons.add_task_outlined, size: 17),
                      label: const Text('Add Recheck'),
                    ),
                ],
                const SizedBox(height:5),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  Widget _generalView() {
    final tasks = _internal;
    return ListView(
      key:const Key('general-tasks-list'),
      padding:const EdgeInsets.fromLTRB(12,8,12,32),
      children:[
        Row(children:[
          Expanded(child:Text('General Tasks · '+tasks.length.toString(),
            style:const TextStyle(fontSize:15,fontWeight:FontWeight.w800))),
          if(widget.scopedJob==null) TextButton.icon(onPressed:widget.onAddGeneral,
            icon:const Icon(Icons.add),label:const Text('New Task')),
        ]),
        if(tasks.isEmpty)
          const Padding(padding:EdgeInsets.all(15),
            child:Text('No general tasks match these filters.')),
        for(final task in tasks)
          Card(
            key:ValueKey('general-task-'+task['id'].toString()),
            margin:const EdgeInsets.only(bottom:7),
            child:ExpansionTile(
              leading: Icon(task['status']=='done'
                ? Icons.check_circle: Icons.radio_button_unchecked,
                color:task['status']=='done' ?
                  const Color(0xFF167A54):BriskersColors.jobs),
              title:Text(task['description']?.toString()??'',
                style:const TextStyle(fontWeight:FontWeight.w700)),
              children:[ListTile(title:Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((task['employee_id']?.toString() ?? '').isNotEmpty)
                    Align(alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: () => widget.onEmployeeTap(
                          task['employee_id'].toString()),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(widget.employeeName(
                            task['employee_id']?.toString()),
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline)),
                        ),
                      ),
                    )
                  else
                    const Text('Unassigned'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: task['status'] == 'done'
                          ? const Color(0xFFE2F5E9)
                          : task['status'] == 'in_progress'
                            ? const Color(0xFFE0F1F4)
                            : const Color(0xFFEDF1F5),
                        borderRadius: BorderRadius.circular(12)),
                      child: Text(_statusName(task['status']),
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: task['status'] == 'done'
                            ? const Color(0xFF167A54)
                            : task['status'] == 'in_progress'
                              ? const Color(0xFF126C73)
                              : const Color(0xFF566979))),
                    ),
                    const SizedBox(width: 7),
                    Flexible(child: Text(
                      (task['category']?.toString() ?? 'General') +
                      ((task['due_at'] is int) ? ' · Due ' +
                        DateFormat('MMM d').format(
                          DateTime.fromMillisecondsSinceEpoch(
                            task['due_at'] as int)) : ''),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5,
                        color: Color(0xFF64748B)))),
                  ]),
                ]),
              trailing:PopupMenuButton<String>(
                tooltip:'Task progress',
                onOpened:()=>FocusManager.instance.primaryFocus?.unfocus(),
                onSelected:(v){
                  FocusManager.instance.primaryFocus?.unfocus();
                  widget.onGeneralStatus(task['id'] as int,v);
                },
                itemBuilder:(_)=>const [
                  PopupMenuItem(value:'planned',child:Text('Not Started')),
                  PopupMenuItem(value:'in_progress',child:Text('In Progress')),
                  PopupMenuItem(value:'done',child:Text('Done')),
                ],
              )),],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,10,12,8),
      child:Column(children:[
        Row(children:[
          const Expanded(child:Text('Tasks',
            style:TextStyle(fontWeight:FontWeight.w800,fontSize:20))),
          IconButton(onPressed:()=>_filters(),
            tooltip:'Advanced task filters',
            icon:const Icon(Icons.tune)),
        ]),
        if(widget.scopedJob!=null)
          Wrap(spacing:8,children:[
            OutlinedButton.icon(onPressed:widget.onAddService,icon:const Icon(Icons.add),label:const Text('Labor Task')),
            OutlinedButton.icon(onPressed:widget.onAddGeneral,icon:const Icon(Icons.add),label:const Text('General Task')),
          ]),
        Container(
          decoration:BoxDecoration(color:const Color(0xFFF1F5F7),
            borderRadius:BorderRadius.circular(22)),
          child:Row(children:[
            for(final option in [false,true])
              Expanded(child:InkWell(
                key:ValueKey(option?'general-tasks-tab':'service-tasks-tab'),
                onTap:(){
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState((){
                  _general=option;
                  _status='Active';_employee='';_sort='Newest First';
                  _servicePeriod='Any time';_search.clear();
                  });
                },
                child:Container(
                  padding:const EdgeInsets.symmetric(vertical:13),
                  decoration:BoxDecoration(
                    color:_general==option?const Color(0xFF007E78):null,
                    borderRadius:BorderRadius.circular(22)),
                  child:Text(option?'General Tasks':'Service Tasks',
                    textAlign:TextAlign.center,
                    style:TextStyle(fontWeight:FontWeight.w800,
                      color:_general==option?Colors.white:
                        const Color(0xFF344054))))),
              ),
          ]),
        ),
        const SizedBox(height:9),
        TextField(
          controller:_search,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration:InputDecoration(
            isDense:true,
            hintText:_general?'Search general tasks':'Search job tasks',
            prefixIcon:const Icon(Icons.search,size:21),
            suffixIcon:_search.text.isEmpty?null:IconButton(
              icon:const Icon(Icons.close,size:19),
              onPressed:_search.clear),
            border:OutlineInputBorder(
              borderRadius:BorderRadius.circular(22))),
        ),
        const SizedBox(height:5),
        // Two balanced rows on narrow Note 9 screens: no fourth filter
        // clipped off-screen or undiscoverable horizontal scroll.
        Padding(
          padding:const EdgeInsets.symmetric(horizontal:12),
          child:Column(children:[
            Row(children:[
              Expanded(child:_picker('Employee',
                _employee.isEmpty?'All':_employeeLabel(_employee),
                _employeeChoices,
                (v)=>setState(()=>_employee=_employeeIdForName(v)))),
              const SizedBox(width:5),
              Expanded(child:_picker('Status',_status,
                ['Active','Unpaid','Paid','All','Not Started','In Progress','Done'],
                (v)=>setState(()=>_status=v))),
            ]),
            const SizedBox(height:5),
            Row(children:[
              Expanded(child:_picker(_general?'Category':'Task Type',
                _general?_category:_kind,
                _general?['All Categories','General','Cleaning','Inventory',
                  'Office','Maintenance','Yard','Errands']:
                  ['All Types','Invoice Labor','Rechecks'],
                (v)=>setState((){
                  if(_general) {_category=v;} else {_kind=v;}
                }))),
              const SizedBox(width:5),
              Expanded(child:_general
                ? _picker('Sort',_sort,
                    ['Newest First','Oldest First','Due Date'],
                    (v)=>setState(()=>_sort=v))
                : _picker('Period',_servicePeriod,
                    ['Any time','This week','Last week','Last 7 days',
                     'Last 30 days','Last 90 days'],
                    (v)=>setState(()=>_servicePeriod=v))),
            ]),
          ]),
        ),
      ]),
    ),
    // Filters must never paint over the first Job count row at large
    // Android text scales or on a small phone.
    const SizedBox(height: 8),
    Expanded(child:ClipRect(child:_general?_generalView():_serviceView())),
  ]);
}
