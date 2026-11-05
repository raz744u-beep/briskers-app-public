import 'package:flutter/material.dart';
import '../local/local_database_provider.dart';
import '../services/completed_task_history.dart';

class CompletedWorkSection extends StatefulWidget {
  const CompletedWorkSection({super.key,required this.business,required this.job,this.revision=0});
  final String business,job;
  final int revision;
  @override State<CompletedWorkSection> createState()=>_CompletedWorkSectionState();
}
class _CompletedWorkSectionState extends State<CompletedWorkSection>{
  late Future<List<Map<String,dynamic>>> rows;
  @override void initState(){super.initState();rows=CompletedTaskHistory(localDatabase).read(widget.business,job:widget.job);}
  @override void didUpdateWidget(covariant CompletedWorkSection old){super.didUpdateWidget(old);if(old.job!=widget.job || old.revision!=widget.revision)rows=CompletedTaskHistory(localDatabase).read(widget.business,job:widget.job);}
  @override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,dynamic>>>(future:rows,builder:(context,snapshot)=>ExpansionTile(
    title:const Text('Work Completed'),subtitle:Text(snapshot.hasError?'Saved task history is unavailable':snapshot.hasData?'${snapshot.data!.length} completed mechanic allocations':'Loading saved work…'),
    children:[for(final row in snapshot.data??[])ListTile(dense:true,title:Text(row['description'].toString()),
      subtitle:Text('${row['mechanic']} · ${((row['actual_minutes'] as int)/60).toStringAsFixed(2)} actual hours · ${row['completed_date']??''}')),
      if(snapshot.hasData&&snapshot.data!.isEmpty)const ListTile(title:Text('No completed task allocations recorded. Existing work notes remain unchanged.'))]));
}
