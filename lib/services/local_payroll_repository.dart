import 'historical_general_tasks.dart';
import 'historical_task_recordkeeping.dart';
import 'dart:convert';
import 'payroll_owner_lease.dart';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_mechanic_work_credit_repository.dart';
import 'local_payroll_work_source.dart';
import 'local_task_assignment_store.dart';
import 'offline_job_admin_service.dart';
import 'payroll_lan_peer.dart';
import 'local_invoice_task_store.dart';
import 'invoice_labor_work_summary.dart';
import 'local_document_detail_cache.dart';
import 'verified_paid_labor.dart';
import 'secure_employee_details_cache.dart';
import 'local_owner_authorization.dart';

/// Business-scoped local payroll ledger. Payment recording never sends money
/// or connects to the general financial sync queue.
class LocalPayrollRepository {
  LocalPayrollRepository(
    this.db, {
    required this.business,
    required this.owner,
    this.assertOwnerGrant,
    this.deviceId,
    this.assertLanWriter,
    this.pairedEmployee,
    this.ownerProof,
  });
  final BriskersLocalDatabase db;
  final String business;
  final bool owner;
  final void Function()? assertOwnerGrant;
  final String? deviceId;
  final Future<void> Function()? assertLanWriter;
  final String? pairedEmployee;
  final PayrollOwnerProof? ownerProof;
  Future<void>? _prepared;
  void _authorize() {
    if (!owner || business.trim().isEmpty)
      { throw StateError('Owner payroll access required'); }
    assertOwnerGrant?.call();
  }

  Future<List<Map<String, dynamic>>> _read(
    String sql, [
    List<Object> args = const [],
  ]) async =>
      (await db
              .customSelect(
                sql,
                variables: args
                    .map(
                      (a) => a is int
                          ? Variable<int>(a)
                          : Variable<String>(a as String),
                    )
                    .toList(),
              )
              .get())
          .map((r) => r.data)
          .toList();
  Future<void> prepare() => _prepared ??= _prepare();
  Future<void> _prepare() async {
    await LocalTaskAssignmentStore(db).prepare();
    await LocalMechanicWorkCreditRepository(database: db).prepare();
    await LocalInvoiceTaskStore(db).prepare();
    for (final sql in [
      '''CREATE TABLE IF NOT EXISTS regular_payroll_carry_weeks_v1 (business_id TEXT NOT NULL,allocation_id TEXT NOT NULL,week TEXT NOT NULL,reason TEXT NOT NULL,PRIMARY KEY(business_id,allocation_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_drafts_v1 (business_id TEXT NOT NULL,employee_id TEXT NOT NULL,week TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(business_id,employee_id,week))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_progress_claims (business_id TEXT NOT NULL,employee_id TEXT NOT NULL,event_id TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(business_id,employee_id,event_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_payment_authority (business_id TEXT PRIMARY KEY, device_id TEXT NOT NULL)''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_weekly_defaults (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, base_cents INTEGER NOT NULL, hourly_cents INTEGER NOT NULL, adjustment_cents INTEGER NOT NULL, add_labor INTEGER NOT NULL, PRIMARY KEY(business_id,employee_id))''',
      'CREATE TABLE IF NOT EXISTS regular_payroll_shop_task_jobs (business_id TEXT NOT NULL, task_id INTEGER NOT NULL, job_id TEXT NOT NULL, PRIMARY KEY (business_id,task_id))',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_shop_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL, employee_id TEXT NOT NULL, description TEXT NOT NULL, category TEXT NOT NULL, due_at INTEGER, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','in_progress','done')))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_jobs (business_id TEXT NOT NULL, id TEXT NOT NULL, label TEXT NOT NULL, PRIMARY KEY(business_id,id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_tasks (business_id TEXT NOT NULL, id TEXT NOT NULL, job_id TEXT NOT NULL, labor_id TEXT NOT NULL, description TEXT NOT NULL, planned INTEGER NOT NULL CHECK(planned>=0), PRIMARY KEY(business_id,id), UNIQUE(business_id,job_id,labor_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_portions (business_id TEXT NOT NULL, id TEXT NOT NULL, task_id TEXT NOT NULL, employee_id TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('Open','In Progress','Done')), version INTEGER NOT NULL DEFAULT 0, completed_date TEXT, PRIMARY KEY(business_id,id), UNIQUE(business_id,task_id,employee_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_employees (business_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, rate INTEGER NOT NULL CHECK(rate>=0), base_enabled INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(business_id,id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_advances (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, balance INTEGER NOT NULL CHECK(balance>=0), PRIMARY KEY(business_id,employee_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_payments (business_id TEXT NOT NULL, operation_id TEXT NOT NULL, employee_id TEXT NOT NULL, week TEXT NOT NULL, payload TEXT NOT NULL, gross INTEGER NOT NULL, repayment INTEGER NOT NULL, net INTEGER NOT NULL, method TEXT NOT NULL, verified_date TEXT NOT NULL, PRIMARY KEY(business_id,operation_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_paid_work (business_id TEXT NOT NULL, credit_id TEXT NOT NULL, operation_id TEXT NOT NULL, snapshot TEXT NOT NULL, PRIMARY KEY(business_id,credit_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_paid_base (business_id TEXT NOT NULL, employee_id TEXT NOT NULL, week TEXT NOT NULL, operation_id TEXT NOT NULL, amount INTEGER NOT NULL, PRIMARY KEY(business_id,employee_id,week))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_audit (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL, operation_id TEXT NOT NULL, event TEXT NOT NULL, payload TEXT NOT NULL)''',
      // Explicit historical Owner confirmation, NEVER a payroll payment.
      '''CREATE TABLE IF NOT EXISTS regular_payroll_owner_prior_paid_v1 (
        business_id TEXT NOT NULL,allocation_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,confirmed_at TEXT NOT NULL,
        PRIMARY KEY(business_id,allocation_id))''',
      '''CREATE TABLE IF NOT EXISTS regular_payroll_sync_outbox (business_id TEXT NOT NULL, operation_id TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'held_local', attempts INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(business_id,operation_id))''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_owner_prior_paid_credit_lock
        BEFORE UPDATE OF actual_minutes,completed,employee_id,allocation_id
        ON local_mechanic_work_credits_v1
        WHEN EXISTS(SELECT 1 FROM regular_payroll_owner_prior_paid_v1 h
          WHERE h.business_id=OLD.business_id AND h.allocation_id=OLD.allocation_id)
        BEGIN SELECT RAISE(ABORT,'Owner-confirmed prior paid labor is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_owner_prior_paid_estimate_lock
        BEFORE UPDATE OF minutes ON regular_payroll_estimates
        WHEN NEW.minutes<>OLD.minutes AND EXISTS(
          SELECT 1 FROM regular_payroll_portions p
          JOIN regular_payroll_owner_prior_paid_v1 h
            ON h.business_id=p.business_id AND h.allocation_id=p.id
          WHERE p.business_id=OLD.business_id AND p.task_id=OLD.task_id
            AND p.employee_id=OLD.employee_id)
        BEGIN SELECT RAISE(ABORT,'Owner-confirmed prior paid hours are immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_owner_prior_paid_credit_no_delete
        BEFORE DELETE ON local_mechanic_work_credits_v1
        WHEN EXISTS(SELECT 1 FROM regular_payroll_owner_prior_paid_v1 h
          WHERE h.business_id=OLD.business_id AND h.allocation_id=OLD.allocation_id)
        BEGIN SELECT RAISE(ABORT,'Owner-confirmed prior paid labor is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_owner_prior_paid_portion_lock
        BEFORE UPDATE OF state,employee_id,task_id ON regular_payroll_portions
        WHEN (NEW.state<>OLD.state OR NEW.employee_id<>OLD.employee_id
          OR NEW.task_id<>OLD.task_id) AND EXISTS(
          SELECT 1 FROM regular_payroll_owner_prior_paid_v1 h
          WHERE h.business_id=OLD.business_id AND h.allocation_id=OLD.id)
        BEGIN SELECT RAISE(ABORT,'Owner-confirmed prior paid task is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_owner_prior_paid_portion_no_delete
        BEFORE DELETE ON regular_payroll_portions
        WHEN EXISTS(SELECT 1 FROM regular_payroll_owner_prior_paid_v1 h
          WHERE h.business_id=OLD.business_id AND h.allocation_id=OLD.id)
        BEGIN SELECT RAISE(ABORT,'Owner-confirmed prior paid task is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_credit_frozen_update BEFORE UPDATE ON local_mechanic_work_credits_v1 WHEN OLD.paid_operation_id IS NOT NULL AND EXISTS(SELECT 1 FROM regular_payroll_paid_work WHERE business_id=OLD.business_id AND credit_id=OLD.allocation_id) BEGIN SELECT RAISE(ABORT,'Paid credit is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_credit_frozen_delete BEFORE DELETE ON local_mechanic_work_credits_v1 WHEN EXISTS(SELECT 1 FROM regular_payroll_paid_work WHERE business_id=OLD.business_id AND credit_id=OLD.allocation_id) BEGIN SELECT RAISE(ABORT,'Paid credit is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_paid_work_frozen_update BEFORE UPDATE ON regular_payroll_paid_work BEGIN SELECT RAISE(ABORT,'Paid work is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_paid_work_frozen_delete BEFORE DELETE ON regular_payroll_paid_work BEGIN SELECT RAISE(ABORT,'Paid work is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_payments_frozen_update BEFORE UPDATE ON regular_payroll_payments BEGIN SELECT RAISE(ABORT,'Payment is immutable'); END''',
      '''CREATE TRIGGER IF NOT EXISTS regular_payroll_payments_frozen_delete BEFORE DELETE ON regular_payroll_payments BEGIN SELECT RAISE(ABORT,'Payment is immutable'); END''',
    ]) {
      await db.customStatement(sql);
    }
    final oldTransport = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='payroll_lan_delivery_v1'").get();
    if (oldTransport.isNotEmpty) {
      final receipts = await _read("SELECT body FROM payroll_lan_delivery_v1 WHERE business=? AND direction='in' AND acknowledged=1", [business]);
      for (final receipt in receipts) {
        final change = jsonDecode(receipt['body'] as String) as Map;
        if (change['kind'] != 'progress') continue;
        final payload = change['payload'] as Map;
        await db.customStatement('INSERT OR IGNORE INTO regular_payroll_progress_claims VALUES(?,?,?,?)',
          [business, payload['employee'], jsonEncode([payload['id'], payload['revision']]), _progressBody(payload)]);
      }
    }
    // Retain settled coverage from earlier app versions without rewriting it.
    await db.customStatement(
      'INSERT OR IGNORE INTO regular_payroll_work_coverage '
      '(business_id,credit_id,operation_id,minutes,amount,snapshot) '
      'SELECT w.business_id,w.credit_id,w.operation_id,c.actual_minutes,'
      '(c.actual_minutes*c.rate_cents+30)/60,w.snapshot '
      'FROM regular_payroll_paid_work w JOIN local_mechanic_work_credits_v1 c '
      'ON c.business_id=w.business_id AND c.allocation_id=w.credit_id '
      'WHERE c.actual_minutes>0',
    );
  }

  static String _progressBody(Map payload) => jsonEncode([
    payload['job'], payload['id'], payload['employee'], payload['state'],
    payload['minutes'], payload['date'], payload['revision'],
  ]);

