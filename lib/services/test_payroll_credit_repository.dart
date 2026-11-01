import 'package:drift/drift.dart';
import '../core/shop_payroll_preview.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Explicit TEST-only mechanic work credits. Job planned hours and assignment
/// alone must never be represented as earned/complete payroll hours.
class TestPayrollCreditRepository {
  TestPayrollCreditRepository({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  Future<void> prepare() => _db.customStatement('''
    CREATE TABLE IF NOT EXISTS test_payroll_credits (
      business_id TEXT NOT NULL,
      allocation_id TEXT NOT NULL,
      employee_id TEXT NOT NULL,
      hours_hundredths INTEGER NOT NULL CHECK (hours_hundredths >= 0),
      rate_cents INTEGER NOT NULL CHECK (rate_cents >= 0),
      completed INTEGER NOT NULL CHECK (completed IN (0,1)),
      paid INTEGER NOT NULL DEFAULT 0 CHECK (paid IN (0,1)),
      PRIMARY KEY (business_id, allocation_id)
    )
  ''');

  /// Called only by isolated synthetic TEST flows, never by live Job sync.
  Future<void> seedSyntheticCredit({
    required String businessId,
    required ShopPayrollAllocation credit,
  }) async {
    if (businessId.trim().isEmpty || credit.id.trim().isEmpty ||
        credit.employeeId.trim().isEmpty) {
      throw ArgumentError('Missing synthetic credit identity');
    }
    credit.grossCents;
    await prepare();
    await _db.customStatement('''
      INSERT INTO test_payroll_credits (
        business_id, allocation_id, employee_id, hours_hundredths,
        rate_cents, completed, paid
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [
      businessId, credit.id, credit.employeeId, credit.hoursHundredths,
      credit.rateCentsPerHour, credit.completed ? 1 : 0,
      credit.alreadyPaid ? 1 : 0,
    ]);
  }

  /// Synthetic mechanic completion. A paid credit is immutable; completion
  /// can never reopen or re-credit previously paid payroll hours.
  Future<bool> markSyntheticPortionDone({
    required String businessId,
    required String employeeId,
    required String allocationId,
  }) async {
    if (businessId.trim().isEmpty || employeeId.trim().isEmpty ||
        allocationId.trim().isEmpty) {
      throw ArgumentError('Missing work credit identity');
    }
    await prepare();
    return _db.transaction(() async {
      final rows = await _db.customSelect('''
        SELECT completed, paid FROM test_payroll_credits
        WHERE business_id = ? AND employee_id = ? AND allocation_id = ?
      ''', variables: [
        Variable<String>(businessId), Variable<String>(employeeId),
        Variable<String>(allocationId),
      ]).get();
      if (rows.length != 1 || rows.single.read<int>('paid') != 0) {
        return false;
      }
      if (rows.single.read<int>('completed') == 1) return false;
      await _db.customStatement('''
        UPDATE test_payroll_credits SET completed = 1
        WHERE business_id = ? AND employee_id = ? AND allocation_id = ?
          AND completed = 0 AND paid = 0
      ''', [businessId, employeeId, allocationId]);
      return true;
    });
  }

  Future<List<ShopPayrollAllocation>> completedUnpaid({
    required String businessId,
    required String employeeId,
  }) async {
    if (businessId.trim().isEmpty || employeeId.trim().isEmpty) {
      throw ArgumentError('Business and employee required');
    }
    await prepare();
    final rows = await _db.customSelect('''
      SELECT allocation_id, employee_id, hours_hundredths, rate_cents
      FROM test_payroll_credits
      WHERE business_id = ? AND employee_id = ?
        AND completed = 1 AND paid = 0
      ORDER BY allocation_id
    ''', variables: [
      Variable<String>(businessId), Variable<String>(employeeId),
    ]).get();
    return rows.map((r) => ShopPayrollAllocation(
      id: r.read<String>('allocation_id'),
      employeeId: r.read<String>('employee_id'),
      hoursHundredths: r.read<int>('hours_hundredths'),
      rateCentsPerHour: r.read<int>('rate_cents'),
      completed: true, alreadyPaid: false,
    )).toList(growable: false);
  }
}
