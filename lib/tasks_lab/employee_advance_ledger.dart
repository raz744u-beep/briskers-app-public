import 'package:drift/drift.dart' show Variable;

import '../local/briskers_local_database.dart';

/// Isolated-device experiment only. Nothing here posts payroll, calls an
/// endpoint, generates shop expenses or adjusts a real payroll payment.
class LabAdvanceLedger {
  const LabAdvanceLedger(this.db);
  final BriskersLocalDatabase db;

  static const methods = <String>{
    'Payroll deduction', 'Cash', 'Zelle', 'Check', 'ACH',
  };

  Future<void> _ensure() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_employee_advance_balances (
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        opening_cents INTEGER NOT NULL CHECK(opening_cents >= 0),
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, employee_id)
      )
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS lab_employee_advance_repayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id TEXT NOT NULL, employee_id TEXT NOT NULL,
        cents INTEGER NOT NULL CHECK(cents > 0),
        method TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
        paid_at INTEGER NOT NULL,
        remaining_after_cents INTEGER NOT NULL CHECK(remaining_after_cents >= 0),
        created_at INTEGER NOT NULL
      )
    ''');
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS lab_advance_employee_date
      ON lab_employee_advance_repayments
        (business_id, employee_id, paid_at DESC, id DESC)
    ''');
  }

  static void _identity(String businessId, String employeeId) {
    if (businessId.trim().isEmpty || employeeId.trim().isEmpty) {
      throw ArgumentError('Business and employee required');
    }
  }

  Future<LabAdvanceSnapshot> read(
    String businessId, String employeeId,
  ) async {
    _identity(businessId, employeeId);
    await _ensure();
    final opening = await db.customSelect(
      'SELECT opening_cents FROM lab_employee_advance_balances '
      'WHERE business_id=? AND employee_id=?',
      variables: [Variable<String>(businessId), Variable<String>(employeeId)],
    ).getSingleOrNull();
    final payments = await db.customSelect(
      'SELECT id, cents, method, note, paid_at, remaining_after_cents '
      'FROM lab_employee_advance_repayments '
      'WHERE business_id=? AND employee_id=? '
      'ORDER BY paid_at DESC, id DESC',
      variables: [Variable<String>(businessId), Variable<String>(employeeId)],
    ).get();
    final openingCents = opening?.read<int>('opening_cents') ?? 0;
    final repayments = payments.map((row) => Map<String, dynamic>.from(row.data)).toList();
    final paid = repayments.fold<int>(
      0, (sum, row) => sum + (row['cents'] as int),
    );
    if (paid > openingCents) {
      throw StateError('Advance ledger exceeds opening balance');
    }
    return LabAdvanceSnapshot(
      openingCents: openingCents,
      remainingCents: openingCents - paid,
      repayments: repayments,
    );
  }

  /// Establish a known starting debt without reconstructing older advances.
  /// Do not silently rewrite it after repayments have been recorded.
  Future<void> setOpening({
    required String businessId,
    required String employeeId,
    required int openingCents,
  }) async {
    _identity(businessId, employeeId);
    if (openingCents < 0 || openingCents > 100000000) {
      throw ArgumentError('Invalid opening balance');
    }
    await _ensure();
    await db.transaction(() async {
      final old = await read(businessId, employeeId);
      if (old.repayments.isNotEmpty && old.openingCents != openingCents) {
        throw StateError('Repayments exist. Opening balance is locked.');
      }
      await db.customStatement(
        'INSERT INTO lab_employee_advance_balances '
        '(business_id, employee_id, opening_cents, updated_at) VALUES (?, ?, ?, ?) '
        'ON CONFLICT(business_id, employee_id) DO UPDATE SET '
        'opening_cents=excluded.opening_cents, updated_at=excluded.updated_at',
        [businessId, employeeId, openingCents, DateTime.now().millisecondsSinceEpoch],
      );
    });
  }

  /// Durable TEST-only repayment. A 'Payroll deduction' method selection
  /// records a proposed test entry; it does not touch real compensation.
  Future<void> repay({
    required String businessId,
    required String employeeId,
    required int cents,
    required String method,
    required DateTime date,
    String note = '',
  }) async {
    _identity(businessId, employeeId);
    if (cents < 1 || !methods.contains(method) ||
        date.year < 2000 || date.year > 2100) {
      throw ArgumentError('Invalid repayment');
    }
    await _ensure();
    await db.transaction(() async {
      final previous = await read(businessId, employeeId);
      if (cents > previous.remainingCents) {
        throw StateError('Repayment exceeds the outstanding balance');
      }
      await db.customStatement(
        'INSERT INTO lab_employee_advance_repayments '
        '(business_id, employee_id, cents, method, note, paid_at, '
        'remaining_after_cents, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [businessId, employeeId, cents, method, note.trim(),
          date.millisecondsSinceEpoch, previous.remainingCents - cents,
          DateTime.now().millisecondsSinceEpoch],
      );
    });
  }
}

class LabAdvanceSnapshot {
  const LabAdvanceSnapshot({
    required this.openingCents,
    required this.remainingCents,
    required this.repayments,
  });
  final int openingCents;
  final int remainingCents;
  final List<Map<String, dynamic>> repayments;
}
