import 'dart:async';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import '../../local/briskers_local_database.dart';
import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../services/offline_job_admin_service.dart';
import 'owner_payroll_screen.dart';

/// The same task identity is used by the invoice, Job and employee screens.
class JobTasksAccess extends StatefulWidget {
  const JobTasksAccess({super.key,required this.business,required this.job,this.invoice,this.line,this.database});
  final String business,job;
  final String? invoice,line;
  final BriskersLocalDatabase? database;
  @override State<JobTasksAccess> createState()=>_JobTasksAccessState();
}
class _JobTasksAccessState extends State<JobTasksAccess> {
  BriskersLocalDatabase get db=>widget.database??localDatabase;
  List<Map<String,dynamic>> staff=[];
  String? main;
  String? warning;
  bool busy=false;
  @override void initState(){super.initState();unawaited(load());}
  @override void didUpdateWidget(covariant JobTasksAccess old){super.didUpdateWidget(old);if(old.job!=widget.job)unawaited(load());}
  Future<void> load()async{
    try{
      final roster=await OfflineJobAdminService(database:db).cachedEmployees(widget.business).timeout(const Duration(seconds:3));
      final row=await db.customSelect('SELECT assigned_employee_id FROM local_jobs WHERE business_id=? AND id=?',
        variables:[Variable(widget.business),Variable(widget.job)]).getSingleOrNull();
      if(mounted)setState((){staff=roster;main=row?.data['assigned_employee_id'] as String?;warning=null;});
    }catch(_){if(mounted)setState(()=>warning='Saved mechanic list is not available yet. Retry.');}
  }
  Future<LocalPayrollRepository> unlock()async{
    final grant=await DeviceOwnerAuthorization.instance.authority.authorizeLocal(widget.business);
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
    }catch(e){if(mounted)setState(()=>warning='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> open()async{
    await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>OwnerPayrollScreen(
      businessId:widget.business,jobId:widget.job,invoiceId:widget.invoice,focusLineId:widget.line)));
    if(mounted)await load();
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
      if(warning!=null)Row(children:[Expanded(child:Text(warning!)),TextButton(onPressed:load,child:const Text('Retry'))]),
    ]);
  }
}
