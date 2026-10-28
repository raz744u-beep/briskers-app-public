// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import 'fixture.dart';

/// Offline TEST Tasks workspace. Only customer/job-linked records appear
/// under Service Tasks; General Tasks have no job or invoice relationship.
class TasksWorkspaceLab extends StatefulWidget {
  const TasksWorkspaceLab({
    super.key,
    required this.serviceTasks,
    required this.generalTasks,
    required this.allocationsByLine,
    required this.employeeName,
    required this.serviceTaskCard,
    required this.onAddService,
    required this.onAddGeneral,
    required this.onGeneralStatus,
    required this.onOpenJob,
    this.initialGeneral = false,
  });

  final List<Map<String, dynamic>> serviceTasks;
  final List<Map<String, dynamic>> generalTasks;
  final Map<String, List<Map<String, dynamic>>> allocationsByLine;
  final String Function(String?) employeeName;
  final Widget Function(Map<String,dynamic>) serviceTaskCard;
  final VoidCallback onAddService;
  final VoidCallback onAddGeneral;
  final Future<void> Function(int taskId, String status) onGeneralStatus;
  final VoidCallback onOpenJob;
  final bool initialGeneral;

  @override
  State<TasksWorkspaceLab> createState() => _TasksWorkspaceLabState();
}

class _TasksWorkspaceLabState extends State<TasksWorkspaceLab> {
  late bool _general;
  final _search = TextEditingController();
  String _employee = '';
  String _status = 'Active';
  String _kind = 'All Types';
  String _category = 'All Categories';
  String _job = 'All Jobs';
  String _date = 'Any';
  String _sort = 'Newest First';
  final Set<String> _collapsedJobs = <String>{};

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

  List<Map<String,dynamic>> get _service {
    final q = _search.text.toLowerCase().trim();
    final rows = widget.serviceTasks.where((task) {
      final desc = (task['custom_description'] ??
        task['source_description'] ?? '').toString().toLowerCase();
      final isInvoice = task['document_id'] == BriskersLabFixture.invoiceId;
      if (_kind == 'Invoice Labor' && !isInvoice) return false;
      if (_kind == 'Rechecks' && isInvoice) return false;
      if (_job != 'All Jobs' &&
          task['job_id']?.toString() != _job) return false;
      return task['source_missing'] != 1 &&
        _matchesStatus(task) && _matchesEmployee(task,general:false) &&
        (q.isEmpty || desc.contains(q) ||
          'j-24'.contains(q) ||
          widget.employeeName(task['employee_id']?.toString())
            .toLowerCase().contains(q));
    }).toList();
    if (_sort == 'Oldest First') {
      rows.sort((a,b) => (a['line_id']?.toString() ?? '')
        .compareTo(b['line_id']?.toString() ?? ''));
    }
    return rows;
  }

