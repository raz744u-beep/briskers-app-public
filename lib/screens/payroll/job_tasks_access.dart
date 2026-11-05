import 'dart:async';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import '../../local/briskers_local_database.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../services/offline_job_admin_service.dart';
import 'owner_payroll_screen.dart';
import 'payroll_ui_scope.dart';

/// The same task identity is used by the invoice, Job and employee screens.
class JobTasksAccess extends StatefulWidget {
  const JobTasksAccess({super.key,required this.business,required this.job,this.invoice,this.line,this.database,this.onChanged,this.onHours});
  final String business,job;
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
  @override void initState(){super.initState();if(widget.line==null)unawaited(load());}
  @override void didUpdateWidget(covariant JobTasksAccess old){super.didUpdateWidget(old);if(old.job!=widget.job)unawaited(load());}
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
        if(mounted)widget.onHours?.call(estimated!,actual!);
      }
      if(mounted)setState((){staff=roster;main=row?.data['assigned_employee_id'] as String?;
        if(main!=null && !staff.any((r)=>r['id']==main)){staff=[...staff,{'id':main,'name':row?.data['assigned_employee_name']??'Saved mechanic'}];}
        warning=null;});
    }catch(_){if(mounted)setState(()=>warning='Saved mechanic list is not available yet. Retry.');}
  }
  Future<LocalPayrollRepository> unlock()async{
    final grant=await (PayrollUiScope.of(context)?.unlock(widget.business) ?? DeviceOwnerAuthorization.instance.authority.authorizeLocal(widget.business));
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
    if(mounted && widget.line==null)await load();
  }
  @override Widget build(BuildContext context){
    if(widget.line!=null)return TextButton.icon(onPressed:open,icon:const Icon(Icons.assignment_ind_outlined,size:18),label:const Text('Assign mechanics / task'));
    final values={for(final p in staff) p['id']:p};
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Expanded(child:DropdownButtonFormField<String>(key:ValueKey(main),initialValue:values.containsKey(main)?main:null,
          decoration:const InputDecoration(labelText:'Main Mechanic'),isExpanded:true,
          items:[const DropdownMenuItem<String>(value:null,child:Text('Unassigned')),
            for(final entry in values.entries) if(entry.key is String)
              DropdownMenuItem(value:entry.key as String,child:Text((entry.value['nickname']??entry.value['name']??entry.key).toString()))],
          onChanged:busy?null:chooseMain)),
        const SizedBox(width:8),OutlinedButton.icon(onPressed:open,icon:const Icon(Icons.task_alt),label:const Text('Tasks'))]),
      if(estimated!=null)Text('Estimated labor: ${(estimated!/60).toStringAsFixed(2)} h · Actual: ${(actual!/60).toStringAsFixed(2)} h',style:const TextStyle(fontSize:12)),
      if(warning!=null)Row(children:[Expanded(child:Text(warning!)),TextButton(onPressed:load,child:const Text('Retry'))]),
    ]);
  }
}
