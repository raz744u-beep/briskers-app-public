// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:drift/drift.dart' show Variable;
import '../local/local_database_provider.dart';
import '../services/local_job_tasks_lab_store.dart';
import 'employee_advance_ledger.dart';
import 'payroll_period_projection.dart';

/// A single device-local, synthetic TEST transaction. The bank is not called.
class LabPayrollPaymentResult {
  const LabPayrollPaymentResult({
    required this.grossCents, required this.debtCents,
    required this.netCents, required this.hours,
  });
  final int grossCents;
  final int debtCents;
  final int netCents;
  final double hours;
}

class LabPayrollPaymentService {
  static const _shop='briskers-tasks-test-only';
  static Future<void> ensure() async {
    await LocalJobTasksLabStore.ensureTables(localDatabase);
    await localDatabase.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_payroll_task_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        document_id TEXT NOT NULL, line_id TEXT NOT NULL,
        week_key TEXT NOT NULL, description TEXT NOT NULL,
        hours REAL NOT NULL, cents INTEGER NOT NULL,
        method TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
        paid_at INTEGER NOT NULL
      )
    ''');
    await localDatabase.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_payroll_settlements (
        disbursement_id INTEGER PRIMARY KEY,
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        week_key TEXT NOT NULL,
        gross_cents INTEGER NOT NULL, labor_cents INTEGER NOT NULL,
        debt_cents INTEGER NOT NULL, net_cents INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// Store one confirmed weekly-base/supplement payment on this device.
  /// It deliberately does not mark any mechanic-task allocation as paid.
  /// A unique employee/week key prevents accidental second finalization.
  static Future<LabPayrollPaymentResult> recordFlexibleWeekly({
    required String employeeId,
    required DateTime week,
    required int grossCents,
    required int debtCents,
    required String method,
    required String note,
  }) async {
    if (employeeId.trim().isEmpty || grossCents <= 0 ||
        grossCents > 100000000 || debtCents < 0 ||
        debtCents > grossCents ||
        !const {'zelle', 'cash', 'check', 'ach'}.contains(method)) {
      throw ArgumentError('Invalid flexible TEST payment');
    }
    await ensure();
    final advance = await LabAdvanceLedger(localDatabase)
      .read(_shop, employeeId);
    if (debtCents > advance.remainingCents) {
      throw StateError('Repayment exceeds remaining advance');
    }
    await localDatabase.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_flexible_weekly_confirmations (
        business_id TEXT NOT NULL,
        employee_id TEXT NOT NULL,
        week_key TEXT NOT NULL,
        disbursement_id INTEGER NOT NULL,
        PRIMARY KEY (business_id, employee_id, week_key)
      )
    ''');
    final weekKey = LabPayrollPeriodProjection.weekKey(week);
    final now = DateTime.now().millisecondsSinceEpoch;
    await localDatabase.transaction(() async {
      final previous = await localDatabase.customSelect(
        'SELECT disbursement_id FROM lab_flexible_weekly_confirmations '
        'WHERE business_id=? AND employee_id=? AND week_key=?',
        variables: [const Variable<String>(_shop),
          Variable<String>(employeeId), Variable<String>(weekKey)],
      ).getSingleOrNull();
      if (previous != null) {
        throw StateError('Weekly payment already finalized for this week');
      }
      // The legacy hourly settlement flow can also pay the same week.
      // Never let a flexible payment silently settle it a second time.
      final existing = await localDatabase.customSelect(
        'SELECT disbursement_id FROM lab_payroll_settlements '
        'WHERE business_id=? AND employee_id=? AND week_key=? LIMIT 1',
        variables: [const Variable<String>(_shop),
          Variable<String>(employeeId), Variable<String>(weekKey)],
      ).getSingleOrNull();
      if (existing != null) {
        throw StateError('This payroll week already has a settlement');
      }
      final opening = await localDatabase.customSelect(
        'SELECT opening_cents FROM lab_employee_advance_balances '
        'WHERE business_id=? AND employee_id=?',
        variables: [const Variable<String>(_shop),
          Variable<String>(employeeId)],
      ).getSingleOrNull();
      final repayments = await localDatabase.customSelect(
        'SELECT COALESCE(SUM(cents),0) AS repaid '
        'FROM lab_employee_advance_repayments '
        'WHERE business_id=? AND employee_id=?',
        variables: [const Variable<String>(_shop),
          Variable<String>(employeeId)],
      ).getSingle();
      final remaining = (opening?.read<int>('opening_cents') ?? 0) -
        repayments.read<int>('repaid');
      if (debtCents > remaining) {
        throw StateError('Employee debt changed; reconfirm repayment');
      }
      await localDatabase.customStatement(
        'INSERT INTO local_lab_payroll_disbursements '
        '(business_id,employee_id,cents,kind,method,note,paid_at,created_at) '
        'VALUES (?,?,?,?,?,?,?,?)',
        // Disbursement is money actually transferred; gross belongs in
        // the settlement, and the deduction in the advance ledger.
        [_shop, employeeId, grossCents - debtCents, 'pay', method,
          note.trim(), now, now],
      );
      final idRow = await localDatabase.customSelect(
        'SELECT last_insert_rowid() AS disbursement_id').getSingle();
      final id = idRow.read<int>('disbursement_id');
      if (debtCents > 0) {
        await localDatabase.customStatement(
          'INSERT INTO lab_employee_advance_repayments '
          '(business_id,employee_id,cents,method,note,paid_at,'
          'remaining_after_cents,created_at) VALUES (?,?,?,?,?,?,?,?)',
          [_shop,employeeId,debtCents,'Payroll deduction',note.trim(),
            now,remaining-debtCents,now],
        );
      }
      await localDatabase.customStatement(
        'INSERT INTO lab_payroll_settlements '
        '(disbursement_id,business_id,employee_id,week_key,gross_cents,'
        'labor_cents,debt_cents,net_cents,created_at) '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        [id,_shop,employeeId,weekKey,grossCents,0,
          debtCents,grossCents-debtCents,now],
      );
      await localDatabase.customStatement(
        'INSERT INTO lab_flexible_weekly_confirmations '
        '(business_id,employee_id,week_key,disbursement_id) '
        'VALUES (?,?,?,?)',
        [_shop,employeeId,weekKey,id],
      );
    });
    return LabPayrollPaymentResult(
      grossCents:grossCents,debtCents:debtCents,
      netCents:grossCents-debtCents,hours:0);
  }

  static Future<LabPayrollPaymentResult> record({
    required String employeeId,
    required DateTime week,
    required List<Map<String,dynamic>> tasks,
    required Map<String,double> hoursByTask,
    required double Function(Map<String,dynamic>) assignedHours,
    required int hourlyRateCents,
    required int grossCents,
    required int debtCents,
    required String method,
    required String note,
  }) async {
    if(hourlyRateCents<=0||grossCents<=0||grossCents>100000000||
       debtCents<0||debtCents>grossCents||
       !const {'zelle','cash','check','ach'}.contains(method)) {
      throw ArgumentError('Invalid TEST payment');
    }
    await ensure();
    // Initialize advance ledger schema outside the transaction.
    final advance=await LabAdvanceLedger(localDatabase)
      .read(_shop,employeeId);
    if(debtCents>advance.remainingCents) {
      throw StateError('Debt repayment exceeds amount currently owed');
    }
    final selected=tasks.where((task){
      final key=task['document_id'].toString()+':'+task['line_id'].toString();
      return (hoursByTask[key]??0)>0;
    }).toList();
    final hours=selected.fold<double>(0,(sum,task){
      final key=task['document_id'].toString()+':'+task['line_id'].toString();
      return sum+(hoursByTask[key]??0);
    });
    if(hours<=0||selected.isEmpty) {
      throw ArgumentError('No labor hours selected');
    }
    final laborCents=(hours*hourlyRateCents).round();
    final now=DateTime.now().millisecondsSinceEpoch;
    final weekKey=LabPayrollPeriodProjection.weekKey(week);
    await localDatabase.transaction(() async {
      final rows=await localDatabase.customSelect(
        'SELECT document_id,line_id,SUM(hours) AS paid_hours '
        'FROM lab_payroll_task_payments WHERE business_id=? '
        'AND employee_id=? GROUP BY document_id,line_id',
        variables:[const Variable<String>(_shop),
          Variable<String>(employeeId)],
      ).get();
      final previously=<String,double>{};
      for(final row in rows) {
        previously[row.read<String>('document_id')+':' +
          row.read<String>('line_id')]=row.read<double>('paid_hours');
      }
      for(final task in selected) {
        final id=task['document_id'].toString()+':'+task['line_id'].toString();
        if((hoursByTask[id]??0)>assignedHours(task)-(previously[id]??0)+0.00001) {
          throw StateError('Task paid hours changed; recheck before paying');
        }
      }
      final opening=await localDatabase.customSelect(
        'SELECT opening_cents FROM lab_employee_advance_balances '
        'WHERE business_id=? AND employee_id=?',
        variables:[const Variable<String>(_shop),Variable<String>(employeeId)],
      ).getSingleOrNull();
      final repayments=await localDatabase.customSelect(
        'SELECT COALESCE(SUM(cents),0) AS repaid '
        'FROM lab_employee_advance_repayments '
        'WHERE business_id=? AND employee_id=?',
        variables:[const Variable<String>(_shop),Variable<String>(employeeId)],
      ).getSingle();
      final debtRemaining=(opening?.read<int>('opening_cents')??0)-
        repayments.read<int>('repaid');
      if(debtCents>debtRemaining) {
        throw StateError('Employee debt changed; confirm the amount again');
      }
      await localDatabase.customStatement(
        'INSERT INTO local_lab_payroll_disbursements '
        '(business_id,employee_id,cents,kind,method,note,paid_at,created_at) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [_shop,employeeId,grossCents,'pay',method,note.trim(),now,now],
      );
      final idRow=await localDatabase.customSelect(
        'SELECT last_insert_rowid() AS disbursement_id').getSingle();
      final disbursementId=idRow.read<int>('disbursement_id');
      if(debtCents>0) {
        await localDatabase.customStatement(
          'INSERT INTO lab_employee_advance_repayments '
          '(business_id,employee_id,cents,method,note,paid_at,'
          'remaining_after_cents,created_at) VALUES (?,?,?,?,?,?,?,?)',
          [_shop,employeeId,debtCents,'Payroll deduction',note.trim(),
            now,debtRemaining-debtCents,now],
        );
      }
      await localDatabase.customStatement(
        'INSERT INTO lab_payroll_settlements '
        '(disbursement_id,business_id,employee_id,week_key,gross_cents,'
        'labor_cents,debt_cents,net_cents,created_at) '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        [disbursementId,_shop,employeeId,weekKey,grossCents,
          laborCents,debtCents,grossCents-debtCents,now],
      );
      var distributed=0;
      for(var i=0;i<selected.length;i++) {
        final task=selected[i];
        final id=task['document_id'].toString()+':'+task['line_id'].toString();
        final taskHours=hoursByTask[id]!;
        final part=i==selected.length-1 ? laborCents-distributed
          : (laborCents*taskHours/hours).round();
        distributed+=part;
        await localDatabase.customStatement(
          'INSERT INTO lab_payroll_task_payments '
          '(business_id,employee_id,document_id,line_id,week_key,'
          'description,hours,cents,method,note,paid_at) '
          'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [_shop,employeeId,task['document_id'].toString(),
            task['line_id'].toString(),weekKey,
            (task['custom_description']??
              task['source_description']??'Task').toString(),
            taskHours,part,method,note.trim(),now],
        );
      }
    });
    return LabPayrollPaymentResult(
      grossCents:grossCents,debtCents:debtCents,
      netCents:grossCents-debtCents,hours:hours,
    );
  }
}
