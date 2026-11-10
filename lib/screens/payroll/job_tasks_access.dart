import 'dart:async';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../../local/briskers_local_database.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../services/employee_nickname_store.dart';
import '../../services/offline_job_admin_service.dart';
import 'owner_payroll_screen.dart';
import 'payroll_ui_scope.dart';

/// The same task identity is used by the invoice, Job and employee screens.
class JobTasksAccess extends StatefulWidget {
  const JobTasksAccess({super.key,required this.business,required this.job,this.invoice,this.line,this.database,this.onChanged,this.onHours,this.revision=0});
  final String business,job;
  final int revision;
  final String? invoice,line;
  final BriskersLocalDatabase? database;
  final VoidCallback? onChanged;
  final void Function(int estimated,int actual)? onHours;
  @override State<JobTasksAccess> createState()=>_JobTasksAccessState();
}
class _JobTasksAccessState extends State<JobTasksAccess> {
  BriskersLocalDatabase get db=>widget.database??localDatabase;
  List<Map<String,dynamic>> staff=[];
  String? main;
  String? warning;
  bool busy=false;
  int? estimated,actual;
  String? lineAssignment;
  List<Map<String,dynamic>> linePeople=[];
  @override void initState(){super.initState();unawaited(widget.line==null?load():loadLine());}
  @override void didUpdateWidget(covariant JobTasksAccess old){super.didUpdateWidget(old);if(old.job!=widget.job || old.line!=widget.line || old.invoice!=widget.invoice || old.revision!=widget.revision){unawaited(widget.line==null?load():loadLine());}}
  /// Snapshot the *same* durable invoice-labor allocation IDs used by Payroll.
  /// Customer billed quantity is never read or changed by this presentation.
  Future<void> loadLine() async {
    final invoice=widget.invoice,line=widget.line;
    if(invoice==null || line==null)return;
    try{
      final tables=await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
        "('regular_payroll_task_sources','regular_payroll_portions',"
        "'regular_payroll_employees','regular_payroll_assignment_meta',"
        "'regular_payroll_estimates','local_employee_nicknames',"
        "'local_mechanic_work_credits_v1','regular_payroll_work_coverage')").get();
      final names=tables.map((r)=>r.read<String>('name')).toSet();
      final hasCore=names.containsAll({
        'regular_payroll_task_sources','regular_payroll_portions',
        'regular_payroll_employees'
      });
      final people=<Map<String,dynamic>>[];
      final cached=await OfflineJobAdminService(database:db)
          .cachedEmployees(widget.business);
      if(hasCore){
        final nick=names.contains('local_employee_nicknames');
        final meta=names.contains('regular_payroll_assignment_meta');
        final estimates=names.contains('regular_payroll_estimates');
        final credit=names.contains('local_mechanic_work_credits_v1');
        final coverage=names.contains('regular_payroll_work_coverage');
        final rows=await db.customSelect(
          'SELECT p.task_id,p.employee_id,p.state,e.name AS legal_name,'
          '${nick?"COALESCE(NULLIF(n.nickname,''),e.name)":"e.name"} AS nickname,'
          '${estimates?"COALESCE(t.minutes,0)":"0"} AS estimated_minutes,'
          '${credit?"c.paid_operation_id":"NULL"} AS paid_operation,'
          '${coverage?"(SELECT COALESCE(SUM(w.minutes),0) FROM regular_payroll_work_coverage w WHERE w.business_id=p.business_id AND w.credit_id=p.id)":"0"} AS paid_minutes '
          'FROM regular_payroll_task_sources s '
          'JOIN regular_payroll_portions p ON p.business_id=s.business_id AND p.task_id=s.task_id '
          'JOIN regular_payroll_employees e ON e.business_id=p.business_id AND e.id=p.employee_id '
          '${nick?"LEFT JOIN local_employee_nicknames n ON n.business_id=p.business_id AND n.employee_id=p.employee_id ": ""}'
          '${meta?"LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id ": ""}'
          '${estimates?"LEFT JOIN regular_payroll_estimates t ON t.business_id=p.business_id AND t.task_id=p.task_id AND t.employee_id=p.employee_id ": ""}'
          '${credit?"LEFT JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id ": ""}'
          'WHERE s.business_id=? AND s.invoice_id=? AND s.line_id=? AND s.active=1 '
          '${meta?"AND (COALESCE(m.active,1)=1 OR p.state='Done') ": ""}'
          'ORDER BY e.name',
          variables:[widget.business,invoice,line].map(Variable<String>.new).toList()).get();
        final known={for(final p in cached)p['id']:p}.values.toList();
        for(final row in rows){
          final data=row.data;
          final id=data['employee_id']?.toString();
          if(id==null)continue;
          final saved=cached.where((p)=>p['id']==id).firstOrNull;
          final identity=<String,dynamic>{
            'id':id,'name':saved?['name']??data['legal_name'],
            'nickname':saved?['nickname']??data['nickname'],
          };
          final others={for(final person in known)person['id']:person,id:identity}.values;
          people.add({
            ...identity,
            'label':EmployeeNicknameStore.displayLabel(identity,others),
            'task_id':data['task_id'],
            'estimated_minutes':data['estimated_minutes'],
            'paid':data['paid_operation']!=null ||
              (data['paid_minutes'] as int? ?? 0)>0,
          });
        }
      }
      if(mounted && widget.invoice==invoice && widget.line==line){
        setState((){
          linePeople=people;
          staff=cached;
          lineAssignment=people.isEmpty?'Unassigned':null;
          warning=null;
        });
      }
    }catch(_){
      if(mounted){
        setState((){
          linePeople=[];
          lineAssignment='Assignments unavailable · Tap to retry';
          warning='Saved mechanic assignments could not be read. Reopen this invoice to retry.';
        });
      }
    }
  }

  Future<void> editMechanicHours(Map<String,dynamic> allocation)async{
    if(allocation['paid']==true)return;
    final input=TextEditingController(
      text:((allocation['estimated_minutes'] as int? ?? 0)/60)
        .toStringAsFixed(2));
    final hours=await showDialog<double>(context:context,builder:(dialogContext)=>
      AlertDialog(
        title:Text('Mechanic hours · ${allocation['label']}'),
        content:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Separate from customer-billed hours.',
            style:TextStyle(fontSize:12)),
          TextField(controller:input,autofocus:true,
            keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:const InputDecoration(labelText:'Estimated mechanic hours')),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),
            child:const Text('Cancel')),
          FilledButton(onPressed:(){
            final value=double.tryParse(input.text.trim());
            if(value==null || !value.isFinite || value<0 || value>10000)return;
            Navigator.pop(dialogContext,value);
          },child:const Text('Save')),
        ],
      ));
    input.dispose();
    if(hours==null || !mounted)return;
    setState(()=>busy=true);
    try{
      final repo=await unlock();
      final task=allocation['task_id']?.toString();
      final employee=allocation['id']?.toString();
      if(task==null || employee==null)return;
      // Revalidate paid coverage after the Owner-session check; partial payments
      // are just as immutable as fully settled allocations.
      await repo.prepare();
      final settled=await db.customSelect(
        'SELECT c.paid_operation_id,'
        '(SELECT COALESCE(SUM(w.minutes),0) '
        'FROM regular_payroll_work_coverage w '
        'WHERE w.business_id=p.business_id AND w.credit_id=p.id) AS paid_minutes '
        'FROM regular_payroll_portions p '
        'LEFT JOIN local_mechanic_work_credits_v1 c '
        'ON c.business_id=p.business_id AND c.allocation_id=p.id '
        'WHERE p.business_id=? AND p.task_id=? AND p.employee_id=?',
        variables:[widget.business,task,employee].map(Variable<String>.new).toList())
        .getSingleOrNull();
      if(settled==null || settled.data['paid_operation_id']!=null ||
          (settled.data['paid_minutes'] as int? ?? 0)>0){
        throw StateError('Paid mechanic labor is locked.');
      }
      await repo.setEstimatedMinutes(task,employee,(hours*60).round());
      await loadLine();
      if(mounted)widget.onChanged?.call();
    }catch(error){
      if(mounted)setState(()=>warning='$error');
    }finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> load()async{
    try{
      final roster=await OfflineJobAdminService(database:db).cachedEmployees(widget.business).timeout(const Duration(seconds:3));
      final row=await db.customSelect('SELECT assigned_employee_id,assigned_employee_name FROM local_jobs WHERE business_id=? AND id=?',
        variables:[Variable(widget.business),Variable(widget.job)]).getSingleOrNull();
      final tables=await db.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('regular_payroll_portions','regular_payroll_estimates','local_mechanic_work_credits_v1','regular_payroll_actual_time','regular_payroll_assignment_meta')").get();
      if(tables.length==5){
        final totals=await db.customSelect('SELECT COALESCE(SUM(e.minutes),0) AS estimated,COALESCE(SUM(COALESCE(a.minutes,c.actual_minutes)),0) AS actual '
          'FROM regular_payroll_portions p JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id '
          'LEFT JOIN regular_payroll_estimates e ON e.business_id=p.business_id AND e.task_id=p.task_id AND e.employee_id=p.employee_id '
          'LEFT JOIN regular_payroll_actual_time a ON a.business_id=p.business_id AND a.credit_id=p.id '
          'LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id '
          'WHERE p.business_id=? AND c.job_id=? AND (COALESCE(m.active,1)=1 OR c.actual_minutes>0)',
          variables:[Variable(widget.business),Variable(widget.job)]).getSingle();
        estimated=totals.read<int>('estimated');actual=totals.read<int>('actual');
        if(mounted){widget.onHours?.call(estimated!,actual!);}
      }
      if(mounted){setState((){staff=roster;main=row?.data['assigned_employee_id'] as String?;
        if(main!=null && !staff.any((r)=>r['id']==main)){staff=[...staff,{'id':main,'name':row?.data['assigned_employee_name']??'Saved mechanic'}];}
        warning=null;});}
    }catch(_){if(mounted)setState(()=>warning='Saved mechanic list is not available yet. Retry.');}
  }
  Future<LocalPayrollRepository> unlock()async{
    final scope=PayrollUiScope.of(context);
    // The already-signed-in Briskers Owner session is sufficient for
    // Main Mechanic selection and per-line time editing. Only isolated
    // debug fixtures may supply their synthetic Owner authority.
    final grant=await (kDebugMode && scope?.debugAllowOwnerView==true
      ? scope!.unlock(widget.business)
      : DeviceOwnerAuthorization.instance.authority.authorizeSession(widget.business));
    void check()=>grant.assertValid(widget.business,grant.actorId);
    return LocalPayrollRepository(db,business:widget.business,owner:true,assertOwnerGrant:check);
  }
  Future<void> chooseMain(String? id)async{
    setState(()=>busy=true);
    try{
      final repo=await unlock();
      final person=staff.where((r)=>r['id']==id).firstOrNull;
      if(id!=null && person!=null){
        final prior=(await repo.employees()).where((r)=>r['id']==id).firstOrNull;
        if(prior==null)await repo.saveEmployeeCompensation(employee:id,name:(person['name']??id).toString(),rate:0,weeklyBase:false);
      }
      await repo.setMainMechanic(widget.job,id,person?['name']?.toString());
      await load();
      if(mounted)widget.onChanged?.call();
    }catch(e){if(mounted)setState(()=>warning='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> open()async{
    await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>OwnerPayrollScreen(
      businessId:widget.business,jobId:widget.job,invoiceId:widget.invoice,focusLineId:widget.line,
      database:db,unlockOwner:PayrollUiScope.of(context)?.unlock,ownerConnection:PayrollUiScope.of(context)?.connection)));
    if(mounted){await (widget.line==null?load():loadLine());widget.onChanged?.call();}
  }
  @override Widget build(BuildContext context){
    if(widget.line!=null){
      return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        // Single-line TEST invoice header: the old Wrap broke before the
        // mechanic name even for one mechanic, leaving "Labor" above "Chris".
        // Keep the identity and hours on the same row; long split names use
        // ellipsis instead of moving below the Labor heading.
        Row(mainAxisSize:MainAxisSize.max,children:[
          if(linePeople.isNotEmpty) ...[
            Expanded(child: Tooltip(
              message:linePeople.map((p) =>
                '${p['label']} ${((p['estimated_minutes'] as int? ?? 0)/60).toStringAsFixed(1)}h'
              ).join(' · '),
              child:Text(linePeople.map((p) =>
                '${p['label']} ${((p['estimated_minutes'] as int? ?? 0)/60).toStringAsFixed(1)}h'
              ).join(' · '),
                maxLines:1,
                softWrap:false,
                overflow:TextOverflow.ellipsis,
                textAlign:TextAlign.end,
                style:const TextStyle(fontSize:15,color:Color(0xFF00897E),
                  fontWeight:FontWeight.w800)),
            )),
            IconButton(
              constraints:const BoxConstraints(minWidth:28,minHeight:28),
              padding:EdgeInsets.zero,
              icon:Icon(linePeople.every((p)=>p['paid']==true)
                  ? Icons.lock_outline : Icons.edit_outlined,
                size:18,color:linePeople.every((p)=>p['paid']==true)
                  ? const Color(0xFF64748B):const Color(0xFF00897E)),
              tooltip:linePeople.every((p)=>p['paid']==true)
                ? 'Paid mechanic labor locked'
                : 'Edit or split mechanic labor',
              onPressed:busy || linePeople.every((p)=>p['paid']==true)
                ? null : open,
            ),
          ] else ...[
            Expanded(child:Text(lineAssignment??'Loading assignments…',
              textAlign:TextAlign.end,maxLines:1,
              overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:12,color:Color(0xFF64748B)))),
            IconButton(
              tooltip:'Assign or split mechanic labor',
              icon:const Icon(Icons.edit_outlined,
                color:Color(0xFF00897E),size:20),
              constraints:const BoxConstraints(minWidth:30,minHeight:30),
              padding:EdgeInsets.zero,
              onPressed:busy?null:open,
            ),
          ],
        ]),
        if (linePeople.length > 1)
          Align(alignment:Alignment.centerRight,child:Text(
            'Assigned total: ${(linePeople.fold<int>(0,(sum,person)=>sum+
              (person['estimated_minutes'] as int? ?? 0))/60).toStringAsFixed(1)} h',
            style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700,
              color:Color(0xFF526171)))),
        if(warning!=null)Text(warning!,style:const TextStyle(fontSize:11)),
      ]);
    }
    final values={for(final p in staff) p['id']:p};
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
        Expanded(child:Container(
          height:50,
          padding:const EdgeInsets.symmetric(horizontal:11),
          decoration:BoxDecoration(
            color:const Color(0xFFF0FBF7),
            borderRadius:BorderRadius.circular(15),
            border:Border.all(color:const Color(0xFF087D63)),
          ),
          child:Column(
            mainAxisAlignment:MainAxisAlignment.center,
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              const Text('Main Mechanic',maxLines:1,
                style:TextStyle(fontSize:10,color:Color(0xFF526171),fontWeight:FontWeight.w700)),
              DropdownButtonHideUnderline(child:DropdownButton<String>(
              key:ValueKey('main-mechanic-$main'),
              value:values.containsKey(main)?main:null,
              isExpanded:true,isDense:true,
              style:const TextStyle(fontSize:14,color:Color(0xFF153E38),fontWeight:FontWeight.w800),
              icon:const Icon(Icons.arrow_drop_down,color:Color(0xFF076B56)),
              hint:const Text('Unassigned'),
              items:[
                const DropdownMenuItem<String>(value:null,
                  child:Text('Unassigned')),
                for(final entry in values.entries)
                  DropdownMenuItem<String>(
                    value:entry.key as String,
                    child:Text(EmployeeNicknameStore.displayLabel(entry.value,staff),
                      maxLines:1,overflow:TextOverflow.ellipsis)),
              ],
              onChanged:busy?null:chooseMain,
            )),
            ],
          ),
        )),
        const SizedBox(width:8),Expanded(child:SizedBox(height:50,child:OutlinedButton.icon(
          style:OutlinedButton.styleFrom(
            tapTargetSize:MaterialTapTargetSize.shrinkWrap,
            visualDensity:VisualDensity.standard,
            padding:const EdgeInsets.symmetric(horizontal:11),
            backgroundColor:const Color(0xFFF0FBF7),
            foregroundColor:const Color(0xFF076B56),
            side:const BorderSide(color:Color(0xFF087D63)),
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15))),
          onPressed:busy?null:open,icon:const Icon(Icons.checklist),
          label:const Text('Job Tasks',maxLines:1,overflow:TextOverflow.ellipsis,
            style:TextStyle(fontWeight:FontWeight.w800,fontSize:15)))))]),
      if(widget.invoice!=null && estimated!=null)Text('Estimated labor: ${(estimated!/60).toStringAsFixed(2)} h · Actual: ${(actual!/60).toStringAsFixed(2)} h',style:const TextStyle(fontSize:12)),
      if(warning!=null)Row(children:[Expanded(child:Text(warning!)),TextButton(onPressed:load,child:const Text('Retry'))]),
    ]);
  }
}