  List<Map<String,dynamic>> get _internal {
    final q = _search.text.toLowerCase().trim();
    final rows = widget.generalTasks.where((task) {
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
      onSelected: onChange,
      itemBuilder: (_) => [
        for (final item in items)
          PopupMenuItem(value:item,child: Text(item)),
      ],
      child:Container(
        padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
        decoration:BoxDecoration(
          color: const Color(0xFFF3F7F8),
          border: Border.all(color:const Color(0xFFCBD7DC)),
          borderRadius:BorderRadius.circular(20)),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          Column(crossAxisAlignment:CrossAxisAlignment.start,
            mainAxisSize:MainAxisSize.min,children:[
            Text(title,style:const TextStyle(fontSize:10,
              color:Color(0xFF64748B))),
            Text(chosen,style:const TextStyle(fontSize:11,
              fontWeight:FontWeight.w700)),
          ]),
          const SizedBox(width:5),
          const Icon(Icons.keyboard_arrow_down,size:15),
        ]),
      ),
    );
  }

  List<String> get _employeeChoices =>
    ['All Employees',
     for (final e in BriskersLabFixture.employees)
       widget.employeeName(e['id'])];

  String _employeeIdForName(String name) {
    if (name == 'All Employees') return '';
    for (final e in BriskersLabFixture.employees) {
      if (widget.employeeName(e['id']) == name) return e['id']!;
    }
    return '';
  }

  Future<void> _filters() async {
    var employee = _employee;
    var status = _status, type = _kind, category = _category;
    var job = _job, date = _date, sort = _sort;
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
                  date='Any';sort='Newest First';
                }),child:const Text('Reset')),
              ]),
              dropdown('Employee',employee.isEmpty ? 'All Employees' :
                widget.employeeName(employee),_employeeChoices,
                (v)=>employee=_employeeIdForName(v)),
              if(!_general) ...[
                dropdown('Job',job,['All Jobs',
                  for(final id in widget.serviceTasks
                    .map((t)=>t['job_id']?.toString()??'')
                    .where((e)=>e.isNotEmpty).toSet()) id],
                  (v)=>job=v),
                dropdown('Task Type',type,
                  ['All Types','Invoice Labor','Rechecks'],(v)=>type=v),
              ] else ...[
                dropdown('Category',category,
                  ['All Categories','General','Cleaning','Inventory','Office',
                   'Maintenance','Yard','Errands'],(v)=>category=v),
                dropdown('Due Date',date,
                  ['Any','Today','This Week','Overdue'],(v)=>date=v),
              ],
              dropdown('Status',status,
                ['Active','All','Not Started','In Progress','Done'],
                (v)=>status=v),
              dropdown('Sort By',sort,
                ['Newest First','Oldest First','Due Date']
                  .where((s)=>_general||s!='Due Date').toList(),
                (v)=>sort=v),
              const SizedBox(height:8),
              FilledButton(
                onPressed:(){
                  setState((){
                    _employee=employee;_status=status;_kind=type;
                    _category=category;_job=job;_date=date;_sort=sort;
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
    final entries=byJob.entries.toList();
    return ListView(
      key:const Key('service-tasks-list'),
      padding:const EdgeInsets.fromLTRB(12,8,12,28),
      children:[
        Text('Jobs with Tasks · '+entries.length.toString(),
          style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),
        const SizedBox(height:9),
        if(entries.isEmpty)
          const Padding(padding:EdgeInsets.all(15),
            child:Text('No service tasks match these filters.')),
        for(final entry in entries) ...[
          Card(color:const Color(0xFFF0F5FA),margin:const EdgeInsets.only(bottom:9),
            child:Column(children:[
              ListTile(
                onTap:()=>setState((){
                  if(!_collapsedJobs.add(entry.key)) {
                    _collapsedJobs.remove(entry.key);
                  }
                }),
                title:Text(entry.key==BriskersLabFixture.jobId
                  ? 'J-24 · Invoice #6342' : entry.key,
                  style:const TextStyle(fontWeight:FontWeight.w800)),
                subtitle:Text(entry.key==BriskersLabFixture.jobId
                  ? 'Richard Goff · Hyundai Equus · '+entry.value.length.toString()+' tasks'
                  : entry.value.length.toString()+' tasks'),
                trailing:Icon(_collapsedJobs.contains(entry.key)
                  ? Icons.expand_more:Icons.expand_less),
              ),
              if(!_collapsedJobs.contains(entry.key)) ...[
                const Divider(height:1),
                for(final task in entry.value) widget.serviceTaskCard(task),
                TextButton.icon(onPressed:widget.onOpenJob,
                  icon:const Icon(Icons.open_in_new,size:17),
                  label:const Text('Open Job Details')),
                if(entry.key==BriskersLabFixture.jobId)
                  OutlinedButton.icon(
                    onPressed:widget.onAddService,
                    icon:const Icon(Icons.add_circle_outline),
                    label:const Text('Add Recheck to J-24')),
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
          TextButton.icon(onPressed:widget.onAddGeneral,
            icon:const Icon(Icons.add),label:const Text('New Task')),
        ]),
        if(tasks.isEmpty)
          const Padding(padding:EdgeInsets.all(15),
            child:Text('No general tasks match these filters.')),
        for(final task in tasks)
          Card(
            key:ValueKey('general-task-'+task['id'].toString()),
            margin:const EdgeInsets.only(bottom:7),
            child:ListTile(
              leading: Icon(task['status']=='done'
                ? Icons.check_circle: Icons.radio_button_unchecked,
                color:task['status']=='done' ?
                  const Color(0xFF167A54):BriskersColors.jobs),
              title:Text(task['description']?.toString()??'',
                style:const TextStyle(fontWeight:FontWeight.w700)),
              subtitle:Text(widget.employeeName(
                task['employee_id']?.toString())+
                ' · '+_statusName(task['status'])+
                ' · '+(task['category']?.toString()??'General')+
                ((task['due_at'] is int) ? ' · Due '+DateFormat('MMM d')
                  .format(DateTime.fromMillisecondsSinceEpoch(
                    task['due_at'] as int)) : '')),
              trailing:PopupMenuButton<String>(
                tooltip:'Task progress',
                onSelected:(v)=>widget.onGeneralStatus(task['id'] as int,v),
                itemBuilder:(_)=>const [
                  PopupMenuItem(value:'planned',child:Text('Not Started')),
                  PopupMenuItem(value:'in_progress',child:Text('In Progress')),
                  PopupMenuItem(value:'done',child:Text('Done')),
                ],
              ),
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
        Container(
          decoration:BoxDecoration(color:const Color(0xFFF1F5F7),
            borderRadius:BorderRadius.circular(22)),
          child:Row(children:[
            for(final option in [false,true])
              Expanded(child:InkWell(
                key:ValueKey(option?'general-tasks-tab':'service-tasks-tab'),
                onTap:()=>setState((){
                  _general=option;
                  _status='Active';_employee='';_search.clear();
                }),
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
        const SizedBox(height:9),
        SingleChildScrollView(scrollDirection:Axis.horizontal,
          child:Row(children:[
            _picker('Employee',
              _employee.isEmpty?'All':widget.employeeName(_employee),
              _employeeChoices,
              (v)=>setState(()=>_employee=_employeeIdForName(v))),
            const SizedBox(width:6),
            _picker('Status',_status,
              ['Active','All','Not Started','In Progress','Done'],
              (v)=>setState(()=>_status=v)),
            const SizedBox(width:6),
            _picker(_general?'Category':'Task Type',
              _general?_category:_kind,
              _general?['All Categories','General','Cleaning','Inventory',
                'Office','Maintenance','Yard','Errands']:
                ['All Types','Invoice Labor','Rechecks'],
              (v)=>setState((){
                if(_general) {_category=v;} else {_kind=v;}
              })),
            const SizedBox(width:6),
            _picker('Sort',_sort,
              ['Newest First','Oldest First',if(_general)'Due Date'],
              (v)=>setState(()=>_sort=v)),
          ]),
        ),
      ]),
    ),
    Expanded(child:_general?_generalView():_serviceView()),
  ]);
}
