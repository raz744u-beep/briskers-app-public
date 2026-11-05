import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'employee_nickname_store.dart';

/// Read-only completion projection. Internal chores never enter service history;
/// legacy manual notes remain in their original visit records.
class CompletedTaskHistory {
  CompletedTaskHistory(this.db);
  final BriskersLocalDatabase db;
  Future<List<Map<String,dynamic>>> read(String business,{String? job,String? customer})async{
    final schema=await db.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('regular_payroll_tasks','regular_payroll_portions','local_mechanic_work_credits_v1','regular_payroll_employees','regular_payroll_task_sources')").get();
    if(schema.length!=5)return [];
    final extra=await db.customSelect("SELECT name FROM sqlite_master WHERE name='regular_payroll_actual_time'").get();
    final meta=await db.customSelect("SELECT name FROM sqlite_master WHERE name='regular_payroll_assignment_meta'").get();
    final rows=await db.customSelect('SELECT t.id AS task_id,t.job_id,t.description,p.employee_id,p.completed_date,'
      'e.name AS mechanic,j.job_number,j.customer_id,j.vehicle_label,s.invoice_id,s.source_kind,'
      '${extra.isEmpty?'c.actual_minutes':'COALESCE(a.minutes,c.actual_minutes)'} AS actual_minutes '
      'FROM regular_payroll_tasks t JOIN regular_payroll_portions p ON p.business_id=t.business_id AND p.task_id=t.id '
      'JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id '
      'JOIN regular_payroll_employees e ON e.business_id=p.business_id AND e.id=p.employee_id '
      'JOIN local_jobs j ON j.business_id=t.business_id AND j.id=t.job_id '
      'LEFT JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id '
      '${extra.isEmpty?'':'LEFT JOIN regular_payroll_actual_time a ON a.business_id=c.business_id AND a.credit_id=c.allocation_id '}'
      "WHERE t.business_id=? AND p.state='Done' AND c.completed=1 "
      "${meta.isEmpty?'':"AND NOT EXISTS (SELECT 1 FROM regular_payroll_assignment_meta m WHERE m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id AND m.active=0) "}"
      '${job==null?'':'AND t.job_id=? '} ${customer==null?'':'AND j.customer_id=? '}'
      'ORDER BY p.completed_date DESC,t.id,p.employee_id',
      variables:[business,?job,?customer].map(Variable<String>.new).toList()).get();
    final nicknames=await EmployeeNicknameStore(database:db).all(business);
    return rows.map((r)=><String,dynamic>{...r.data,'mechanic':nicknames[r.data['employee_id']]??r.data['mechanic']}).toList();
  }
}
