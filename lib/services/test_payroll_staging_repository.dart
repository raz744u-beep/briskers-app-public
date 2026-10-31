import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import '../core/shop_payroll_preview.dart';

/// TEST-only durable staging. No shop payroll ledger, API, or sync integration.
/// Never interpret a staged proposal as money paid.
class TestPayrollStagingRepository {
  TestPayrollStagingRepository({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  Future<void> _prepare() async {
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS test_payroll_staging (
        business_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state = 'staged'),
        PRIMARY KEY (business_id, operation_id)
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS test_payroll_staged_credits (
        business_id TEXT NOT NULL,
        allocation_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        PRIMARY KEY (business_id, allocation_id)
      )
    ''');
  }

  /// Returns false only for an exact existing replay; conflicting replays and
  /// allocations reserved by another operation fail the entire transaction.
  Future<bool> stage({
    required String businessId,
    required ShopPayrollPaymentProposal proposal,
    required bool owner,
    required List<ShopPayrollAllocation> credits,
    required int outstandingAdvanceCents,
  }) async {
    if (businessId.trim().isEmpty ||
        !ShopPayrollTransactionPreflight.isValid(
          owner: owner, proposal: proposal, selectedCredits: credits,
          outstandingAdvanceCents: outstandingAdvanceCents,
          operationIdUnused: true,
        )) {
      throw StateError('Payroll staging preflight failed');
    }
    final sortedIds = [...proposal.allocationIds]..sort();
    final payload = jsonEncode({
      'employee_id': proposal.employeeId,
      'allocation_ids': sortedIds,
      'gross_cents': proposal.grossCents,
      'repayment_cents': proposal.repaymentCents,
      'net_cents': proposal.netCents,
      'method': proposal.method,
    });
    await _prepare();
    return _db.transaction(() async {
      final existing = await _db.customSelect(
        'SELECT payload_json FROM test_payroll_staging '
        'WHERE business_id = ? AND operation_id = ?',
        variables: [Variable<String>(businessId),
          Variable<String>(proposal.operationId)],
      ).get();
      if (existing.isNotEmpty) {
        if (existing.single.read<String>('payload_json') != payload) {
          throw StateError('Conflicting payroll operation replay');
        }
        return false;
      }
      await _db.customStatement(
        'INSERT INTO test_payroll_staging '
        '(business_id, operation_id, payload_json, state) '
        "VALUES (?, ?, ?, 'staged')",
        [businessId, proposal.operationId, payload],
      );
      for (final id in sortedIds) {
        await _db.customStatement(
          'INSERT INTO test_payroll_staged_credits '
          '(business_id, allocation_id, operation_id) VALUES (?, ?, ?)',
          [businessId, id, proposal.operationId],
        );
      }
      return true;
    });
  }
}