  /// Explicit and bounded invoice-task recovery. Checkpoints are persisted
  /// in the local shop database, so a resumed batch does not restart at zero.
  /// This is a derived index only; no payroll payments are recorded.
  Future<bool> backfillInvoiceTasks({String? job,int maxInvoices=25,bool resume=false,
    Future<void> Function()? onBatch,
    void Function(int checked,int recovered,int unavailable)? onProgress}) async {
    _authorize();
    await prepare();
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS regular_payroll_recovery_cursor '
      '(business_id TEXT NOT NULL,job_id TEXT NOT NULL,cursor TEXT NOT NULL,'
      'complete INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(business_id,job_id))');
    final scope=job??'';
    final stored=await _read(
      'SELECT cursor,complete FROM regular_payroll_recovery_cursor '
      'WHERE business_id=? AND job_id=?',[business,scope]);
    if(resume && stored.isNotEmpty && stored.single['complete']==1)return false;
    var after=!resume || stored.isEmpty?'':stored.single['cursor'] as String;
    var checked=0,recovered=0,unavailable=0;
    while(checked<maxInvoices){
      _authorize();
      final limit=(maxInvoices-checked)<10?(maxInvoices-checked):10;
      final rows=await _read(
        "SELECT id FROM local_documents WHERE business_id=? AND kind='invoice' "
        "AND date(document_date)=document_date AND document_date>=? AND id>? AND COALESCE(status,'') NOT IN "
        "('void','voided','cancelled','canceled','deleted') "
        "${job==null?'':'AND job_id=? '}ORDER BY id LIMIT $limit",
        [business,LocalInvoiceTaskStore.payrollCutover,after,?job]);
      if(rows.isEmpty){
        if(resume){await db.customStatement(
          'INSERT INTO regular_payroll_recovery_cursor VALUES(?,?,?,1) '
          'ON CONFLICT(business_id,job_id) DO UPDATE SET complete=1',
          [business,scope,after]);}
        return false;
      }
      for(final row in rows){
        _authorize();
        final id=row['id'] as String;
        final before=(await _read(
          "SELECT COUNT(*) AS n FROM regular_payroll_task_sources "
          "WHERE business_id=? AND invoice_id=? AND active=1 AND source_kind='invoice'",
          [business,id])).single['n'] as int;
        final detail=await LocalDocumentDetailCache(database:db).load(business,id);
        final afterCount=(await _read(
          "SELECT COUNT(*) AS n FROM regular_payroll_task_sources "
          "WHERE business_id=? AND invoice_id=? AND active=1 AND source_kind='invoice'",
          [business,id])).single['n'] as int;
        final raw=detail?['lines']??detail?['items'];
        final lines=raw is List?
          raw.whereType<Map>().map(Map<String,dynamic>.from).toList():null;
        final usable=lines!=null && lines.length==raw.length &&
          lines.every((r)=>r['id'] is String && (r['id'] as String).isNotEmpty) &&
          lines.map((r)=>r['id']).toSet().length==lines.length;
        checked++;
        if(!usable || lines.where(isInvoiceLaborLine).length!=afterCount)unavailable++;
        if(afterCount>before)recovered+=afterCount-before;
        after=id;
        onProgress?.call(checked,recovered,unavailable);
      }
      // A resumable UI scan checkpoints; explicit reconciliation can always
      // re-read an edited invoice from the beginning without a stale cursor.
      if(resume){await db.customStatement(
        'INSERT INTO regular_payroll_recovery_cursor VALUES(?,?,?,0) '
        'ON CONFLICT(business_id,job_id) DO UPDATE SET cursor=excluded.cursor,complete=0',
        [business,scope,after]);}
      await onBatch?.call();
      await Future<void>.delayed(const Duration(milliseconds:10));
    }
    return true;
  }

  Future<void> refreshInvoiceTasks() async {
    _authorize();
    await prepare();
    final details = await LocalDocumentDetailCache(database: db).loadAll(business);
    for (final detail in details) {
      _authorize();
      final id = detail['id'];
      if (id is String) await LocalInvoiceTaskStore(db).save(business, id, detail);
    }
    final candidates = await _read(
      "SELECT t.id AS task_id,a.employee_id FROM regular_payroll_tasks t "
      "JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id "
      "JOIN local_jobs j ON j.business_id=t.business_id AND j.id=t.job_id "
      "JOIN local_job_assignments a ON a.business_id=j.business_id AND a.job_id=j.id AND a.active=1 "
      "JOIN regular_payroll_employees e ON e.business_id=a.business_id AND e.id=a.employee_id "
      "WHERE t.business_id=? AND s.active=1 AND s.source_kind='invoice' AND e.rate>0 "
      "AND EXISTS(SELECT 1 FROM local_documents d WHERE d.business_id=s.business_id AND d.id=s.invoice_id AND date(d.document_date)=d.document_date AND d.document_date >= '${LocalInvoiceTaskStore.payrollCutover}') "
      "AND (a.employee_id=j.assigned_employee_id OR (j.assigned_employee_id IS NULL AND "
      "(SELECT COUNT(*) FROM local_job_assignments a2 WHERE a2.business_id=j.business_id "
      "AND a2.job_id=j.id AND a2.active=1)=1)) "
      "AND NOT EXISTS(SELECT 1 FROM regular_payroll_portions p "
      "WHERE p.business_id=t.business_id AND p.task_id=t.id)",
      [business],
    );
    await db.transaction(() async {
      for (final row in candidates) {
        _authorize();
        final exists = await _read(
          'SELECT id FROM regular_payroll_portions WHERE business_id=? AND task_id=?',
          [business, row['task_id'] as String],
        );
        if (exists.isEmpty) await _assign(row['task_id'] as String, row['employee_id'] as String);
      }
    });
    _authorize();
  }

  /// Hydrate only saved pay data, plus the Owner's explicit Nov 12 missing-rate
  /// correction for uniquely identified Chris/Kam. Never replace a saved rate.
  Future<List<Map<String,dynamic>>> localCompensation(List<Map<String,dynamic>> roster,{LocalOwnerGrant? grant}) async {
    _authorize(); await prepare();
    final saved=await employees();
    final byId=<String,Map<String,dynamic>>{
      for(final r in roster) if(r['id'] is String) r['id'] as String: {...r},
      for(final r in saved) r['id'] as String: {...?roster.where((x)=>x['id']==r['id']).firstOrNull,...r},
    };
    await db.transaction(() async {
      for(final entry in byId.entries) {
        final r=entry.value;
        if(grant!=null) {
          try {
            final snapshot=await const SecureEmployeeDetailsCache().read(business,entry.key,grant);
            final details=snapshot?['details'] as Map?;
            if(details!=null) {
              for(final key in ['payment_type','hourly_rate','weekly_rate','compensation_enabled']) {
                if(details.containsKey(key))r[key]=details[key];
              }
            }
          } on StateError { /* Expired private snapshots never replace saved local pay. */ }
        }
        final existing=saved.where((x)=>x['id']==entry.key).firstOrNull;
        final name=(r['name']??'').toString().trim();
        final normalized=name.toLowerCase();
        final known=const {'chris rideaux':4000,'chris':4000,'kamerron smith':3500,'kam':3500};
        final approved=known[normalized];
        final unique=byId.values.where((x)=>(x['name']??'').toString().trim().toLowerCase()==normalized).length==1;
        final raw=num.tryParse(r['hourly_rate']?.toString()??'');
        final remoteRate=raw!=null && raw.isFinite && raw>0 ? (raw*100).round():null;
        final type=r['payment_type']?.toString();
        final base=existing?['base_enabled']==1 || const {'fixed_weekly','flexible_weekly'}.contains(type);
        var rate=existing?['rate'] as int?;
        if((rate==null || rate==0) && !base && r['compensation_enabled']!=false) {
          final recovered=remoteRate ?? (unique?approved:null);
          if(recovered!=null && recovered>0 && name.isNotEmpty) {
            await saveEmployeeCompensation(employee:entry.key,name:name,rate:recovered,weeklyBase:false);
            await db.customStatement('INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
              [business,entry.key,'local_saved_compensation_hydrated',jsonEncode({'rate':recovered,'source':remoteRate==null?'owner_2026_11_12':'saved_employee_settings'})]);
            rate=recovered;
          }
        }
        var defaults=await weeklyDefaults(entry.key);
        if(base && existing==null && name.isNotEmpty) {
          final weekly=num.tryParse(r['weekly_rate']?.toString()??'');
          if(weekly!=null && weekly.isFinite && weekly>=0) {
            if(type=='flexible_weekly') {
              await saveEmployeeCompensation(employee:entry.key,name:name,rate:remoteRate??0,weeklyBase:true);
              await saveWeeklyDefaults(entry.key,(weekly*100).round(),remoteRate??0,0,true);
            } else {
              await saveLocalPayBasis(employee:entry.key,name:name,paymentType:'fixed_weekly',amountCents:(weekly*100).round());
            }
            defaults=await weeklyDefaults(entry.key);rate=type=='flexible_weekly'?remoteRate??0:0;
          }
        }
        r['rate']=rate;
        r['hourly_rate']=rate==null?null:rate/100;
        r['base_enabled']=base?1:0;
        r['payment_type']=base ? (type=='fixed_weekly' || defaults?['add_labor']==0?'fixed_weekly':'flexible_weekly') : (rate==null?type:'hourly');
        if(defaults!=null) r['weekly_rate']=(defaults['base_cents'] as int)/100;
        r['pay_saved_locally']=existing!=null || rate!=null || defaults!=null;
      }
      _authorize();
    });
    return byId.values.toList();
  }

  /// Apply only the exact task the Owner identified. Match local stable IDs,
  /// reject ambiguous/paid evidence, and retain the original task and invoice.
  Future<String?> applyNov12OilSeparatorCarry() async {
    _authorize(); await prepare();
    try { return await db.transaction(() async {
      final matches=(await work()).where((r)=>r['job_number']=='J-40' &&
        (r['description']??'').toString().trim().toLowerCase()=='oil separator' &&
        const {'chris','chris rideaux'}.contains((r['employee_name']??'').toString().trim().toLowerCase())).toList();
      if(matches.isEmpty)return null;
      if(matches.length!=1)return 'Oil Separator needs review: more than one matching allocation. No records changed.';
      final row=matches.single, id=row['id'] as String, employee=row['employee_id'] as String;
      final invoices=await _read("SELECT id FROM local_documents WHERE business_id=? AND job_id=? AND kind='invoice' AND document_number='6359'",[business,row['job_id'] as String]);
      if(invoices.length!=1)return 'Oil Separator needs review: saved Gloria invoice identity is unavailable.';
      final existing=await _read('SELECT week FROM regular_payroll_carry_weeks_v1 WHERE business_id=? AND allocation_id=?',[business,id]);
      if(existing.isNotEmpty)return null;
      // Existing Owner audit travels with the protected payroll ledger. Rebuild
      // only this local index after a restore, without another carry operation.
      final restored=await _read("SELECT 1 FROM regular_payroll_audit WHERE business_id=? AND operation_id=? AND event='owner_reviewed_unpaid_carry' AND json_extract(payload,'\$.week')='2026-11-09' AND json_extract(payload,'\$.minutes')=600 AND json_extract(payload,'\$.rate')=4000",[business,id]);
      if(restored.isNotEmpty) {
        await db.customStatement('INSERT INTO regular_payroll_carry_weeks_v1 VALUES(?,?,?,?)',[business,id,'2026-11-09','Warranty rework · Owner-authorized unpaid carry-forward']);
        return null;
      }
      final covered=await _read('SELECT credit_id FROM regular_payroll_work_coverage WHERE business_id=? AND credit_id=?',[business,id]);
      final minutes=row['estimated_minutes'] as int? ?? 0;
      final actual=row['actual_minutes'] as int? ?? 0;
      final rate=(await employees()).where((e)=>e['id']==employee).firstOrNull?['rate'];
      if(covered.isNotEmpty || row['owner_prior_paid']==1 || row['paid']==1 || row['paid_minutes']!=0 ||
          row['assignment_conflict']==1 || row['recordkeeping_only']==true || minutes!=600 ||
          (actual!=0 && actual!=600) || rate!=4000) {
        return 'Oil Separator needs review: hours, saved rate or paid coverage differ. No records changed.';
      }
      await db.customStatement('INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [business,id,'owner_reviewed_unpaid_carry',jsonEncode({'employee':employee,'week':'2026-11-09','minutes':600,'rate':4000,'reason':'Owner instruction November 12: existing Oil Separator warranty rework, completed and unpaid. Nonbillable.'})]);
      // Preserve a completed task's original completion date; establish one
      // only when the saved task had not recorded its completed work yet.
      if(row['credit_completed']!=1 || actual!=600) {
        await _updateWork(id,'Done',600,'2026-11-12',expectedRevision:row['version'] as int,authorize:_authorize);
      }
      await db.customStatement('INSERT INTO regular_payroll_carry_weeks_v1 VALUES(?,?,?,?)',
        [business,id,'2026-11-09','Warranty rework · Owner-authorized unpaid carry-forward']);
      _authorize(); return null;
    }); } on StateError catch(error) {
      _authorize(); return 'Oil Separator needs review; saved records were preserved: $error';
    }
  }

  Future<void> savePayrollDraft(String employee,String week,Map<String,double> selected,{int adjustment=0,int repayment=0,String reason=''}) async {
    _authorize(); await prepare(); _date(week);
    if(selected.values.any((h)=>!h.isFinite||h<=0) || repayment<0 || adjustment.abs()>100000000 || (adjustment!=0 && reason.trim().isEmpty))throw ArgumentError('Invalid payroll draft');
    await db.customStatement('INSERT INTO regular_payroll_drafts_v1 VALUES(?,?,?,?) ON CONFLICT(business_id,employee_id,week) DO UPDATE SET payload=excluded.payload',
      [business,employee,week,jsonEncode({'hours':selected,'adjustment':adjustment,'repayment':repayment,'reason':reason})]);
    _authorize();
  }
  Future<Map<String,dynamic>?> payrollDraftDetails(String employee,String week) async {
    _authorize(); await prepare();
    final rows=await _read('SELECT payload FROM regular_payroll_drafts_v1 WHERE business_id=? AND employee_id=? AND week=?',[business,employee,week]);
    if(rows.isEmpty)return null;
    final value=Map<String,dynamic>.from(jsonDecode(rows.single['payload'] as String) as Map);
    return value['hours'] is Map ? value : {'hours':value,'adjustment':0,'repayment':0,'reason':''};
  }
  Future<Map<String,double>?> payrollDraft(String employee,String week) async {
    final value=await payrollDraftDetails(employee,week);
    return (value?['hours'] as Map?)?.map((k,v)=>MapEntry(k as String,(v as num).toDouble()));
  }

  Future<void> saveEmployeeCompensation({
    required String employee, required String name, required int rate, required bool weeklyBase,
  }) async {
    _authorize();
    if (employee.isEmpty || name.trim().isEmpty || rate < 0) {
      throw ArgumentError('Valid employee compensation is required.');
    }
    await prepare();
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,?) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,'
        'rate=excluded.rate,base_enabled=excluded.base_enabled',
        [business, employee, name, rate, weeklyBase ? 1 : 0],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)', [business, employee],
      );
      _authorize();
    });
  }

  /// Set the locally effective compensation basis for future payroll review.
  /// Saved receipts and existing paid labor allocations are immutable. This
  /// does not pretend to update the server employee record while offline.
  Future<void> saveLocalPayBasis({
    required String employee,
    required String name,
    required String paymentType,
    required int amountCents,
  }) async {
    _authorize();
    if (employee.trim().isEmpty || name.trim().isEmpty ||
        !const {'hourly', 'fixed_weekly'}.contains(paymentType) ||
        amountCents < 0 || amountCents > 100000000) {
      throw ArgumentError('Invalid employee payment settings.');
    }
    await prepare();
    await db.transaction(() async {
      _authorize();
      final fixed = paymentType == 'fixed_weekly';
      final prior = await weeklyDefaults(employee);
      final adjustment = prior?['adjustment_cents'] as int? ?? 0;
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,?) '
        'ON CONFLICT(business_id,id) DO UPDATE SET '
        'rate=excluded.rate,base_enabled=excluded.base_enabled',
        [business, employee, name, fixed ? 0 : amountCents, fixed ? 1 : 0],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
        [business, employee],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_weekly_defaults VALUES(?,?,?,?,?,?) '
        'ON CONFLICT(business_id,employee_id) DO UPDATE SET '
        'base_cents=excluded.base_cents,hourly_cents=excluded.hourly_cents,'
        'adjustment_cents=excluded.adjustment_cents,'
        'add_labor=excluded.add_labor',
        [business, employee, fixed ? amountCents : 0,
         fixed ? 0 : amountCents, adjustment, fixed ? 0 : 1],
      );
      _authorize();
    });
  }

  Future<void> createRecheck({
    required String operation, required String job, required String description,
    required String employee, required String name, required int rate,
    required int estimatedMinutes, String kind = 'recheck', Future<void> Function()? queueChange,
  }) async {
    _authorize();
    if ([operation, job, employee, name, description].any((value) => value.trim().isEmpty) ||
        rate < 0 || estimatedMinutes < 0 || !['job','recheck'].contains(kind)) {
      throw ArgumentError('Invalid recheck.');
    }
    await prepare();
    await db.transaction(() async {
      final source = await _read(
        'SELECT j.title FROM local_jobs j JOIN local_job_assignments a '
        'ON a.business_id=j.business_id AND a.job_id=j.id AND a.active=1 '
        'WHERE j.business_id=? AND j.id=? AND a.employee_id=?',
        [business, job, employee],
      );
      if (source.isEmpty) throw StateError('Save the job and mechanic assignment first.');
      final task = jsonEncode([job, kind, operation]);
      final labor = jsonEncode([kind, operation]);
      final prior = await _read(
        'SELECT description,planned FROM regular_payroll_tasks WHERE business_id=? AND id=?',
        [business, task],
      );
      if (prior.isNotEmpty) {
        if (prior.single['description'] != description.trim() ||
            prior.single['planned'] != (estimatedMinutes * 100 + 30) ~/ 60) {
          throw StateError('Conflicting recheck retry.');
        }
        await queueChange?.call();
        return;
      }
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,0) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,rate=CASE WHEN regular_payroll_employees.rate=0 THEN excluded.rate ELSE regular_payroll_employees.rate END',
        [business, employee, name, rate],
      );
      await db.customStatement('INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
        [business, employee]);
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_jobs VALUES(?,?,?)',
        [business, job, source.first['title']],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_tasks VALUES(?,?,?,?,?,?)',
        [business, task, job, labor, description.trim(), (estimatedMinutes * 100 + 30) ~/ 60],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_task_sources VALUES(?,?,NULL,NULL,?,1)", [business, task, kind],
      );
      await _assign(task, employee);
      await queueChange?.call();
      _authorize();
    });
  }

  Future<void> reviewUnpaidCarry(String employee,String allocation) async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      final row = (await work(employee:employee)).where((r)=>r['id']==allocation).single;
      if(row['recordkeeping_only']==true) throw StateError('Reconcile the original mechanic allocation before carrying this corrected historical record into payroll.');
      if(row['archived_labor']!=1 || row['paid_minutes']!=0 || row['assignment_conflict']==1) {
        throw StateError('Only unreviewed unpaid historical work can be carried forward.');
      }
      await db.customStatement('INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [business,allocation,'owner_reviewed_unpaid_carry',jsonEncode({'employee':employee,'reviewed_at':DateTime.now().toUtc().toIso8601String()})]);
      _authorize();
    });
  }

  Future<void> removeOpenAllocation(String task,String employee) async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      final open = await _read(
        "SELECT p.id FROM regular_payroll_portions p JOIN local_mechanic_work_credits_v1 c "
        "ON c.business_id=p.business_id AND c.allocation_id=p.id WHERE p.business_id=? AND p.task_id=? "
        "AND p.employee_id=? AND p.state='Open' AND c.actual_minutes=0 AND c.completed=0 AND c.paid_operation_id IS NULL "
        "AND NOT EXISTS(SELECT 1 FROM regular_payroll_actual_time at WHERE at.business_id=p.business_id AND at.credit_id=p.id AND at.minutes>0) "
        "AND NOT EXISTS(SELECT 1 FROM regular_payroll_work_coverage w WHERE w.business_id=p.business_id AND w.credit_id=p.id)",
        [business,task,employee]);
      if(open.isEmpty) throw StateError('Started, earned or paid work cannot be removed.');
      await db.customStatement('INSERT INTO regular_payroll_assignment_meta(business_id,task_id,employee_id,inherited,active) VALUES(?,?,?,0,0) '
        'ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET active=0,revision=revision+1 WHERE active=1',[business,task,employee]);
      await db.customStatement('INSERT INTO regular_payroll_task_policy VALUES(?,?,1) ON CONFLICT(business_id,task_id) DO UPDATE SET manual_override=1',[business,task]);
      _authorize();
    });
  }

  Future<void> editAllocation({required String task, required String previous,
    required String employee, required String name, required int minutes}) async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      final historical = (await work()).where((r) => r['task_id']==task &&
        r['employee_id']==previous && r['archived_labor']==1 && r['source_active']!=0).toList();
      if(historical.length==1) {
        if(previous!=employee && (await work()).any((r)=>r['task_id']==task && r['employee_id']==employee)) {
          throw StateError('This mechanic already has an allocation on this task.');
        }
        await HistoricalTaskRecordkeeping(db).save(business,
          historical.single['id'] as String,employee,name,minutes);
        await db.customStatement('INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
          [business,historical.single['id'],'historical_recordkeeping_only',
            jsonEncode({'employee':employee,'minutes':minutes})]);
        _authorize();
        return;
      }
      if (previous != employee) {
        final open = await _read(
          "SELECT p.id,p.state FROM regular_payroll_portions p "
          "JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id "
          "LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id "
          "WHERE p.business_id=? AND p.task_id=? AND p.employee_id=? AND p.state IN ('Open','In Progress') AND COALESCE(m.active,1)=1 "
          "AND c.actual_minutes=0 AND c.completed=0 AND c.paid_operation_id IS NULL "
          "AND NOT EXISTS(SELECT 1 FROM regular_payroll_actual_time at WHERE at.business_id=p.business_id AND at.credit_id=p.id AND at.minutes>0) "
        "AND NOT EXISTS(SELECT 1 FROM regular_payroll_work_coverage w WHERE w.business_id=p.business_id AND w.credit_id=p.id)",
          [business,task,previous]);
        if (open.isEmpty) throw StateError('Completed, credited or paid work cannot change mechanic.');
        final existing = await _read(
          'SELECT id FROM regular_payroll_portions WHERE business_id=? AND task_id=? AND employee_id=?',
          [business,task,employee]);
        if (existing.isNotEmpty) throw StateError('This mechanic already has an allocation on this task.');
        if ((await _read('SELECT id FROM regular_payroll_employees WHERE business_id=? AND id=?',[business,employee])).isEmpty) {
          await saveEmployeeCompensation(employee:employee,name:name,rate:0,weeklyBase:false);
        }
        if(open.single['state']=='In Progress') {
          final id=open.single['id'];
          await db.customStatement('INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
            [business,id,'owner_reassigned_unearned_work',jsonEncode({'from':previous,'to':employee,'status':'In Progress'})]);
          await db.customStatement("UPDATE regular_payroll_portions SET state='Open',version=version+1 WHERE business_id=? AND id=?",[business,id]);
          await db.customStatement("UPDATE local_mechanic_work_credits_v1 SET revision=revision+1 WHERE business_id=? AND allocation_id=?",[business,id]);
        }
        await LocalTaskAssignmentStore(db).allocate(business,task,employee,inherited:false);
        await db.customStatement(
          'INSERT INTO regular_payroll_assignment_meta(business_id,task_id,employee_id,inherited,active) VALUES(?,?,?,0,0) '
          'ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET active=0,revision=revision+1',
          [business,task,previous]);
      }
      await setEstimatedMinutes(task, employee, minutes,
          reviseCompletedUnpaid: previous == employee);
      _authorize();
    });
  }

  /// Record the Owner's explicit confirmation of wages paid BEFORE this
  /// task entered the new payroll workflow. This is NOT a new payroll payment.
  /// One immutable allocation/employee share is settled, not the entire job.
  Future<void> confirmHistoricalAlreadyPaid(String allocation) async {
    _authorize();
    await assertLanWriter?.call();
    await prepare();
    await db.transaction(() async {
      final rows = await _read(
        'SELECT p.id,p.task_id,p.employee_id,p.state,c.revision,c.actual_minutes,'
        'c.paid_operation_id,COALESCE(e.minutes,0) AS estimated_minutes '
        'FROM regular_payroll_portions p '
        'JOIN local_mechanic_work_credits_v1 c '
        'ON c.business_id=p.business_id AND c.allocation_id=p.id '
        'LEFT JOIN regular_payroll_estimates e ON e.business_id=p.business_id '
        'AND e.task_id=p.task_id AND e.employee_id=p.employee_id '
        'WHERE p.business_id=? AND p.id=?',
        [business,allocation],
      );
      if (rows.length != 1) throw StateError('Saved labor allocation unavailable.');
      final row = rows.single;
      final previous = await _read(
        'SELECT allocation_id FROM regular_payroll_owner_prior_paid_v1 '
        'WHERE business_id=? AND allocation_id=?',
        [business,allocation],
      );
      if (previous.isNotEmpty) return; // Idempotent confirmation, no new pay.
      final paid = await _read(
        'SELECT credit_id FROM regular_payroll_work_coverage '
        'WHERE business_id=? AND credit_id=? LIMIT 1',
        [business,allocation],
      );
      if (row['paid_operation_id'] != null || paid.isNotEmpty) {
        throw StateError('This portion is already settled in payroll.');
      }
      final minutes = (row['actual_minutes'] as int) > 0
          ? row['actual_minutes'] as int
          : row['estimated_minutes'] as int;
      if (minutes <= 0) {
        throw StateError('Enter the historical mechanic hours before marking Already Paid.');
      }
      // No historical completion date is invented. The Owner's confirmation
      // establishes Done now; prior actual dates remain intact if saved.
      await LocalMechanicWorkCreditRepository(database:db).recordWork(
        businessId:business, allocationId:allocation,
        employeeId:row['employee_id'] as String,
        expectedRevision:row['revision'] as int,
        actualMinutes:minutes, completed:true,
      );
      await db.customStatement(
        "UPDATE regular_payroll_portions SET state='Done',version=version+1 "
        'WHERE business_id=? AND id=?',
        [business,allocation],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_actual_time(business_id,credit_id,minutes,revision) '
        'SELECT ?,?,?,revision FROM local_mechanic_work_credits_v1 '
        'WHERE business_id=? AND allocation_id=? '
        'ON CONFLICT(business_id,credit_id) DO UPDATE SET '
        'minutes=excluded.minutes,revision=excluded.revision',
        [business,allocation,minutes,business,allocation],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await db.customStatement(
        'INSERT INTO regular_payroll_owner_prior_paid_v1 '
        '(business_id,allocation_id,employee_id,confirmed_at) VALUES(?,?,?,?)',
        [business,allocation,row['employee_id'],now],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) '
        'VALUES(?,?,?,?)',
        [business,allocation,'owner_confirmed_historical_already_paid',
         jsonEncode({'employee':row['employee_id'],'minutes':minutes,
           'confirmed_at':now,'payment_record_created':false})],
      );
      _authorize();
    });
  }

  /// Owner correction to an existing allocation. A completed but UNPAID
  /// portion can have its assigned and credited time corrected together.
  /// Payment coverage/operation locks are never bypassed, and we never
  /// create a new allocation or a second wage credit for this correction.
  Future<void> setEstimatedMinutes(String task, String employee, int minutes, {
    bool reviseCompletedUnpaid = false,
  }) async {
    _authorize();
    if (minutes < 0 || minutes > 600000) throw ArgumentError('Invalid estimated minutes.');
    await prepare();
    await db.transaction(() async {
      final assignment = await _read(
        'SELECT p.id,p.state,c.revision,c.completed FROM regular_payroll_portions p '
        'JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id '
        'LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id '
        'WHERE p.business_id=? AND p.task_id=? AND p.employee_id=? AND COALESCE(m.active,1)=1 '
        'AND c.paid_operation_id IS NULL '
        'AND NOT EXISTS(SELECT 1 FROM regular_payroll_work_coverage w WHERE w.business_id=p.business_id AND w.credit_id=p.id) '
        'AND NOT EXISTS(SELECT 1 FROM regular_payroll_owner_prior_paid_v1 h WHERE h.business_id=p.business_id AND h.allocation_id=p.id)',
        [business, task, employee],
      );
      if (assignment.length != 1) {
        throw StateError('Mechanic allocation is unavailable or already paid.');
      }
      final row = assignment.single;
      if (row['state'] == 'Done' && !reviseCompletedUnpaid) {
        throw StateError('Completed labor requires the Owner correction action.');
      }
      if (row['state'] == 'Done' && minutes == 0) {
        throw StateError('Completed labor must retain positive credited time.');
      }
      if (row['state'] == 'Done') {
        // Preserve Done and the original completion date while revising the
        // exact SAME unpaid allocation; no new task or payroll payment.
        await LocalMechanicWorkCreditRepository(database: db).recordWork(
          businessId: business,
          allocationId: row['id'] as String,
          employeeId: employee,
          expectedRevision: row['revision'] as int,
          actualMinutes: minutes,
          completed: true,
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_actual_time(business_id,credit_id,minutes,revision) '
          'SELECT ?,?,?,revision FROM local_mechanic_work_credits_v1 '
          'WHERE business_id=? AND allocation_id=? '
          'ON CONFLICT(business_id,credit_id) DO UPDATE SET '
          'minutes=excluded.minutes,revision=excluded.revision',
          [business,row['id'],minutes,business,row['id']],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) '
          'VALUES(?,?,?,?)',
          [business,row['id'],'owner_corrected_completed_unpaid_hours',
           jsonEncode({'task':task,'employee':employee,'minutes':minutes,
             'recorded_at':DateTime.now().toUtc().toIso8601String()})],
        );
      }
      await db.customStatement(
        'INSERT INTO regular_payroll_estimates VALUES(?,?,?,?) '
        'ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET minutes=excluded.minutes',
        [business, task, employee, minutes],
      );
      _authorize();
    });
  }

  Future<void> setMainMechanic(String job, String? employee, String? name) async {
    _authorize(); await prepare();
    await db.transaction(() async {
      _authorize();
      await OfflineJobAdminService(database: db).queueMainMechanic(business, job,
        employeeId: employee, employeeName: name);
      await db.customStatement('INSERT INTO regular_payroll_job_lead(business_id,job_id,employee_id,employee_name) VALUES(?,?,?,?) '
        'ON CONFLICT(business_id,job_id) DO UPDATE SET employee_id=excluded.employee_id,employee_name=excluded.employee_name,revision=revision+1 '
        'WHERE employee_id IS NOT excluded.employee_id OR employee_name IS NOT excluded.employee_name',[business,job,employee,name]);
      if (employee != null) {
        // Recover saved sources regardless of invoice age or paid/closed status.
        // This does not authorize historical carry-forward.
        final older = await _read(
          "SELECT id FROM local_documents WHERE business_id=? AND job_id=? AND kind='invoice'",
          [business,job]);
        for (final row in older) {
          final id = row['id'] as String;
          final detail = await LocalDocumentDetailCache(database:db).load(business,id);
          if (detail != null) {
            await LocalInvoiceTaskStore(db).save(business,id,detail,ownerAssignedOpenDocument:true);
          }
        }
        await LocalTaskAssignmentStore(db).inherit(business, job);
      } else {
        for(final task in await tasks()){
          if(task['job_id']==job)await LocalTaskAssignmentStore(db).retireInherited(business,task['id'] as String);
        }
      }
      _authorize();
    });
  }

  Future<void> recoverJobAssignments(String job) async {
    _authorize();
    await prepare();
    final documents = await _read(
      "SELECT id FROM local_documents WHERE business_id=? AND job_id=? AND kind='invoice'",
      [business,job]);
    for (final document in documents) {
      await LocalDocumentDetailCache(database:db).load(business,document['id'] as String);
    }
    await LocalTaskAssignmentStore(db).inherit(business,job);
  }

  /// Assign an existing service, without creating or editing a billed item.
  Future<void> assignExistingService({required String job, required String invoice,
    required String line, required String employee, required String name,
    required int rate, int? minutes}) async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      final detail = await LocalDocumentDetailCache(database:db).load(business,invoice);
      if (detail == null || detail['job_id'] != job || detail['kind'] != 'invoice') {
        throw StateError('Saved invoice is unavailable.');
      }
      final raw = detail['lines'] ?? detail['items'];
      if (raw is! List || raw.whereType<Map>().where((r)=>r['id']==line).length != 1) {
        throw StateError('Saved service is unavailable.');
      }
      await LocalInvoiceTaskStore(db).save(business,invoice,detail,selectedServiceLine:line);
      final task = (await tasks()).where((r)=>r['invoice_id']==invoice && r['source_line_id']==line && r['source_active']!=0).single;
      final staff = await employees();
      if (!staff.any((r)=>r['id']==employee)) {
        await saveEmployeeCompensation(employee:employee,name:name,rate:rate,weeklyBase:false);
      }
      await LocalTaskAssignmentStore(db).allocate(business,task['id'] as String,employee,inherited:false);
      if (minutes != null) await setEstimatedMinutes(task['id'] as String,employee,minutes);
      _authorize();
    });
  }

  Future<void> assignTask(String task, String employee, String name, {int rate=0}) async {
    _authorize(); await prepare();
    await db.transaction(() async {
      _authorize();
      final staff=await _read('SELECT id FROM regular_payroll_employees WHERE business_id=? AND id=?',[business,employee]);
      if(staff.isEmpty) await saveEmployeeCompensation(employee:employee,name:name,rate:rate,weeklyBase:false);
      final assignments=LocalTaskAssignmentStore(db);
      await assignments.retireInherited(business,task,except:employee);
      await assignments.allocate(business,task,employee,inherited:false);
      _authorize();
    });
  }

  Future<void> acceptChangedAssignment(String id) async {
    _authorize();await prepare();
    await db.transaction(()async{
      final row=(await _read('SELECT task_id,employee_id FROM local_mechanic_work_credits_v1 WHERE business_id=? AND allocation_id=?',[business,id])).single;
      await db.customStatement('UPDATE regular_payroll_assignment_meta SET active=1,inherited=0,revision=revision+1 WHERE business_id=? AND task_id=? AND employee_id=?',
        [business,row['task_id'],row['employee_id']]);
      await db.customStatement('INSERT INTO regular_payroll_task_policy VALUES(?,?,1) ON CONFLICT(business_id,task_id) DO UPDATE SET manual_override=1',[business,row['task_id']]);
      _authorize();
    });
  }

  Future<void> recordAllocatedTime(String id, String state, int actualMinutes, int creditedMinutes, String date) async {
    _authorize(); await prepare();
    if(actualMinutes<0||creditedMinutes<0)throw ArgumentError('Hours must be positive.');
    await db.transaction(() async {
      final covered=await _read('SELECT credit_id FROM regular_payroll_work_coverage WHERE business_id=? AND credit_id=?',[business,id]);
      if(covered.isNotEmpty)throw StateError('Paid time is immutable. Create a separate recheck.');
      await _updateWork(id,state,creditedMinutes,date,expectedRevision:null,authorize:_authorize);
      await db.customStatement('INSERT INTO regular_payroll_actual_time(business_id,credit_id,minutes,revision) SELECT ?,?,?,revision FROM local_mechanic_work_credits_v1 WHERE business_id=? AND allocation_id=? '
        'ON CONFLICT(business_id,credit_id) DO UPDATE SET minutes=excluded.minutes,revision=excluded.revision',[business,id,actualMinutes,business,id]);
      _authorize();
    });
  }

  Future<List<Map<String, dynamic>>> employees() async {
    _authorize();
    await prepare();
    return _read('SELECT * FROM regular_payroll_employees WHERE business_id=? ORDER BY id', [
      business,
    ]);
  }

  Future<List<Map<String, dynamic>>> assignedEmployees(String jobId) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT DISTINCT a.employee_id, a.employee_name, e.name, e.rate '
      'FROM local_job_assignments a LEFT JOIN regular_payroll_employees e '
      'ON e.business_id=a.business_id AND e.id=a.employee_id '
      'WHERE a.business_id=? AND a.job_id=? AND a.active=1',
      [business, jobId],
    );
    _authorize();
    return rows;
  }

  /// Capture the actual Job, invoice line and assignment in one transaction.
  /// The caller supplies compensation from the authorized employee profile.
  Future<void> registerAssignedLabor({
    required String jobId,
    required String invoiceId,
    required String lineId,
    required String employeeId,
    required String employeeName,
    required int rateCents,
    Future<void> Function()? queueChange,
  }) async {
    _authorize();
    if (employeeName.trim().isEmpty || rateCents < 0) {
      throw ArgumentError('A saved employee name and hourly rate are required');
    }
    await prepare();
    await db.transaction(() async {
      final invoice = await _read("SELECT document_date FROM local_documents WHERE business_id=? AND id=? AND job_id=? AND kind='invoice'",
        [business,invoiceId,jobId]);
      if(!LocalInvoiceTaskStore.currentPayrollDate(invoice.firstOrNull?['document_date'])) {
        // Replaying an existing settled identity after invoice/job remapping
        // is a no-op. Never enqueue another assignment or modify its hours.
        final retained = await _read(
          'SELECT p.id FROM regular_payroll_task_sources s '
          'JOIN regular_payroll_tasks t ON t.business_id=s.business_id AND t.id=s.task_id '
          'JOIN regular_payroll_portions p ON p.business_id=t.business_id AND p.task_id=t.id '
          'JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id '
          'WHERE s.business_id=? AND s.invoice_id=? AND s.line_id=? AND t.job_id=? AND p.employee_id=? '
          "AND p.state='Done' AND c.completed=1 AND (c.paid_operation_id IS NOT NULL OR "
          '(SELECT SUM(w.minutes) FROM regular_payroll_work_coverage w WHERE w.business_id=p.business_id '
          'AND w.credit_id=p.id)=c.actual_minutes)',[business,invoiceId,lineId,jobId,employeeId]);
        if(retained.length==1) {
          _authorize();
          return;
        }
        throw StateError('Review historical or undated invoice labor before carrying it forward.');
      }
      final line = await LocalPayrollWorkSource(db).resolve(
        businessId: business,
        jobId: jobId,
        invoiceId: invoiceId,
        lineId: lineId,
        employeeId: employeeId,
      );
      if (line == null) {
        throw StateError('Saved invoice labor or active assignment is missing');
      }
      final job = (await _read(
        'SELECT title FROM local_jobs WHERE business_id=? AND id=?',
        [business, jobId],
      )).single;
      final laborId = jsonEncode([invoiceId, lineId]);
      final sources = await _read(
        'SELECT task_id FROM regular_payroll_task_sources '
        'WHERE business_id=? AND invoice_id=? AND line_id=?',
        [business, invoiceId, lineId]);
      if (sources.length > 1) { throw StateError('Conflicting invoice task identity.'); }
      final task = sources.isEmpty ? jsonEncode([jobId, invoiceId, lineId])
          : sources.single['task_id'] as String;
      final description = line['description']?.toString().trim() ?? '';
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_jobs VALUES(?,?,?)',
        [business, jobId, job['title']],
      );
      // Manual assignment may run before invoice-task projection finishes.
      // Carry the customer-billable labor quantity into the initial *planned*
      // mechanic estimate instead of creating a permanent zero-hour task.
      // This does not mark work done or change credited/paid hours.
      final billableHours = LocalInvoiceTaskStore.invoiceLaborHours(line);
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_tasks VALUES(?,?,?,?,?,?)',
        [business, task, jobId, laborId,
          description.isEmpty ? 'Invoice labor' : description,
          billableHours == null ? 0 : (billableHours * 100).round()],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,0) '
        'ON CONFLICT(business_id,id) DO UPDATE SET name=excluded.name,rate=CASE WHEN regular_payroll_employees.rate=0 THEN excluded.rate ELSE regular_payroll_employees.rate END',
        [business, employeeId, employeeName, rateCents],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
        [business, employeeId],
      );
      await db.customStatement("INSERT OR IGNORE INTO regular_payroll_task_sources VALUES(?,?,?,?,'invoice',1)",
        [business,task,invoiceId,lineId]);
      await LocalTaskAssignmentStore(db).allocate(business,task,employeeId,inherited:false);
      await queueChange?.call();
      _authorize();
    });
  }

  Future<void> _assign(String task, String employee) async {
    _authorize();
    await prepare();
    await db.transaction(() async {
      final tasks = await _read(
        'SELECT * FROM regular_payroll_tasks WHERE business_id=? AND id=?',
        [business, task],
      );
      final staff = await _read(
        'SELECT * FROM regular_payroll_employees WHERE business_id=? AND id=?',
        [business, employee],
      );
      if (tasks.length != 1 || staff.length != 1)
        { throw StateError('Task or employee missing'); }
      final id = jsonEncode([task, employee]);
      await db.customStatement(
        "INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES(?,?,?,?,'Open')",
        [business, id, task, employee],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_estimates VALUES(?,?,?,?)',
        [business, task, employee, ((tasks.single['planned'] as int) * 60 + 50) ~/ 100],
      );
      await LocalMechanicWorkCreditRepository(database: db).createAssignment(
        businessId: business, allocationId: id, jobId: tasks.single['job_id'] as String,
        laborLineId: tasks.single['labor_id'] as String, taskId: task, employeeId: employee,
        actualMinutes: 0,
        rateCents: staff.single['rate'] as int,
      );
    });
  }

  Future<List<Map<String, dynamic>>> assignmentSnapshots(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT c.allocation_id AS credit,t.job_id AS job,c.rate_cents AS rate,'
      '(SELECT confirmed_at FROM regular_payroll_owner_prior_paid_v1 h WHERE h.business_id=c.business_id AND h.allocation_id=c.allocation_id) AS prior_paid_at,'
      'c.task_id,c.job_id AS credit_job,c.labor_line_id AS credit_labor,'
      'c.actual_minutes AS total_credit_minutes,c.revision AS credit_revision,p.state,p.completed_date,'
      'COALESCE(at.minutes,c.actual_minutes) AS recorded_actual_minutes,'
      't.description,t.planned,s.invoice_id AS invoice,s.line_id AS line,'
      's.source_kind AS kind,CASE WHEN m.active=0 THEN 0 ELSE s.active END AS active,e.minutes AS estimated_minutes '
      'FROM local_mechanic_work_credits_v1 c '
      'JOIN regular_payroll_tasks t ON t.business_id=c.business_id AND t.id=c.task_id '
      'JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id '
      'LEFT JOIN regular_payroll_actual_time at ON at.business_id=c.business_id AND at.credit_id=c.allocation_id '
      'JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id '
      'LEFT JOIN regular_payroll_estimates e ON e.business_id=c.business_id '
      'AND e.task_id=c.task_id AND e.employee_id=c.employee_id '
      'LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=c.business_id AND m.task_id=c.task_id AND m.employee_id=c.employee_id '
      'WHERE c.business_id=? AND c.employee_id=? ORDER BY c.allocation_id',
      [business, employee],
    );
    return rows.map((row) {
      final task = jsonDecode(jsonDecode(row['credit'] as String)[0] as String) as List;
      return {...row, 'employee': employee,
        if (['recheck','job'].contains(row['kind'])) 'operation': task[2]};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> mechanicWork({
    required String? job,
    required String employee,
    required void Function() assertSession,
  }) async {
    assertSession();
    if (pairedEmployee != null && pairedEmployee != employee) {
      throw StateError('Only the paired employee can view this work.');
    }
    await prepare();
    final rows = await _read(
      'SELECT c.allocation_id AS id,t.job_id,t.description,p.state,c.actual_minutes,c.revision '
      'FROM local_mechanic_work_credits_v1 c '
      'JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id '
      'JOIN regular_payroll_tasks t ON t.business_id=p.business_id AND t.id=p.task_id '
      "WHERE c.business_id=? AND (?='' OR t.job_id=?) AND c.employee_id=? "
      "AND (p.state!='Open' OR NOT EXISTS(SELECT 1 FROM regular_payroll_task_sources s "
      'WHERE s.business_id=t.business_id AND s.task_id=t.id AND s.active=0)) '
      'AND (?=1 OR EXISTS (SELECT 1 FROM local_job_assignments a WHERE a.business_id=c.business_id '
      'AND a.job_id=t.job_id AND a.employee_id=c.employee_id AND a.active=1)) '
      'ORDER BY c.allocation_id',
      [business, job ?? '', job ?? '', employee, pairedEmployee == employee ? 1 : 0],
    );
    assertSession();
    return rows;
  }

  Future<void> updateMechanicWork({
    required String job,
    required String employee,
    required String id,
    required String state,
    required int minutes,
    required String date,
    required int expectedRevision,
    required void Function() assertSession,
    Future<void> Function()? queueChange,
  }) async {
    assertSession();
    await prepare();
    await db.transaction(() async {
      final rows = await mechanicWork(
        job: job, employee: employee, assertSession: assertSession,
      );
      final row = rows.where((row) => row['id'] == id).firstOrNull;
      final from = row?['state'];
      if (row == null || from == 'Done' ||
          (from == 'Open' && state != 'In Progress') ||
          (from == 'In Progress' && state != 'Done')) {
        throw StateError('This labor portion is unavailable.');
      }
      await _updateWork(
        id, state, minutes, date,
        expectedRevision: expectedRevision,
        authorize: assertSession, allowRetiredProgress: true,
      );
      await queueChange?.call();
    });
  }

  Future<({int unpaid, List<Map<String, dynamic>> receipts})> mechanicReport(
    String employee, void Function() assertLink,
  ) async {
    assertLink();
    if (owner || pairedEmployee != employee) {
      throw StateError('Only the paired employee can view these receipts.');
    }
    await prepare();
    final rows = await _read(
      'SELECT COALESCE(SUM((actual_minutes * rate_cents + 30)/60 - '
      '((COALESCE((SELECT SUM(x.minutes) FROM regular_payroll_work_coverage x '
      'WHERE x.business_id=local_mechanic_work_credits_v1.business_id '
      'AND x.credit_id=local_mechanic_work_credits_v1.allocation_id),0) * rate_cents + 30)/60)),0) AS unpaid '
      'FROM local_mechanic_work_credits_v1 WHERE business_id=? AND employee_id=? '
      'AND completed=1 AND paid_operation_id IS NULL',
      [business, employee],
    );
    final receipts = await _read(
      'SELECT operation_id,net,method,verified_date FROM regular_payroll_payments '
      'WHERE business_id=? AND employee_id=? ORDER BY verified_date DESC,operation_id',
      [business, employee],
    );
    assertLink();
    return (unpaid: rows.single['unpaid'] as int, receipts: receipts);
  }

  /// Apply only after the LAN transport validates the signed shop/employee
  /// envelope. The transport commits this change and the replay receipt together.
  Future<void> applyLanChange(
    PayrollLanOperation operation,
    Map<String, dynamic> payload, {
    required String employee,
    required void Function() assertLink,
  }) async {
    assertLink();
    if (payload['employee'] != employee) {
      throw StateError('Payroll change is for a different employee.');
    }
    await prepare();
    final job = payload['job'] as String?;
    switch (operation) {
      case PayrollLanOperation.ownerRoute:
        if (owner || pairedEmployee != employee) throw StateError('Only the paired mechanic receives Owner routes.');
        return;
      case PayrollLanOperation.progress:
        if (!owner) throw StateError('Only the Owner receives mechanic progress.');
        final event = jsonEncode([payload['id'], payload['revision']]);
        final body = _progressBody(payload);
        final prior = await _read('SELECT body FROM regular_payroll_progress_claims WHERE business_id=? AND employee_id=? AND event_id=?',
          [business, employee, event]);
        if (prior.isNotEmpty) {
          if (prior.single['body'] != body) throw StateError('Conflicting mechanic progress replay.');
          return;
        }
        await updateMechanicWork(
          job: job!, employee: employee, id: payload['id'] as String,
          state: payload['state'] as String, minutes: payload['minutes'] as int,
          date: payload['date'] as String,
          expectedRevision: payload['revision'] as int, assertSession: assertLink,
        );
        await db.customStatement('INSERT INTO regular_payroll_progress_claims VALUES(?,?,?,?)', [business, employee, event, body]);
      case PayrollLanOperation.assignment:
        if (owner || pairedEmployee != employee || job == null) {
          throw StateError('Labor assignment is unavailable to this device.');
        }
        final isRecheck = ['recheck','job'].contains(payload['kind']);
        final invoice = isRecheck ? 'recheck' : payload['invoice'] as String;
        final line = isRecheck ? payload['operation'] as String : payload['line'] as String;
        final labor = payload['credit_labor'] as String? ?? jsonEncode([invoice, line]);
        final task = payload['task_id'] as String? ?? jsonEncode([job, invoice, line]);
        final id = jsonEncode([task, employee]);
        final rate = payload['rate'] as int;
        final incomingRevision = payload['assignment_revision'] as int? ?? 0;
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS regular_payroll_assignment_incoming '
          '(business_id TEXT NOT NULL,credit TEXT NOT NULL,revision INTEGER NOT NULL,'
          'PRIMARY KEY(business_id,credit))');
        final previousRevision = await _read(
          'SELECT revision FROM regular_payroll_assignment_incoming '
          'WHERE business_id=? AND credit=?', [business, id]);
        if (previousRevision.isNotEmpty &&
            (previousRevision.single['revision'] as int) >= incomingRevision) { return; }
        await db.customStatement('INSERT INTO regular_payroll_assignment_incoming VALUES(?,?,?) '
          'ON CONFLICT(business_id,credit) DO UPDATE SET revision=excluded.revision',
          [business, id, incomingRevision]);
        await db.customStatement(
          'INSERT OR IGNORE INTO regular_payroll_jobs VALUES(?,?,?)',
          [business, job, job],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_tasks VALUES(?,?,?,?,?,?) '
          'ON CONFLICT(business_id,id) DO UPDATE SET description=excluded.description,planned=excluded.planned,job_id=excluded.job_id',
          [business, task, job, labor, payload['description'] as String, payload['planned'] as int? ?? 0],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_task_sources VALUES(?,?,?,?,?,?) '
          'ON CONFLICT(business_id,task_id) DO UPDATE SET active=excluded.active,invoice_id=excluded.invoice_id,line_id=excluded.line_id',
          [business, task, isRecheck ? null : invoice, isRecheck ? null : line,
            isRecheck ? payload['kind'] : 'invoice', payload['active'] as int? ?? 1],
        );
        await db.customStatement(
          'INSERT INTO regular_payroll_estimates VALUES(?,?,?,?) ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET minutes=excluded.minutes',
          [business, task, employee, payload['estimated_minutes'] as int? ?? 0],
        );
        final existing = await _read(
          'SELECT id FROM regular_payroll_portions WHERE business_id=? AND id=?',
          [business, id],
        );
        if (existing.isEmpty) {
          await db.customStatement(
            "INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES(?,?,?,?,'Open')",
            [business, id, task, employee],
          );
          await LocalMechanicWorkCreditRepository(database: db).createAssignment(
            businessId: business, allocationId: id, jobId: payload['credit_job'] as String? ?? job,
            laborLineId: labor, taskId: task, employeeId: employee,
            actualMinutes: 0, rateCents: rate,
          );
        }
        await _applyCanonicalProgress(id, employee, payload);
        final priorPaidAt=payload['prior_paid_at'];
        if(priorPaidAt!=null) {
          if(priorPaidAt is! String || DateTime.tryParse(priorPaidAt)==null || payload['state']!='Done') {
            throw StateError('Invalid historical settlement snapshot.');
          }
          await db.customStatement('INSERT INTO regular_payroll_owner_prior_paid_v1 VALUES(?,?,?,?) ON CONFLICT(business_id,allocation_id) DO NOTHING',[business,id,employee,priorPaidAt]);
        }
      case PayrollLanOperation.payment:
        if (owner || pairedEmployee != employee) {
          throw StateError('Payroll receipt is unavailable to this device.');
        }
        final operationId = payload['operation'] as String;
        final existing = await _read(
          'SELECT payload FROM regular_payroll_payments WHERE business_id=? AND operation_id=?',
          [business, operationId],
        );
        if (existing.isNotEmpty) {
          if (existing.single['payload'] != jsonEncode(payload)) {
            throw StateError('Conflicting payment receipt.');
          }
          return;
        }
        final ids = (payload['work'] as List).cast<String>();
        if (ids.toSet().length != ids.length) throw StateError('Duplicate receipt work.');
        final coverage = payload['coverage'];
        final entries = coverage is List
            ? coverage.map((row) => Map<String, dynamic>.from(row as Map)).toList()
            : [
                for (final id in ids) {'credit_id': id},
              ];
        if (entries.length != ids.length ||
            entries.any((row) => !ids.contains(row['credit_id'])) ||
            entries.map((row) => row['credit_id']).toSet().length != ids.length) {
          throw StateError('Receipt coverage does not match its work.');
        }
        final staged = <Map<String, dynamic>>[];
        for (final entry in entries) {
          final id = entry['credit_id'] as String;
          final canonical = entry['snapshot'];
          if (canonical is Map){await _applyCanonicalProgress(id, employee, Map<String,dynamic>.from(canonical));}
          final rows = await _read(
            'SELECT c.* FROM local_mechanic_work_credits_v1 c '
            'WHERE c.business_id=? AND c.allocation_id=? AND c.employee_id=?',
            [business, id, employee],
          );
          if (rows.length != 1 || rows.single['completed'] != 1 ||
              rows.single['paid_operation_id'] != null) {
            throw StateError('Receipt conflicts with local payroll work.');
          }
          final credit = rows.single;
          final paid = (await _read(
            'SELECT COALESCE(SUM(minutes),0) AS minutes,COALESCE(SUM(amount),0) AS amount '
            'FROM regular_payroll_work_coverage WHERE business_id=? AND credit_id=?',
            [business, id],
          )).single;
          final priorMinutes = paid['minutes'] as int;
          final minutes = entry['minutes'] ?? credit['actual_minutes'];
          final total = credit['actual_minutes'] as int;
          if (minutes is! int || minutes <= 0 || minutes + priorMinutes > total) {
            throw StateError('Receipt exceeds remaining work.');
          }
          final snapshot = entry['snapshot'] as Map<String, dynamic>?;
          final paymentRate = snapshot?['payment_rate_cents'] ?? credit['rate_cents'];
          if (paymentRate is! int || paymentRate < 0 || paymentRate > 10000000) {
            throw StateError('Invalid receipt labor rate.');
          }
          final amount = (((priorMinutes + minutes) * paymentRate + 30) ~/ 60) -
              ((priorMinutes * paymentRate + 30) ~/ 60);
          if (entry['amount'] != null && entry['amount'] != amount) {
            throw StateError('Receipt work amount conflicts with this ledger.');
          }
          staged.add({
            'credit_id': id, 'minutes': minutes, 'amount': amount,
            'full': priorMinutes + minutes == total,
            'snapshot': jsonEncode({
              ...credit, 'id': id, 'description': 'Paid labor',
              'actual_minutes': minutes, 'gross_cents': amount,
              ...?snapshot,
            }),
          });
        }
        if (payload['gross'] is! int || payload['repayment'] is! int || payload['net'] is! int ||
            (payload['gross'] as int) < 0 || (payload['repayment'] as int) < 0 ||
            payload['net'] != (payload['gross'] as int) - (payload['repayment'] as int)) {
          throw StateError('Invalid receipt totals.');
        }
        await db.customStatement(
          'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
          [business, operationId, employee, payload['week'], jsonEncode(payload),
            payload['gross'], payload['repayment'], payload['net'],
            payload['method'], payload['date']],
        );
        for (final entry in staged) {
          await db.customStatement(
            'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
            [business, entry['credit_id'], operationId, entry['minutes'], entry['amount'], entry['snapshot']],
          );
          if (entry['full'] == true) {
            await db.customStatement(
              'UPDATE local_mechanic_work_credits_v1 SET paid_operation_id=? '
              'WHERE business_id=? AND allocation_id=? AND employee_id=?',
              [operationId, business, entry['credit_id'], employee],
            );
          }
        }

    }
    assertLink();
  }

  /// A signed Owner snapshot carries credited and actual hours separately.
  /// Older snapshots never overwrite offline mechanic progress. Paid coverage
  /// freezes the work, including partial payments; conflicts remain pending.
  Future<void> _applyCanonicalProgress(String id,String employee,Map<String,dynamic> value) async {
    if(value['credit_revision']==null){return;} // Existing receipts remain valid.
    final revision=value['credit_revision'];
    final minutes=value['total_credit_minutes'];
    final actual=value['recorded_actual_minutes'];
    final state=value['state'];
    if(revision is! int || revision<0 || minutes is! int || minutes<0 || actual is! int || actual<0 ||
        !['Open','In Progress','Done'].contains(state)){throw StateError('Invalid Owner work snapshot.');}
    final rows=await _read('SELECT c.*,p.state,p.completed_date FROM local_mechanic_work_credits_v1 c '
      'JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id '
      'WHERE c.business_id=? AND c.allocation_id=? AND c.employee_id=?',[business,id,employee]);
    if(rows.length!=1){throw StateError('Payment pending: receive the labor assignment first.');}
    final row=rows.single;
    if(value['task_id']!=row['task_id'] || (value['job_id']??value['credit_job']??value['job'])!=row['job_id']){throw StateError('Owner work identity conflicts.');}
    final prior=row['revision'] as int;
    if(revision<prior){return;}
    final recorded=await _read('SELECT minutes FROM regular_payroll_actual_time WHERE business_id=? AND credit_id=?',[business,id]);
    final same=row['actual_minutes']==minutes && row['state']==state &&
      row['completed_date']==value['completed_date'] && (recorded.firstOrNull?['minutes']??row['actual_minutes'])==actual;
    if(revision==prior && !same){throw StateError('Payment pending: work revisions conflict. Reconcile before payment.');}
    if(same){
      if(revision>prior){
        await db.customStatement('UPDATE local_mechanic_work_credits_v1 SET revision=? WHERE business_id=? AND allocation_id=?',[revision,business,id]);
      }
      return;
    }
    final coverage=await _read('SELECT credit_id FROM regular_payroll_work_coverage WHERE business_id=? AND credit_id=?',[business,id]);
    if(coverage.isNotEmpty || row['paid_operation_id']!=null){throw StateError('Paid work history cannot be replaced.');}
    if(state=='Done' && value['prior_paid_at']==null){_date(value['completed_date'] as String);}
    await db.customStatement('UPDATE local_mechanic_work_credits_v1 SET actual_minutes=?,completed=?,revision=? WHERE business_id=? AND allocation_id=? AND employee_id=?',
      [minutes,state=='Done'?1:0,revision,business,id,employee]);
    await db.customStatement('UPDATE regular_payroll_portions SET state=?,completed_date=?,version=? WHERE business_id=? AND id=?',
      [state,value['completed_date'],revision,business,id]);
    await db.customStatement('INSERT INTO regular_payroll_actual_time VALUES(?,?,?,?) ON CONFLICT(business_id,credit_id) DO UPDATE SET minutes=excluded.minutes,revision=excluded.revision',
      [business,id,actual,revision]);
  }

  /// Editing or reopening an unpaid portion increments its version. Paid
  /// portions require a new recheck labor line; their original hours stay frozen.
  Future<void> updateWork(
    String id,
    String state,
    int hours,
    String date, {
    int? expectedRevision,
  }) {
    if (hours < 0) throw ArgumentError('Invalid work hours');
    return _updateWork(
      id, state, (hours * 60 + 50) ~/ 100, date,
      expectedRevision: expectedRevision,
      authorize: _authorize,
    );
  }

  Future<void> _updateWork(
    String id,
    String state,
    int minutes,
    String date, {
    required int? expectedRevision,
    required void Function() authorize,
    bool allowRetiredProgress=false,
  }) async {
    authorize();
    await prepare();
    _date(date);
    if (!['Open', 'In Progress', 'Done'].contains(state) || minutes < 0)
      { throw ArgumentError('Invalid work'); }
    await db.transaction(() async {
      final rows = await _read(
        'SELECT c.*,p.state FROM local_mechanic_work_credits_v1 c JOIN regular_payroll_portions p ON p.business_id=c.business_id AND p.id=c.allocation_id WHERE c.business_id=? AND c.allocation_id=?',
        [business, id],
      );
      final covered = await _read(
        'SELECT credit_id FROM regular_payroll_work_coverage WHERE business_id=? AND credit_id=?',
        [business,id]);
      if (covered.isNotEmpty) throw StateError('Paid work is immutable');
      final historical = await _read(
        "SELECT s.task_id FROM regular_payroll_task_sources s "
        "JOIN local_documents d ON d.business_id=s.business_id AND d.id=s.invoice_id "
        "WHERE s.business_id=? AND s.task_id=? AND s.source_kind='invoice' "
        "AND (date(d.document_date) IS NULL OR date(d.document_date)!=d.document_date OR d.document_date<?) "
        "AND NOT EXISTS(SELECT 1 FROM regular_payroll_audit a WHERE a.business_id=s.business_id "
        "AND a.operation_id=? AND a.event='owner_reviewed_unpaid_carry')",
        [business,rows.firstOrNull?['task_id']?.toString() ?? '',LocalInvoiceTaskStore.payrollCutover,id]);
      if (historical.isNotEmpty) {
        throw StateError('Historical labor requires separate Owner carry-forward before recording new work.');
      }
      final retired = await _read('SELECT active FROM regular_payroll_assignment_meta WHERE business_id=? AND task_id=? AND employee_id=?',
        [business, rows.firstOrNull?['task_id']?.toString() ?? '', rows.firstOrNull?['employee_id']?.toString() ?? '']);
      if (!allowRetiredProgress && retired.firstOrNull?['active'] == 0){throw StateError('This inherited assignment changed. Refresh tasks.');}
      final priorPaid = await _read(
        'SELECT allocation_id FROM regular_payroll_owner_prior_paid_v1 '
        'WHERE business_id=? AND allocation_id=?',
        [business,id],
      );
      if (rows.length != 1 || rows.single['paid_operation_id'] != null ||
          priorPaid.isNotEmpty)
        { throw StateError('Missing or paid work; add a recheck'); }
      if (rows.single['state'] == 'Open') {
        final removed = await _read(
          'SELECT task_id FROM regular_payroll_task_sources '
          'WHERE business_id=? AND task_id=? AND active=0',
          [business, rows.single['task_id'] as String],
        );
        if (removed.isNotEmpty) {
          throw StateError('This invoice labor was removed. Add a separate task for new work.');
        }
      }
      if (expectedRevision != null && rows.single['revision'] != expectedRevision) {
        throw StateError('Work changed. Refresh before updating it.');
      }
      if (state == 'Done' && rows.single['state'] == 'Open') {
        final estimate = await _read('SELECT minutes FROM regular_payroll_estimates WHERE business_id=? AND task_id=? AND employee_id=?',
          [business,rows.single['task_id'],rows.single['employee_id']]);
        if (minutes<=0 || estimate.firstOrNull?['minutes']!=minutes) {
          throw StateError('Mark Done requires the saved assigned hours.');
        }
      }
      await LocalMechanicWorkCreditRepository(database: db).recordWork(
        businessId: business, allocationId: id, employeeId: rows.single['employee_id'] as String,
        expectedRevision: rows.single['revision'] as int,
        actualMinutes: minutes, completed: state == 'Done',
      );
      await db.customStatement('INSERT INTO regular_payroll_actual_time(business_id,credit_id,minutes,revision) SELECT ?,?,?,revision FROM local_mechanic_work_credits_v1 WHERE business_id=? AND allocation_id=? '
        'ON CONFLICT(business_id,credit_id) DO UPDATE SET minutes=excluded.minutes,revision=excluded.revision',[business,id,minutes,business,id]);
      await db.customStatement(
        'UPDATE regular_payroll_portions SET state=?,version=version+1,completed_date=? WHERE business_id=? AND id=?',
        [state, state == 'Done' ? date : null, business, id],
      );
      authorize();
    });
  }

  Future<List<Map<String, dynamic>>> jobs() async {
    _authorize();
    await prepare();
    return _read(
      '''SELECT j.*,count(t.id) total, coalesce(sum(CASE WHEN EXISTS(SELECT 1 FROM regular_payroll_portions p WHERE p.business_id=t.business_id AND p.task_id=t.id) AND NOT EXISTS(SELECT 1 FROM regular_payroll_portions p WHERE p.business_id=t.business_id AND p.task_id=t.id AND p.state!='Done') THEN 1 ELSE 0 END),0) done,
    (SELECT count(*) FROM regular_payroll_portions p JOIN regular_payroll_tasks x ON x.business_id=p.business_id AND x.id=p.task_id WHERE x.business_id=j.business_id AND x.job_id=j.id AND p.state!='Open') started
    FROM regular_payroll_jobs j LEFT JOIN regular_payroll_tasks t ON t.business_id=j.business_id AND t.job_id=j.id WHERE j.business_id=? GROUP BY j.id ORDER BY j.id''',
      [business],
    );
  }

  Future<List<Map<String, dynamic>>> tasks() async {
    _authorize();
    await prepare();
    return _read(
      'SELECT t.*,j.job_number,j.customer_name,j.vehicle_label,j.created_at AS job_created_at,'
      '(SELECT MIN(document_date) FROM local_documents jd WHERE jd.business_id=t.business_id AND jd.job_id=t.job_id) AS job_document_date,'
      "d.document_number AS invoice_number,d.document_date AS invoice_date,d.created_at AS invoice_created_at,o.line_position,s.source_kind,CASE WHEN d.status IN ('void','voided','cancelled','canceled','deleted') THEN 0 ELSE s.active END AS source_active,"
      's.invoice_id,s.line_id AS source_line_id FROM regular_payroll_tasks t '
      'LEFT JOIN local_jobs j ON j.business_id=t.business_id AND j.id=t.job_id '
      'LEFT JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id '
      'LEFT JOIN local_documents d ON d.business_id=s.business_id AND d.id=s.invoice_id '
      'LEFT JOIN regular_payroll_task_order o ON o.business_id=t.business_id AND o.task_id=t.id '
      'WHERE t.business_id=? ORDER BY t.id', [business],
    );
  }

  Future<List<Map<String, dynamic>>> work({String? employee, String? job}) async {
    _authorize();
    await prepare();
    final rows = await _read(
      "SELECT p.business_id,p.id,p.task_id,p.employee_id,e.name AS employee_name,"
      "CASE WHEN h.allocation_id IS NULL THEN 0 ELSE 1 END AS owner_prior_paid,"
      "CASE WHEN s.source_kind='invoice' AND (date(d.document_date) IS NULL OR date(d.document_date)!=d.document_date OR d.document_date < '${LocalInvoiceTaskStore.payrollCutover}') AND NOT EXISTS "
      "(SELECT 1 FROM regular_payroll_audit a WHERE a.business_id=p.business_id AND a.operation_id=p.id "
      "AND a.event='owner_reviewed_unpaid_carry') THEN 1 ELSE 0 END AS archived_labor,"
      "COALESCE(cw.week,(SELECT json_extract(a.payload,'\$.week') FROM regular_payroll_audit a WHERE a.business_id=p.business_id AND a.operation_id=p.id AND a.event='owner_reviewed_unpaid_carry' ORDER BY a.id DESC LIMIT 1)) AS carry_week,cw.reason AS carry_reason,e.rate AS saved_rate,e.base_enabled,p.state,p.completed_date,c.revision AS version,t.description,t.job_id,"
      "j.job_number,j.customer_name,j.vehicle_label,j.created_at AS job_created_at,"
      "(SELECT MIN(document_date) FROM local_documents jd WHERE jd.business_id=t.business_id AND jd.job_id=t.job_id) AS job_document_date,"
      "d.document_number AS invoice_number,d.document_date AS invoice_date,d.created_at AS invoice_created_at,o.line_position,c.completed AS credit_completed,"
      "s.source_kind,CASE WHEN m.active=0 THEN 1 ELSE 0 END AS assignment_conflict,CASE WHEN m.active=0 OR d.status IN ('void','voided','cancelled','canceled','deleted') THEN 0 ELSE s.active END AS source_active,s.invoice_id,s.line_id AS source_line_id,"
      "COALESCE(est.minutes,0) AS estimated_minutes,"
      "c.actual_minutes,c.rate_cents,COALESCE(at.minutes,c.actual_minutes) AS recorded_actual_minutes,"
      "(SELECT x.snapshot FROM regular_payroll_work_coverage x WHERE x.business_id=c.business_id AND x.credit_id=c.allocation_id ORDER BY x.operation_id LIMIT 1) AS coverage_snapshot,"
      "COALESCE((SELECT SUM(x.minutes) FROM regular_payroll_work_coverage x "
      "WHERE x.business_id=c.business_id AND x.credit_id=c.allocation_id),"
      "CASE WHEN c.paid_operation_id IS NOT NULL THEN c.actual_minutes ELSE 0 END) AS paid_minutes,"
      "COALESCE((SELECT SUM(x.amount) FROM regular_payroll_work_coverage x "
      "WHERE x.business_id=c.business_id AND x.credit_id=c.allocation_id),"
      "CASE WHEN c.paid_operation_id IS NOT NULL THEN (c.actual_minutes*c.rate_cents+30)/60 ELSE 0 END) AS paid_cents "
      "FROM regular_payroll_portions p "
      "JOIN regular_payroll_tasks t ON t.business_id=p.business_id AND t.id=p.task_id "
      "JOIN local_mechanic_work_credits_v1 c ON c.business_id=p.business_id AND c.allocation_id=p.id "
      "JOIN regular_payroll_employees e ON e.business_id=p.business_id AND e.id=p.employee_id "
      "LEFT JOIN regular_payroll_assignment_meta m ON m.business_id=p.business_id AND m.task_id=p.task_id AND m.employee_id=p.employee_id "
      "LEFT JOIN regular_payroll_actual_time at ON at.business_id=p.business_id AND at.credit_id=p.id "
      "LEFT JOIN regular_payroll_owner_prior_paid_v1 h ON h.business_id=p.business_id AND h.allocation_id=p.id "
      "LEFT JOIN regular_payroll_carry_weeks_v1 cw ON cw.business_id=p.business_id AND cw.allocation_id=p.id "
      "LEFT JOIN local_jobs j ON j.business_id=t.business_id AND j.id=t.job_id "
      "LEFT JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id "
      "LEFT JOIN local_documents d ON d.business_id=s.business_id AND d.id=s.invoice_id "
      "LEFT JOIN regular_payroll_task_order o ON o.business_id=t.business_id AND o.task_id=t.id "
      "LEFT JOIN regular_payroll_estimates est ON est.business_id=p.business_id "
      "AND est.task_id=p.task_id AND est.employee_id=p.employee_id "
      "WHERE (COALESCE(m.active,1)=1 OR p.state<>'Open' OR c.actual_minutes>0 OR c.paid_operation_id IS NOT NULL) AND p.business_id=?  "
      "${job == null ? '' : 'AND t.job_id=?'} ORDER BY p.id",
      [business, ?job],
    );
    _authorize();
    final verifiedPaid=await VerifiedPaidLabor(db).allocations(business);
    final notes=await HistoricalTaskRecordkeeping(db).read(business);
    return rows.map((row) {
      final total = row['actual_minutes'] as int;
      final ownerPriorPaid = row['owner_prior_paid'] == 1;
      final paid = ownerPriorPaid ? total : row['paid_minutes'] as int;
      final rate = row['rate_cents'] as int;
      final coverage=row['coverage_snapshot'] is String ? jsonDecode(row['coverage_snapshot'] as String) as Map : null;
      final paymentRate=rate==0 ? (paid>0 ? (coverage?['payment_rate_cents'] as int? ?? 0) : (row['saved_rate'] as int? ?? 0)) : rate;
      if (paid < 0 || paid > total) throw StateError('Conflicting payroll coverage.');
      final remaining = total - paid;
      return {
        ...row,
        if(rate==0 && paymentRate>0) 'payment_rate_cents':paymentRate,
        if(verifiedPaid.contains(row['id']) || row['archived_labor']==1) 'state':'Done',
        if(row['archived_labor']==1 && notes[row['id']]!=null) ...{
          'employee_id':notes[row['id']]!['employee_id'],
          'employee_name':notes[row['id']]!['employee_name'],
          'estimated_minutes':notes[row['id']]!['minutes'],
          'recordkeeping_only':true,
        },
        'hours_hundredths': (total * 100 + 30) ~/ 60,
        'paid_minutes': paid,
        'paid_cents': ownerPriorPaid ? ((total * rate + 30) ~/ 60) : row['paid_cents'],
        'remaining_minutes': remaining,
        'remaining_cents': ((total * paymentRate + 30) ~/ 60) - ((paid * paymentRate + 30) ~/ 60),
        'gross_cents': (total * rate + 30) ~/ 60,
        'paid': total > 0 && remaining == 0 ? 1 : 0,
        'pay_status': ownerPriorPaid ? 'Already Paid' :
            paid == 0 ? 'Unpaid' : remaining == 0 ? 'Paid' : 'Partially Paid',
      };
    }).where((row)=>employee==null || row['employee_id']==employee).toList();
  }

  Future<void> enableWeeklyBase(String employee, String name) async {
    _authorize();
    if (employee.isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Employee identity is required.');
    }
    await prepare();
    await db.transaction(() async {
      await _assertPaymentAuthority();
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,0,1) '
        'ON CONFLICT(business_id,id) DO UPDATE SET base_enabled=1',
        [business, employee, name],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_advances VALUES(?,?,0)',
        [business, employee],
      );
      _authorize();
    });
  }

  Future<Map<String, dynamic>?> weeklyDefaults(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT base_cents,hourly_cents,adjustment_cents,add_labor '
      'FROM regular_payroll_weekly_defaults WHERE business_id=? AND employee_id=?',
      [business, employee],
    );
    _authorize();
    return rows.firstOrNull;
  }

  Future<void> saveWeeklyDefaults(
    String employee, int base, int hourly, int adjustment, bool addLabor,
  ) async {
    _authorize();
    if (employee.isEmpty || base < 0 || hourly < 0) {
      throw ArgumentError('Enter valid weekly amounts.');
    }
    await prepare();
    await db.transaction(() async {
      _authorize();
      await db.customStatement(
        'INSERT INTO regular_payroll_weekly_defaults VALUES(?,?,?,?,?,?) '
        'ON CONFLICT(business_id,employee_id) DO UPDATE SET '
        'base_cents=excluded.base_cents,hourly_cents=excluded.hourly_cents,'
        'adjustment_cents=excluded.adjustment_cents,add_labor=excluded.add_labor',
        [business, employee, base, hourly, adjustment, addLabor ? 1 : 0],
      );
      _authorize();
    });
  }

  Future<List<Map<String, dynamic>>> shopTasks([String? employee]) async {
    _authorize();
    await prepare();
    final rows = await _read(
      'SELECT t.*, j.job_id FROM regular_payroll_shop_tasks t LEFT JOIN regular_payroll_shop_task_jobs j ON j.business_id=t.business_id AND j.task_id=t.id '
      'WHERE t.business_id=? ${employee == null ? '' : 'AND employee_id=?'} ORDER BY t.id DESC',
      [business, ?employee],
    );
    _authorize();
    final historical=await HistoricalGeneralTasks(db).completed(business);
    return rows.map((r)=><String,dynamic>{...r,if(historical.contains(r['id'])) 'status':'done'}).toList();
  }

  Future<void> addShopTask(
    String employee, String description, String category, {DateTime? due, String? job}
  ) async {
    _authorize();
    if (employee.isEmpty || description.trim().isEmpty) {
      throw ArgumentError('Employee and task description are required.');
    }
    await prepare();
    await HistoricalGeneralTasks(db).completed(business);
    await db.transaction(() async {
      _authorize();
      await db.customStatement(
        'INSERT INTO regular_payroll_shop_tasks (business_id,employee_id,description,category,due_at) '
        'VALUES (?,?,?,?,?)', [business, employee, description.trim(), category, due?.millisecondsSinceEpoch],
      );
      if (job != null) {
        await db.customStatement(
          'INSERT INTO regular_payroll_shop_task_jobs VALUES(?,last_insert_rowid(),?)',
          [business, job],
        );
      }
      _authorize();
    });
  }

  Future<void> setShopTaskStatus(String employee, int id, String status) async {
    _authorize();
    if (!['planned', 'in_progress', 'done'].contains(status)) {
      throw ArgumentError('Unknown task status.');
    }
    await prepare();
    await db.transaction(() async {
      _authorize();
      await HistoricalGeneralTasks(db).completed(business);
      await db.customStatement('DELETE FROM historical_general_tasks_v1 WHERE business_id=? AND task_id=?',[business,id]);
      await db.customStatement(
        'UPDATE regular_payroll_shop_tasks SET status=? WHERE business_id=? AND employee_id=? AND id=?',
        [status, business, employee, id],
      );
      _authorize();
    });
  }

  /// Edit an existing general task without changing its identity,
  /// Job link, status, payroll coverage or payment history.
  Future<void> editShopTask({
    required int id,
    required String previousEmployee,
    required String employee,
    required String description,
    required String category,
  }) async {
    _authorize();
    if (id <= 0 || previousEmployee.trim().isEmpty ||
        employee.trim().isEmpty || description.trim().isEmpty ||
        category.trim().isEmpty) {
      throw ArgumentError('Valid task, assigned mechanic and description required.');
    }
    await prepare();
    await db.transaction(() async {
      _authorize();
      final original = await _read(
        'SELECT id FROM regular_payroll_shop_tasks '
        'WHERE business_id=? AND id=? AND employee_id=?',
        [business, id, previousEmployee],
      );
      if (original.length != 1) throw StateError('Task assignment changed. Refresh.');
      await db.customStatement(
        'UPDATE regular_payroll_shop_tasks '
        'SET employee_id=?, description=?, category=? '
        'WHERE business_id=? AND id=? AND employee_id=?',
        [employee, description.trim(), category.trim(),
          business, id, previousEmployee],
      );
      _authorize();
    });
  }

  Future<int> advance(String employee) async {
    _authorize();
    await prepare();
    final r = await _read(
      'SELECT balance FROM regular_payroll_advances WHERE business_id=? AND employee_id=?',
      [business, employee],
    );
    return r.firstOrNull?['balance'] as int? ?? 0;
  }

  Future<void> addAdvance(String employee, int amount) async {
    _authorize();
    await prepare();
    if (amount <= 0) { throw ArgumentError('Positive advance required'); }
    await db.transaction(() async {
      await _assertPaymentAuthority();
      if ((await _read(
        'SELECT id FROM regular_payroll_employees WHERE business_id=? AND id=?',
        [business, employee],
      )).isEmpty)
        { throw StateError('Employee missing'); }
      await db.customStatement(
        'UPDATE regular_payroll_advances SET balance=balance+? WHERE business_id=? AND employee_id=?',
        [amount, business, employee],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [
          business,
          'advance-${DateTime.now().microsecondsSinceEpoch}',
          'advance',
          jsonEncode({'employee': employee, 'amount': amount}),
        ],
      );
      await _assertPaymentAuthority();
    });
  }

  Future<void> recordOpeningAdvance(String employee, int cents) async {
    _authorize();
    if (cents <= 0) throw ArgumentError('Enter a positive opening amount.');
    await prepare();
    await db.transaction(() async {
      await _assertPaymentAuthority();
      if (await advance(employee) != 0 ||
          (await history(employee)).isNotEmpty ||
          (await repaymentHistory(employee)).isNotEmpty) {
        throw StateError('An opening amount cannot replace existing payroll history.');
      }
      await db.customStatement(
        'INSERT INTO regular_payroll_advances VALUES(?,?,?) '
        'ON CONFLICT(business_id,employee_id) DO UPDATE SET balance=excluded.balance',
        [business, employee, cents],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) "
        "VALUES(?,?,'opening_advance',?)",
        [business, 'opening-advance-$employee',
          jsonEncode({'employee': employee, 'cents': cents})],
      );
      _authorize();
      await _assertPaymentAuthority();
    });
  }

  Future<int?> openingAdvance(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      "SELECT payload FROM regular_payroll_audit WHERE business_id=? "
      "AND event='opening_advance' AND operation_id=?",
      [business, 'opening-advance-$employee'],
    );
    _authorize();
    final row = rows.firstOrNull;
    return row == null ? null :
        (jsonDecode(row['payload'] as String) as Map)['cents'] as int;
  }

  Future<void> recordRepayment({
    required String employee,
    required String operation,
    required int amount,
    required String date,
    required String method,
    required String note,
  }) async {
    _authorize();
    _date(date);
    if (operation.isEmpty || amount <= 0 ||
        !['Cash', 'Zelle', 'Check', 'ACH'].contains(method)) {
      throw ArgumentError('Enter a positive repayment and a valid payment method.');
    }
    await prepare();
    await db.transaction(() async {
      await _assertPaymentAuthority();
      final prior = await _read(
        "SELECT payload FROM regular_payroll_audit WHERE business_id=? "
        "AND operation_id=? AND event='standalone_repayment'",
        [business, operation],
      );
      final fields = {
        'employee': employee, 'cents': amount, 'date': date,
        'method': method, 'note': note,
      };
      if (prior.isNotEmpty) {
        final recorded = jsonDecode(prior.single['payload'] as String) as Map;
        if (fields.entries.any((entry) => recorded[entry.key] != entry.value)) {
          throw StateError('Conflicting repayment retry.');
        }
        return;
      }
      final balance = await advance(employee);
      if (amount > balance) throw StateError('Repayment exceeds the balance.');
      final remaining = balance - amount;
      await db.customStatement(
        'UPDATE regular_payroll_advances SET balance=? WHERE business_id=? AND employee_id=?',
        [remaining, business, employee],
      );
      await db.customStatement(
        "INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) "
        "VALUES(?,?,'standalone_repayment',?)",
        [business, operation, jsonEncode({...fields, 'remaining_after_cents': remaining})],
      );
      _authorize();
      await _assertPaymentAuthority();
    });
  }

  Future<List<Map<String, dynamic>>> repaymentHistory(String employee) async {
    _authorize();
    await prepare();
    final rows = await _read(
      "SELECT payload FROM regular_payroll_audit WHERE business_id=? "
      "AND event='standalone_repayment' AND json_extract(payload,'\$.employee')=? ORDER BY id DESC",
      [business, employee],
    );
    _authorize();
    return [
      for (final row in rows)
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> history(String employee) async {
    _authorize();
    await prepare();
    return _read(
      'SELECT p.*, o.state AS reconciliation_state FROM regular_payroll_payments p '
      'LEFT JOIN regular_payroll_sync_outbox o ON o.business_id=p.business_id '
      'AND o.operation_id=p.operation_id WHERE p.business_id=? AND p.employee_id=? '
      'ORDER BY p.verified_date DESC,p.operation_id DESC',
      [business, employee],
    );
  }

  /// Read the settlement and its frozen allocations together. Grouping by
  /// payment date would mix disbursements from different payroll weeks.
  Future<List<Map<String, dynamic>>> historyWithWork(String employee) async {
    _authorize();
    await prepare();
    return db.transaction(() async {
      final payments = await history(employee);
      final result = <Map<String, dynamic>>[];
      for (final payment in payments) {
        final rows = await _read(
          'SELECT credit_id, snapshot FROM regular_payroll_work_coverage '
          'WHERE business_id=? AND operation_id=? ORDER BY credit_id',
          [business, payment['operation_id'] as String],
        );
        final work = <Map<String, dynamic>>[];
        for (final row in rows) {
          final snapshot = Map<String, dynamic>.from(
            jsonDecode(row['snapshot'] as String) as Map,
          );
          final taskId = snapshot['task_id'];
          // Older snapshots may predate the encoded invoice linkage.
          Object? task;
          if (taskId is String) {
            try {
              task = jsonDecode(taskId);
            } on FormatException {
              task = null;
            }
          }
          final source = taskId is String ? (await _read(
            'SELECT t.job_id,s.invoice_id,s.source_kind FROM regular_payroll_tasks t '
            'LEFT JOIN regular_payroll_task_sources s ON s.business_id=t.business_id AND s.task_id=t.id '
            'WHERE t.business_id=? AND t.id=?', [business, taskId],
          )).firstOrNull : null;
          final jobId = source?['job_id'] ?? snapshot['job_id'];
          final job = jobId is String ? (await _read(
            'SELECT id, job_number, vehicle_label FROM local_jobs '
            'WHERE business_id=? AND id=?', [business, jobId],
          )).firstOrNull : null;
          final invoiceIdentity = source?['invoice_id'] ??
              (task is List && task.length == 3 ? task[1] : null);
          final invoice = (source?['source_kind'] ?? snapshot['source_kind']) != 'recheck' && invoiceIdentity is String &&
              jobId is String && (source != null ||
                (task is List && task.length == 3 && task[0] == jobId))
              ? (await _read(
                  "SELECT id AS invoice_id, document_number FROM local_documents "
                  "WHERE business_id=? AND id=? AND job_id=? AND kind='invoice'",
                  [business, invoiceIdentity, jobId],
                )).firstOrNull
              : null;
          work.add({
            ...snapshot,
            'job_id': job?['id'],
            'job_number': job?['job_number'],
            'vehicle_label': job?['vehicle_label'],
            ...?invoice,
            'credit_id': row['credit_id'],
            'operation_id': payment['operation_id'],
            'method': payment['method'],
            'verified_date': payment['verified_date'],
          });
        }
        result.add({...payment, 'work': work});
      }
      _authorize();
      return result;
    });
  }

  Future<List<Map<String, dynamic>>> recordedCoverage(String employee, String operation) async {
    _authorize();
    await prepare();
    if ((await _read(
      'SELECT operation_id FROM regular_payroll_payments '
      'WHERE business_id=? AND operation_id=? AND employee_id=?',
      [business, operation, employee],
    )).length != 1) {
      throw StateError('Payment receipt is missing.');
    }
    final rows = await _read(
      'SELECT credit_id,minutes,amount,snapshot FROM regular_payroll_work_coverage '
      'WHERE business_id=? AND operation_id=? ORDER BY credit_id',
      [business, operation],
    );
    _authorize();
    return [
      for (final row in rows) {
        ...row,
        'snapshot': Map<String, dynamic>.from(jsonDecode(row['snapshot'] as String) as Map),
      },
    ];
  }

  /// Install a verified, non-transferable payment authority. This is for
  /// trusted LAN enrollment, never self-election by a disconnected device.
  Future<void> bindPaymentAuthority({
    required String writerDeviceId,
    required void Function() assertVerifiedPairing,
  }) async {
    _authorize();
    assertVerifiedPairing();
    if (writerDeviceId.trim().isEmpty) {
      throw ArgumentError('A verified payroll device is required.');
    }
    await prepare();
    await db.transaction(() async {
      assertVerifiedPairing();
      await db.customStatement(
        'INSERT OR IGNORE INTO regular_payroll_payment_authority VALUES(?,?)',
        [business, writerDeviceId],
      );
      final saved = await _read(
        'SELECT device_id FROM regular_payroll_payment_authority WHERE business_id=?',
        [business],
      );
      if (saved.single['device_id'] != writerDeviceId) {
        throw StateError('Conflicting payroll authority. Payments are not transferable.');
      }
      _authorize();
    });
  }

  Future<void> _assertPaymentAuthority() async {
    if (ownerProof != null) {
      await ownerProof!.validate(business, deviceId);
      return;
    }
    final upgraded = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='payroll_owner_proof_required_v2'",
    ).get();
    if (upgraded.isNotEmpty && (await _read(
      'SELECT business_id FROM payroll_owner_proof_required_v2 WHERE business_id=?', [business],
    )).isNotEmpty) {
      throw const PayrollPending('Payment pending: key-backed Owner payroll state must be reconciled.');
    }
    await assertLanWriter?.call();
    final saved = await _read(
      'SELECT device_id FROM regular_payroll_payment_authority WHERE business_id=?',
      [business],
    );
    if (deviceId == null || saved.length != 1 ||
        saved.single['device_id'] != deviceId) {
      throw StateError('Only the enrolled payroll device can record payments.');
    }
  }

  /// Sends immutable receipts by their original operation IDs. A failed or
  /// interrupted delivery remains pending, including after an app restart.
  Future<int> reconcile({
    required Future<Map<String, dynamic>> Function(
      String operation, Map<String, dynamic> payload,
    ) send,
  }) async {
    _authorize();
    await prepare();
    final pending = await _read(
      "SELECT operation_id,payload FROM regular_payroll_sync_outbox "
      "WHERE business_id=? AND state='held_local' ORDER BY operation_id",
      [business],
    );
    var acknowledged = 0;
    for (final row in pending) {
      _authorize();
      final operation = row['operation_id'] as String;
      final payload = row['payload'] as String;
      final reply = await send(
        operation,
        Map<String, dynamic>.from(jsonDecode(payload) as Map),
      );
      if (reply['operation_id'] != operation || reply['status'] != 'recorded') {
        throw StateError('Payroll reconciliation returned an invalid receipt.');
      }
      await db.transaction(() async {
        _authorize();
        await db.customStatement(
          "UPDATE regular_payroll_sync_outbox SET state='reconciled' "
          "WHERE business_id=? AND operation_id=? AND payload=? AND state='held_local'",
          [business, operation, payload],
        );
        _authorize();
      });
      acknowledged++;
    }
    return acknowledged;
  }

  void _date(String value) {
    final d = DateTime.tryParse(value);
    if (d == null || d.toIso8601String().substring(0, 10) != value)
      { throw ArgumentError('Use YYYY-MM-DD'); }
  }

  /// The selected versions, hours and rates are part of the exact replay
  /// payload. Same-ID/same-content retries return false; any conflict fails.
  Future<bool> verify({
    required String operation,
    required String employee,
    required String week,
    required String date,
    required String method,
    required List<Map<String, dynamic>> selected,
    required int base,
    required int hourlyAdjustment,
    required String adjustmentReason,
    required int repayment,
    required int confirmedNet,
    Future<void> Function()? beforeCommit,
  }) async {
    _authorize();
    await prepare();
    _date(week);
    _date(date);
    if (DateTime.parse(week).weekday != DateTime.monday ||
        operation.isEmpty ||
        !['Cash', 'Zelle', 'Check', 'ACH', 'Card', 'Other'].contains(method) ||
        base < 0 ||
        repayment < 0 ||
        confirmedNet < 0 ||
        (selected.isEmpty && base == 0) ||
        (hourlyAdjustment != 0 && adjustmentReason.trim().isEmpty))
      { throw ArgumentError('Invalid verification'); }
    final picked =
        selected
            .map(
              (w) => <String, dynamic>{
                'id': w['id'],
                'version': w['version'],
                'hours': w['hours_hundredths'],
                'minutes': w['actual_minutes'],
                'rate': w['rate_cents'],
                if (w.containsKey('pay_minutes')) 'pay_minutes': w['pay_minutes'],
                if (w.containsKey('paid_minutes')) 'paid_minutes': w['paid_minutes'],
                if (w.containsKey('payment_rate_cents')) 'payment_rate_cents': w['payment_rate_cents'],
              },
            )
            .toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    if (picked.map((p) => p['id']).toSet().length != picked.length)
      { throw StateError('Duplicate credit'); }
    final payload = jsonEncode({
      'employee': employee,
      'week': week,
      'date': date,
      'method': method,
      'work': picked,
      'base': base,
      'adjustment': hourlyAdjustment,
      'reason': adjustmentReason,
      'repayment': repayment,
      'confirmed_net': confirmedNet,
    });
    return db.transaction(() async {
      await _assertPaymentAuthority();
      final prior = await _read(
        'SELECT payload FROM regular_payroll_payments WHERE business_id=? AND operation_id=?',
        [business, operation],
      );
      if (prior.isNotEmpty) {
        if (prior.single['payload'] != payload)
          { throw StateError('Conflicting replay'); }
        return false;
      }
      final weeklyPayments = await _read(
        'SELECT operation_id FROM regular_payroll_payments '
        'WHERE business_id=? AND employee_id=? AND week=?',
        [business, employee, week],
      );
      final recordedBase = await _read(
        'SELECT operation_id FROM regular_payroll_paid_base '
        'WHERE business_id=? AND employee_id=? AND week=?',
        [business, employee, week],
      );
      if (base > 0 && (recordedBase.isNotEmpty || weeklyPayments.isNotEmpty)) {
        throw StateError('This employee already has a settlement for that week.');
      }
      final staff = await _read(
        'SELECT * FROM regular_payroll_employees WHERE business_id=? AND id=?',
        [business, employee],
      );
      if (staff.length != 1 || (base > 0 && staff.single['base_enabled'] != 1))
        { throw StateError('Base not allowed for employee'); }
      final current = (await work(employee: employee)).where((r)=>r['archived_labor']!=1).toList();
      if (base > 0 && selected.isEmpty) {
        final nextWeek = DateTime.parse(week).add(const Duration(days: 7));
        final unpaidWork = current.any((row) {
          final date = DateTime.tryParse(row['completed_date']?.toString() ?? '');
          return row['paid'] != 1 && (date == null || date.isBefore(nextWeek));
        });
        if (unpaidWork) {
          throw StateError('Link this employee’s outstanding labor credits before recording weekly pay.');
        }
      }
      var gross = base + hourlyAdjustment;
      final snapshots = <String>[];
      for (final p in picked) {
        final match = current.where((w) => w['id'] == p['id']).toList();
        if (match.length != 1) { throw StateError('Missing work'); }
        final w = match.single;
        if (w['assignment_conflict']==1 || w['state'] != 'Done' ||
            w['credit_completed'] != 1 ||
            w['paid'] != 0 ||
            (p.containsKey('paid_minutes') && w['paid_minutes'] != p['paid_minutes']) ||
            w['version'] != p['version'] ||
            w['hours_hundredths'] != p['hours'] ||
            w['actual_minutes'] != p['minutes'] ||
            w['rate_cents'] != p['rate'])
          { throw StateError('Work changed or already paid'); }
        if(w['carry_week']!=null && week.compareTo(w['carry_week'] as String)<0) throw StateError('This carry-forward starts in its authorized payroll week.');
        final completed = DateTime.parse(w['completed_date'] as String);
        final start = DateTime.parse(week);
        if ((completed.isBefore(start) ||
                !completed.isBefore(start.add(const Duration(days: 7)))) &&
            adjustmentReason.trim().isEmpty)
          { throw StateError(
            'Outside-week work requires an Owner override reason',
          ); }
        final remaining = w['remaining_minutes'] as int;
        final minutes = p['pay_minutes'] ?? remaining;
        if (minutes is! int || minutes <= 0 || minutes > remaining) {
          throw StateError('Select positive unpaid minutes for each work credit.');
        }
        final previouslyPaid = w['paid_minutes'] as int;
        // Cumulative rounding ensures several partial payments equal one
        // full payment, including credits with fractional cents per minute.
        final paymentRate = p['payment_rate_cents'] ?? p['rate'];
        if (paymentRate is! int || paymentRate < 0 || paymentRate > 10000000 ||
            (paymentRate != p['rate'] && adjustmentReason.trim().isEmpty)) {
          throw StateError('An adjusted labor rate requires an Owner reason.');
        }
        if(paymentRate==0 && base==0)throw StateError('Configure an hourly rate or approve weekly base before paying this work.');
        final amount = (((previouslyPaid + minutes) * paymentRate + 30) ~/ 60) -
            ((previouslyPaid * paymentRate + 30) ~/ 60);
        gross += amount;
        snapshots.add(jsonEncode({
          ...w, 'employee_name': staff.single['name'],
          'total_credit_minutes':w['actual_minutes'],'credit_revision':w['version'],
          'actual_minutes': minutes, 'hours_hundredths': (minutes * 100 + 30) ~/ 60,
          'gross_cents': amount, 'payment_rate_cents': paymentRate,
        }));
      }
      if (gross < 0 ||
          repayment > gross ||
          repayment > await advance(employee) ||
          confirmedNet != gross - repayment)
        { throw StateError('Amount or repayment changed'); }
      if (base > 0)
        { await db.customStatement('INSERT INTO regular_payroll_paid_base VALUES(?,?,?,?,?)', [
          business,
          employee,
          week,
          operation,
          base,
        ]); }
      await db.customStatement(
        'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          business,
          operation,
          employee,
          week,
          payload,
          gross,
          repayment,
          gross - repayment,
          method,
          date,
        ],
      );
      for (var i = 0; i < picked.length; i++) {
        final snapshot = jsonDecode(snapshots[i]) as Map<String, dynamic>;
        await db.customStatement(
          'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
          [business, picked[i]['id'], operation, snapshot['actual_minutes'],
            snapshot['gross_cents'], snapshots[i]],
        );
        final total = await _read(
          'SELECT SUM(minutes) AS minutes FROM regular_payroll_work_coverage '
          'WHERE business_id=? AND credit_id=?',
          [business, picked[i]['id'] as String],
        );
        if (total.single['minutes'] == picked[i]['minutes']) {
          await db.customStatement(
            'UPDATE local_mechanic_work_credits_v1 SET paid_operation_id=? '
            'WHERE business_id=? AND allocation_id=?',
            [operation, business, picked[i]['id']],
          );
        }
      }
      await db.customStatement(
        'UPDATE regular_payroll_advances SET balance=balance-? WHERE business_id=? AND employee_id=?',
        [repayment, business, employee],
      );
      await db.customStatement(
        'INSERT INTO regular_payroll_audit(business_id,operation_id,event,payload) VALUES(?,?,?,?)',
        [business, operation, 'verify_payment', payload],
      );
      // Keep payroll reconciliation separate from ordinary shop sync.
      await db.customStatement(
        'INSERT INTO regular_payroll_sync_outbox(business_id,operation_id,payload) VALUES(?,?,?)',
        [business, operation, payload],
      );
      if (beforeCommit != null) { await beforeCommit(); }
      await _assertPaymentAuthority();
      _authorize();
      return true;
    });
  }
}
