import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_mechanic_work_credit_repository.dart';

/// Assignment provenance supplements the existing task/credit ledger. Never
/// changes customer billing, removes earned work, or guesses employee identity.
class LocalTaskAssignmentStore {
  LocalTaskAssignmentStore(this.db);
  final BriskersLocalDatabase db;
  Future<List<Map<String,dynamic>>> _read(String sql,List<Object> args) async =>
    (await db.customSelect(sql,variables:args.map((a)=>a is int?Variable<int>(a):Variable<String>(a as String)).toList()).get()).map((r)=>r.data).toList();
  Future<void> prepare() async {
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_assignment_meta '
      '(business_id TEXT NOT NULL,task_id TEXT NOT NULL,employee_id TEXT NOT NULL,inherited INTEGER NOT NULL DEFAULT 0,'
      'active INTEGER NOT NULL DEFAULT 1,PRIMARY KEY(business_id,task_id,employee_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_task_policy '
      '(business_id TEXT NOT NULL,task_id TEXT NOT NULL,manual_override INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(business_id,task_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_actual_time '
      '(business_id TEXT NOT NULL,credit_id TEXT NOT NULL,minutes INTEGER NOT NULL CHECK(minutes>=0),PRIMARY KEY(business_id,credit_id))');
  }
  Future<void> linkEmployee(String business,String job,String employee,String name) async {
    final exists=await _read('SELECT id FROM local_jobs WHERE business_id=? AND id=?',[business,job]);
    if(exists.length!=1) throw StateError('Saved Job is unavailable.');
    await db.customStatement('INSERT OR IGNORE INTO local_job_assignments '
      '(assignment_id,business_id,job_id,employee_id,employee_name,active,source) VALUES(?,?,?,?,?,1,?)',
      [jsonEncode(['payroll',job,employee]),business,job,employee,name,'payroll_task']);
  }
  Future<void> allocate(String business,String task,String employee,{required bool inherited}) async {
    await prepare();
    final tasks=await _read('SELECT * FROM regular_payroll_tasks WHERE business_id=? AND id=?',[business,task]);
    final staff=await _read('SELECT * FROM regular_payroll_employees WHERE business_id=? AND id=?',[business,employee]);
    if(tasks.length!=1||staff.length!=1) throw StateError('Save employee compensation before assigning labor.');
    final t=tasks.single,e=staff.single;
    await linkEmployee(business,t['job_id'] as String,employee,e['name'] as String);
    final id=jsonEncode([task,employee]);
    await db.customStatement("INSERT OR IGNORE INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES(?,?,?,?,'Open')",[business,id,task,employee]);
    final existing=await _read('SELECT allocation_id FROM local_mechanic_work_credits_v1 WHERE business_id=? AND allocation_id=?',[business,id]);
    if(existing.isEmpty) {
      await LocalMechanicWorkCreditRepository(database:db).createAssignment(businessId:business,allocationId:id,
        jobId:t['job_id'] as String,laborLineId:t['labor_id'] as String,taskId:task,employeeId:employee,
        actualMinutes:0,rateCents:e['rate'] as int);
    }
    await db.customStatement('INSERT OR IGNORE INTO regular_payroll_estimates VALUES(?,?,?,?)',[business,task,employee,((t['planned'] as int)*60+50)~/100]);
    await db.customStatement('INSERT INTO regular_payroll_assignment_meta VALUES(?,?,?,?,1) '
      'ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET inherited=excluded.inherited,active=1',[business,task,employee,inherited?1:0]);
    if(!inherited) await db.customStatement('INSERT INTO regular_payroll_task_policy VALUES(?,?,1) '
      'ON CONFLICT(business_id,task_id) DO UPDATE SET manual_override=1',[business,task]);
  }
  Future<void> retireInherited(String business,String task,{String? except}) async {
    await prepare();
    await db.customStatement("UPDATE regular_payroll_assignment_meta SET active=0 WHERE business_id=? AND task_id=? AND inherited=1 "
      "AND employee_id<>? AND EXISTS(SELECT 1 FROM regular_payroll_portions p JOIN local_mechanic_work_credits_v1 c "
      "ON c.business_id=p.business_id AND c.allocation_id=p.id WHERE p.business_id=regular_payroll_assignment_meta.business_id "
      "AND p.task_id=regular_payroll_assignment_meta.task_id AND p.employee_id=regular_payroll_assignment_meta.employee_id "
      "AND p.state='Open' AND c.actual_minutes=0 AND c.paid_operation_id IS NULL "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_work_coverage x WHERE x.business_id=c.business_id AND x.credit_id=c.allocation_id))",
      [business,task,except??'']);
  }
  Future<void> inherit(String business,String job) async {
    await prepare();
    final ready=await _read("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('regular_payroll_portions','regular_payroll_employees','regular_payroll_estimates','regular_payroll_work_coverage','local_mechanic_work_credits_v1')",[]);
    if(ready.length!=5)return;
    final lead=await _read('SELECT j.assigned_employee_id,e.name FROM local_jobs j JOIN regular_payroll_employees e '
      'ON e.business_id=j.business_id AND e.id=j.assigned_employee_id WHERE j.business_id=? AND j.id=?',[business,job]);
    if(lead.isEmpty)return;
    final employee=lead.single['assigned_employee_id'] as String;
    final tasks=await _read("SELECT t.id FROM regular_payroll_tasks t JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id "
      "WHERE t.business_id=? AND t.job_id=? AND s.active=1 AND s.source_kind='invoice' "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_task_policy o WHERE o.business_id=t.business_id AND o.task_id=t.id AND o.manual_override=1) "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_portions p LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id "
      "WHERE p.business_id=t.business_id AND p.task_id=t.id AND m.inherited IS NULL)",[business,job]);
    for(final t in tasks) {
      final task=t['id'] as String;
      await retireInherited(business,task,except:employee);
      // Started/earned inherited allocations stay historical and are not duplicated.
      final retained=await _read("SELECT p.id FROM regular_payroll_portions p LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id "
        "WHERE p.business_id=? AND p.task_id=? AND COALESCE(m.active,1)=1",[business,task]);
      if(retained.isEmpty)await allocate(business,task,employee,inherited:true);
    }
  }
}
