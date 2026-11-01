import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Synthetic TEST-only payroll commit; not connected to UI or real payments.
/// All selected credits, the payment record and the advance deduction change
/// in one SQLite transaction. No Supabase or production ledger writes.
class TestPayrollAtomicCommit {
  TestPayrollAtomicCommit({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  Future<void> _prepare() async {
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS test_payroll_paid_operations (
        business_id TEXT NOT NULL, operation_id TEXT NOT NULL,
        employee_id TEXT NOT NULL, payload_json TEXT NOT NULL,
        gross_cents INTEGER NOT NULL, repayment_cents INTEGER NOT NULL,
        net_cents INTEGER NOT NULL,
        PRIMARY KEY (business_id, operation_id)
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS test_payroll_advances (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        balance_cents INTEGER NOT NULL CHECK (balance_cents >= 0),
        PRIMARY KEY (business_id, employee_id)
      )
    ''');
  }

  /// Only synthetic records may be finalized here. The caller must use this
  /// with the isolated TEST database, never as an authorization boundary.
  Future<bool> finalizeSynthetic({
    required String businessId,
    required String operationId,
    required bool owner,
  }) async {
    if (!owner || businessId.trim().isEmpty || operationId.trim().isEmpty) {
      throw StateError('Owner and operation required');
    }
    await _prepare();
    return _db.transaction(() async {
      final staged = await _db.customSelect(
        'SELECT payload_json FROM test_payroll_staging '
        'WHERE business_id = ? AND operation_id = ? AND state = ?',
        variables: [Variable<String>(businessId),
          Variable<String>(operationId), const Variable<String>('staged')],
      ).get();
      if (staged.length != 1) throw StateError('Missing staged proposal');
      final payload = staged.single.read<String>('payload_json');
      final existing = await _db.customSelect(
        'SELECT payload_json FROM test_payroll_paid_operations '
        'WHERE business_id = ? AND operation_id = ?',
        variables: [Variable<String>(businessId), Variable<String>(operationId)],
      ).get();
      if (existing.isNotEmpty) {
        if (existing.single.read<String>('payload_json') != payload) {
          throw StateError('Conflicting paid operation');
        }
        return false;
      }
      // JSON remains immutable from staging; validate totals against current
      // credits, not an untrusted UI preview, before writing a payment.
      final data = await _db.customSelect(
        "SELECT json_extract(?, '\$.employee_id') AS employee_id, "
        "json_extract(?, '\$.gross_cents') AS gross_cents, "
        "json_extract(?, '\$.repayment_cents') AS repayment_cents, "
        "json_extract(?, '\$.net_cents') AS net_cents",
        variables: List.generate(4, (_) => Variable<String>(payload)),
      ).get();
      final item = data.single;
      final employee = item.read<String>('employee_id');
      final gross = item.read<int>('gross_cents');
      final repayment = item.read<int>('repayment_cents');
      final net = item.read<int>('net_cents');
      if (gross < 0 || repayment < 0 || net != gross - repayment) {
        throw StateError('Invalid payment totals');
      }
      final credits = await _db.customSelect('''
        SELECT c.allocation_id, c.hours_hundredths, c.rate_cents
        FROM test_payroll_staged_credits s
        JOIN test_payroll_credits c
          ON c.business_id = s.business_id AND c.allocation_id = s.allocation_id
        WHERE s.business_id = ? AND s.operation_id = ?
          AND c.employee_id = ? AND c.completed = 1 AND c.paid = 0
      ''', variables: [Variable<String>(businessId),
        Variable<String>(operationId), Variable<String>(employee)]).get();
      final expected = await _db.customSelect(
        'SELECT count(*) AS n FROM test_payroll_staged_credits '
        'WHERE business_id = ? AND operation_id = ?',
        variables: [Variable<String>(businessId), Variable<String>(operationId)],
      ).get();
      if (credits.isEmpty || credits.length != expected.single.read<int>('n')) {
        throw StateError('Staged work is missing, incomplete or already paid');
      }
      var recomputed = 0;
      for (final credit in credits) {
        recomputed += (credit.read<int>('hours_hundredths') *
            credit.read<int>('rate_cents') + 50) ~/ 100;
      }
      if (recomputed != gross) throw StateError('Work amount changed');
      if (repayment > 0) {
        final balance = await _db.customSelect(
          'SELECT balance_cents FROM test_payroll_advances '
          'WHERE business_id = ? AND employee_id = ?',
          variables: [Variable<String>(businessId), Variable<String>(employee)],
        ).get();
        if (balance.length != 1 ||
            balance.single.read<int>('balance_cents') < repayment) {
          throw StateError('Insufficient outstanding advance');
        }
        await _db.customStatement(
          'UPDATE test_payroll_advances '
          'SET balance_cents = balance_cents - ? '
          'WHERE business_id = ? AND employee_id = ?',
          [repayment, businessId, employee],
        );
      }
      await _db.customStatement('''
        UPDATE test_payroll_credits SET paid = 1
        WHERE business_id = ? AND employee_id = ? AND allocation_id IN (
          SELECT allocation_id FROM test_payroll_staged_credits
          WHERE business_id = ? AND operation_id = ?
        )
      ''', [businessId, employee, businessId, operationId]);
      await _db.customStatement('''
        INSERT INTO test_payroll_paid_operations
        (business_id, operation_id, employee_id, payload_json,
         gross_cents, repayment_cents, net_cents)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [businessId, operationId, employee, payload, gross, repayment, net]);
      return true;
    });
  }
}
