import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/connection_mode.dart';
import '../../local/local_database_provider.dart';
import '../../services/briskers_api.dart';
import '../../services/local_document_detail_cache.dart';
import '../../services/local_job_tasks_lab_store.dart';

/// Owner's prototype. Only reads live invoice/employee data. Task edits are
/// LOCAL ONLY and cannot write invoices, payroll, or the server.
class JobTasksLabScreen extends StatefulWidget {
  const JobTasksLabScreen({super.key, required this.businessId,
    required this.jobId, required this.jobLabel,
    required this.documents, required this.employees});
  final String businessId, jobId, jobLabel;
  final List<Map<String,dynamic>> documents, employees;
  @override
  State<JobTasksLabScreen> createState() => _JobTasksLabScreenState();
}

class _JobTasksLabScreenState extends State<JobTasksLabScreen> {
  final _store = LocalJobTasksLabStore(localDatabase);
  final _api = BriskersApi();
  final _cache = const LocalDocumentDetailCache();
  List<Map<String,dynamic>> _tasks = const [];
  List<Map<String,dynamic>> _employees = const [];
  Map<String,String> _nicknames = const {};
  bool _busy = false, _initial = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _employees = widget.employees;
    unawaited(_load());
  }

  String _id(Map<String,dynamic> employee) =>
      (employee['id'] ?? employee['employee_id'] ?? '').toString();
  String _employeeName(Map<String,dynamic> employee) {
    final name = (employee['name'] ?? employee['full_name'] ??
        employee['display_name'] ?? employee['employee_name'] ?? '').toString();
    return LocalJobTasksLabStore.displayName(name, _nicknames[_id(employee)]);
  }
  String _assigned(Map<String,dynamic> task) {
    final id = task['employee_id']?.toString() ?? '';
    if (id.isEmpty) return 'Unassigned';
    for (final employee in _employees) {
      if (_id(employee) == id) return _employeeName(employee);
    }
    return 'Unknown mechanic';
  }
  String _description(Map<String,dynamic> task) =>
      (task['custom_description'] ?? task['source_description'] ?? '').toString();

  Future<void> _readLocal() async {
    final rows = await _store.list(widget.businessId,widget.jobId);
    final names = await _store.nicknames(widget.businessId);
    if (mounted) setState(() {
      _tasks=rows; _nicknames=names; _initial=false;
    });
  }

  Future<void> _load({bool refreshInvoices=true}) async {
    if (_busy) return;
    setState(() => _busy=true);
    try {
      await _readLocal();
      if (!refreshInvoices) return;
      final offline = BriskersConnectionModeController.instance.forceOffline;
      if (!offline && _employees.isEmpty) {
        try {
          final employees=await _api.assignableEmployees(widget.businessId);
          if(mounted) setState(()=>_employees=employees);
        } catch (_) {}
      }
      var refs=widget.documents.where((x)=>x['kind']=='invoice').toList();
      if(!offline) {
        try {
          final all=await _api.jobDocuments(widget.businessId,widget.jobId);
          refs=all.where((x)=>x['kind']=='invoice').toList();
        } catch (_) {}
      }
      final seen=<String>{};
      for(final ref in refs) {
        if(!mounted) return;
        final id=ref['id']?.toString() ?? '';
        if(id.isEmpty || !seen.add(id)) continue;
        try {
          final saved=await _cache.load(widget.businessId,id);
          if(saved!=null) await _seed(id,saved);
        } catch (_) {}
        if(!offline && !id.startsWith('local-')) {
          try {
            final latest=await _api.documentDetail(widget.businessId,id);
            await _seed(id,latest);
          } catch (_) {}
        }
        await _readLocal();
      }
      if(mounted) setState(()=>_error=null);
    } catch(error) {
      if(mounted) setState(()=>_error=error.toString());
    } finally {
      if(mounted) setState(() { _busy=false; _initial=false; });
    }
  }

  Future<void> _seed(String id, Map<String,dynamic> detail) async {
    if(detail['kind']!='invoice' ||
        detail['job_id']?.toString()!=widget.jobId) return;
    await _store.reconcileDocument(
      businessId:widget.businessId,jobId:widget.jobId,documentId:id,
      laborLines:LocalJobTasksLabStore.laborLines(detail));
  }

  Future<void> _edit(Map<String,dynamic> task) async {
    var mechanic=task['employee_id']?.toString() ?? '';
    var status=task['status']?.toString() ?? 'planned';
    final description=TextEditingController(text:_description(task));
    final hours=TextEditingController(
      text:task['payroll_hours']?.toString() ?? '');
    final saved=await showModalBottomSheet<bool>(
      context:context,isScrollControlled:true,useSafeArea:true,
      showDragHandle:true,
      builder:(context)=>StatefulBuilder(builder:(context,update)=>
        Padding(
          padding:EdgeInsets.fromLTRB(16,12,16,
            MediaQuery.viewInsetsOf(context).bottom+18),
          child:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.stretch,
            children:[
              const Text('Edit task',style:TextStyle(
                fontSize:21,fontWeight:FontWeight.w800)),
              const SizedBox(height:12),
              TextField(controller:description,minLines:2,maxLines:4,
                decoration:const InputDecoration(
                  labelText:'Work description',border:OutlineInputBorder())),
              const SizedBox(height:12),
              DropdownButtonFormField<String>(
                initialValue:mechanic,isExpanded:true,
                decoration:const InputDecoration(
                  labelText:'Mechanic',border:OutlineInputBorder()),
                items:[
                  const DropdownMenuItem(value:'',child:Text('Unassigned')),
                  ..._employees.where((x)=>_id(x).isNotEmpty).map((e)=>
                    DropdownMenuItem<String>(value:_id(e),
                      child:Text(_employeeName(e)))),
                ],
                onChanged:(v)=>update(()=>mechanic=v ?? '')),
              const SizedBox(height:12),
              TextField(controller:hours,
                keyboardType:const TextInputType.numberWithOptions(decimal:true),
                decoration:const InputDecoration(
                  labelText:'Mechanic hours',border:OutlineInputBorder())),
              const SizedBox(height:12),
              DropdownButtonFormField<String>(
                initialValue:status,
                decoration:const InputDecoration(
                  labelText:'Task status',border:OutlineInputBorder()),
                items:const [
                  DropdownMenuItem(value:'planned',child:Text('Planned')),
                  DropdownMenuItem(value:'in_progress',child:Text('In progress')),
                  DropdownMenuItem(value:'done',child:Text('Done'))],
                onChanged:(v)=>update(()=>status=v ?? 'planned')),
              const SizedBox(height:15),
              FilledButton.icon(
                icon:const Icon(Icons.save_outlined),
                label:const Text('Save locally'),
                onPressed:() async {
                  final raw=hours.text.trim();
                  final amount=raw.isEmpty ? null : double.tryParse(raw);
                  if(raw.isNotEmpty && amount==null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content:Text('Enter valid hours')));
                    return;
                  }
                  try {
                    await _store.editTask(
                      businessId:widget.businessId,jobId:widget.jobId,
                      documentId:task['document_id'].toString(),
                      lineId:task['line_id'].toString(),
                      employeeId:mechanic,editEmployee:true,
                      description:description.text,editDescription:true,
                      hours:amount,editHours:true,status:status);
                    if(context.mounted) Navigator.pop(context,true);
                  } catch(error) {
                    if(context.mounted) ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content:Text(error.toString())));
                  }
                }),
            ]))),
        )));
    description.dispose(); hours.dispose();
    if(saved==true && mounted) await _load(refreshInvoices:false);
  }

  Future<void> _editNicknames() async {
    if(_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Open online once to load employees.')));
      return;
    }
    final inputs=<String,TextEditingController>{
      for(final e in _employees) if(_id(e).isNotEmpty)
        _id(e):TextEditingController(
          text:_nicknames[_id(e)] ?? _employeeName(e))};
    await showDialog<void>(
      context:context,
      builder:(dialog)=>AlertDialog(
        title:const Text('Nicknames'),
        content:SizedBox(width:420,child:ListView(shrinkWrap:true,children:[
          for(final e in _employees) if(inputs.containsKey(_id(e)))
            Padding(padding:const EdgeInsets.only(bottom:8),
              child:TextField(controller:inputs[_id(e)],
                decoration:InputDecoration(
                  labelText:(e['name'] ?? e['full_name'] ??
                    e['display_name'] ?? _id(e)).toString())))
        ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog),
            child:const Text('Cancel')),
          FilledButton(onPressed:() async {
            try {
              for(final entry in inputs.entries) {
                if(entry.value.text.trim().isNotEmpty) {
                  await _store.saveNickname(widget.businessId,
                    entry.key,entry.value.text);
                }
              }
              if(dialog.mounted) Navigator.pop(dialog);
            } catch(error) {
              if(dialog.mounted) ScaffoldMessenger.of(dialog)
                .showSnackBar(SnackBar(content:Text(error.toString())));
            }
          },child:const Text('Save')),
        ]));
    for(final input in inputs.values) { input.dispose(); }
    if(mounted) await _load(refreshInvoices:false);
  }

  Widget _taskCard(Map<String,dynamic> task,{bool history=false}) {
    final done=task['status']=='done';
    final stamp=task['completed_at'];
    final when=stamp is int ? DateFormat('M/d h:mm a')
      .format(DateTime.fromMillisecondsSinceEpoch(stamp)) : '';
    final hrs=task['payroll_hours']?.toString() ?? '—';
    final state=task['status']=='in_progress' ? 'In progress' :
      done ? 'Done' : 'Planned';
    return Card(child:ListTile(
      onTap:()=>_edit(task),
      leading:Icon(done?Icons.check_circle:Icons.build_outlined,
        color:done?Colors.green:Colors.blue),
      title:Text(_description(task),
        style:const TextStyle(fontWeight:FontWeight.w700)),
      subtitle:Text([
        _assigned(task),hrs+' hrs',
        if(history) when else state,
        if(task['source_missing']==1) 'Source removed'
      ].join(' · ')),
      trailing:const Icon(Icons.edit_outlined)));
  }

  @override
  Widget build(BuildContext context) {
    final active=_tasks.where((x)=>x['source_missing']!=1).toList();
    final done=_tasks.where((x)=>x['status']=='done').toList();
    final ready=active.isNotEmpty && active.every((x)=>x['status']=='done');
    return DefaultTabController(length:2,child:Scaffold(
      appBar:AppBar(
        title:Text('Tasks · '+widget.jobLabel),
        actions:[
          IconButton(tooltip:'Nicknames',onPressed:_editNicknames,
            icon:const Icon(Icons.badge_outlined)),
          IconButton(tooltip:'Refresh invoice labor',onPressed:_busy?null:_load,
            icon:const Icon(Icons.refresh))],
        bottom:const TabBar(tabs:[
          Tab(text:'Tasks'),Tab(text:'Work Log')])),
      body:Column(children:[
        Container(width:double.infinity,color:const Color(0xFFFFF0CA),
          padding:const EdgeInsets.all(10),
          child:const Text('TEST ONLY · Assignments, nicknames and task '
            'status stay on this phone. Not synced to shop or payroll.',
            style:TextStyle(fontSize:12,fontWeight:FontWeight.w700))),
        if(_error!=null) Padding(padding:const EdgeInsets.all(8),
          child:Text(_error!,style:const TextStyle(color:Colors.red))),
        if(ready) const Padding(padding:EdgeInsets.all(8),
          child:Text('All tasks done · Job ready for review',
            style:TextStyle(color:Colors.green,fontWeight:FontWeight.w700))),
        if(_busy && !_initial) const LinearProgressIndicator(minHeight:2),
        Expanded(child:_initial
          ? const Center(child:CircularProgressIndicator())
          : TabBarView(children:[
              RefreshIndicator(onRefresh:_load,
                child:ListView(padding:const EdgeInsets.all(8),children:[
                  if(active.isEmpty) const ListTile(
                    title:Text('No linked invoice labor'),
                    subtitle:Text('Open a job with a saved labor invoice.')),
                  ...active.map((x)=>_taskCard(x))])),
              ListView(padding:const EdgeInsets.all(8),children:[
                if(done.isEmpty) const ListTile(
                  title:Text('No completed tasks yet')),
                ...done.map((x)=>_taskCard(x,history:true))]),
            ])),
      ])));
  }
}
