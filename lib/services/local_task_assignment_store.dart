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
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_job_lead '
      '(business_id TEXT NOT NULL,job_id TEXT NOT NULL,employee_id TEXT,employee_name TEXT,revision INTEGER NOT NULL DEFAULT 1,PRIMARY KEY(business_id,job_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_assignment_meta '
      '(business_id TEXT NOT NULL,task_id TEXT NOT NULL,employee_id TEXT NOT NULL,inherited INTEGER NOT NULL DEFAULT 0,'
      'active INTEGER NOT NULL DEFAULT 1,revision INTEGER NOT NULL DEFAULT 1,PRIMARY KEY(business_id,task_id,employee_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_task_policy '
      '(business_id TEXT NOT NULL,task_id TEXT NOT NULL,manual_override INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(business_id,task_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS regular_payroll_actual_time '
      '(business_id TEXT NOT NULL,credit_id TEXT NOT NULL,minutes INTEGER NOT NULL CHECK(minutes>=0),revision INTEGER NOT NULL DEFAULT 1,PRIMARY KEY(business_id,credit_id))');
  }
  Future<void> linkEmployee(String business,String job,String employee,String name) async {
    final exists=await _read('SELECT id FROM local_jobs WHERE business_id=? AND id=?',[business,job]);
    if(exists.length!=1) throw StateError('Saved Job is unavailable.');
    final assigned=await _read('SELECT assignment_id FROM local_job_assignments WHERE business_id=? AND job_id=? AND employee_id=? AND active=1',[business,job,employee]);
    if(assigned.isNotEmpty)return;
    await db.customStatement('INSERT OR IGNORE INTO local_job_assignments '
      '(assignment_id,business_id,job_id,employee_id,employee_name,active,source) VALUES(?,?,?,?,?,1,?)',
      [jsonEncode(['payroll',business,job,employee]),business,job,employee,name,'payroll_task']);
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
    // Explicit Owner assignment can confirm a previously unknown rate before
    // work starts. Earned work and every covered/paid credit keep their rate.
    if(!inherited && (e['rate'] as int)>0) {
      await db.customStatement('UPDATE local_mechanic_work_credits_v1 SET rate_cents=?,revision=revision+1 '
        'WHERE business_id=? AND allocation_id=? AND rate_cents=0 AND actual_minutes=0 AND completed=0 AND paid_operation_id IS NULL '
        "AND EXISTS(SELECT 1 FROM regular_payroll_portions p WHERE p.business_id=? AND p.id=? AND p.state='Open') "
        'AND NOT EXISTS(SELECT 1 FROM regular_payroll_work_coverage w WHERE w.business_id=? AND w.credit_id=?)',
        [e['rate'],business,id,business,id,business,id]);
    }
    // Splitting a billable invoice line must not hand each mechanic the
    // entire customer labor quantity. First active assignment inherits the
    // estimate; an additional mechanic starts at zero until the Owner
    // explicitly redistributes the allocated hours.
    final others=await _read(
      'SELECT p.id FROM regular_payroll_portions p '
      'LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id '
      'AND m.task_id=p.task_id AND m.employee_id=p.employee_id '
      'WHERE p.business_id=? AND p.task_id=? AND p.employee_id<>? '
      'AND COALESCE(m.active,1)=1',
      [business,task,employee],
    );
    final defaultMinutes=others.isEmpty?((t['planned'] as int)*60+50)~/100:0;
    await db.customStatement('INSERT OR IGNORE INTO regular_payroll_estimates VALUES(?,?,?,?)',
      [business,task,employee,defaultMinutes]);
    await db.customStatement('INSERT INTO regular_payroll_assignment_meta(business_id,task_id,employee_id,inherited,active) VALUES(?,?,?,?,1) '
      'ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET inherited=excluded.inherited,active=1,revision=revision+1 WHERE inherited<>excluded.inherited OR active<>1',[business,task,employee,inherited?1:0]);
    if(!inherited) { await db.customStatement('INSERT INTO regular_payroll_task_policy VALUES(?,?,1) '
      'ON CONFLICT(business_id,task_id) DO UPDATE SET manual_override=1',[business,task]); }
  }
  Future<void> retireInherited(String business,String task,{String? except}) async {
    await prepare();
    await db.customStatement("UPDATE regular_payroll_assignment_meta SET active=0,revision=revision+1 WHERE active=1 AND business_id=? AND task_id=? AND inherited=1 "
      "AND employee_id<>? AND EXISTS(SELECT 1 FROM regular_payroll_portions p JOIN local_mechanic_work_credits_v1 c "
      "ON c.business_id=p.business_id AND c.allocation_id=p.id WHERE p.business_id=regular_payroll_assignment_meta.business_id "
      "AND p.task_id=regular_payroll_assignment_meta.task_id AND p.employee_id=regular_payroll_assignment_meta.employee_id "
      "AND p.state='Open' AND c.actual_minutes=0 AND c.paid_operation_id IS NULL "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_work_coverage x WHERE x.business_id=c.business_id AND x.credit_id=c.allocation_id))",
      [business,task,except??'']);
  }
  Future<void> inherit(String business,String job,{String? ownerAssignedDocument}) async {
    await prepare();
    final ready=await _read("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('regular_payroll_portions','regular_payroll_employees','regular_payroll_estimates','regular_payroll_work_coverage','local_mechanic_work_credits_v1')",[]);
    if(ready.length!=5)return;
    final lead=await _read('SELECT CASE WHEN l.job_id IS NULL THEN j.assigned_employee_id ELSE l.employee_id END AS assigned_employee_id, '
      'COALESCE(e.name,CASE WHEN l.job_id IS NULL THEN j.assigned_employee_name ELSE l.employee_name END) AS employee_name '
      'FROM local_jobs j '
      'LEFT JOIN regular_payroll_job_lead l ON l.business_id=j.business_id AND l.job_id=j.id '
      'LEFT JOIN regular_payroll_employees e ON e.business_id=j.business_id AND e.id=CASE WHEN l.job_id IS NULL THEN j.assigned_employee_id ELSE l.employee_id END '
      'WHERE j.business_id=? AND j.id=?',[business,job]);
    if (lead.isEmpty || lead.single['assigned_employee_id'] is! String ||
        (lead.single['assigned_employee_id'] as String).isEmpty) {
      return;
    }
    final employee=lead.single['assigned_employee_id'] as String;
    // The mechanic's pay basis may legitimately be unconfigured. Do not
    // suppress the labor allocation: initialize the employee with zero rate,
    // retain any saved compensation and block actual payment until reviewed.
    await db.customStatement(
      'INSERT OR IGNORE INTO regular_payroll_employees VALUES(?,?,?,?,0)',
      [business,employee,
       (lead.single['employee_name']?.toString().trim().isNotEmpty ?? false)
         ? lead.single['employee_name'] : employee,0],
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
      [business,employee],
    );
    final tasks=await _read("SELECT t.id FROM regular_payroll_tasks t JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id "
      "WHERE t.business_id=? AND t.job_id=? AND s.active=1 AND s.source_kind='invoice' "
      "AND EXISTS(SELECT 1 FROM local_documents d WHERE d.business_id=s.business_id AND d.id=s.invoice_id AND date(d.document_date)=d.document_date AND (d.document_date >= '2026-11-07' OR d.id=?)) "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_task_policy o WHERE o.business_id=t.business_id AND o.task_id=t.id AND o.manual_override=1) "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_portions p LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id "
      "WHERE p.business_id=t.business_id AND p.task_id=t.id AND m.inherited IS NULL)",[business,job,ownerAssignedDocument ?? '']);
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
