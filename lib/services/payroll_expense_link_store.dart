import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';

/// Durable mapping from immutable payroll settlement to its financial row.
///
/// This table is independent of the financial transaction ID, which changes
/// when an offline create is acknowledged by the server.
class PayrollExpenseLinkStore {
  PayrollExpenseLinkStore(this.database);

  final BriskersLocalDatabase database;

  Future<void> prepare() async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS payroll_expense_links_v1 (
        business_id TEXT NOT NULL,
        payroll_operation_id TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        PRIMARY KEY (business_id, payroll_operation_id),
        UNIQUE (business_id, transaction_id)
      )
    ''');
  }

  Future<void> preparePending() => database.customStatement("""
    CREATE TABLE IF NOT EXISTS payroll_expense_projection_pending_v1 (
      business_id TEXT NOT NULL,
      operation_id TEXT NOT NULL,
      PRIMARY KEY (business_id, operation_id)
    )
  """);

  Future<void> markPending(String businessId, String operationId) async {
    await preparePending();
    await database.customStatement(
      'INSERT OR IGNORE INTO payroll_expense_projection_pending_v1 VALUES (?, ?)',
      [businessId, operationId],
    );
  }

  Future<String?> transactionId(String businessId, String operationId) async {
    await prepare();
    final rows = await database
        .customSelect(
          'SELECT transaction_id FROM payroll_expense_links_v1 '
          'WHERE business_id=? AND payroll_operation_id=?',
          variables: [
            Variable<String>(businessId),
            Variable<String>(operationId),
          ],
        )
        .get();
    return rows.firstOrNull?.read<String>('transaction_id');
  }

  /// Never silently reassign an existing payroll operation to another expense.
  /// Caller must wrap this with financial create in the same DB transaction.
  Future<void> link(
    String businessId,
    String operationId,
    String transactionId,
  ) async {
    if (businessId.isEmpty || operationId.isEmpty || transactionId.isEmpty) {
      throw ArgumentError('Missing payroll expense link identity.');
    }
    await prepare();
    final existing = await this.transactionId(businessId, operationId);
    if (existing != null && existing != transactionId) {
      throw StateError(
        'Payroll settlement is already linked to another expense.',
      );
    }
    await database.customStatement(
      'INSERT OR IGNORE INTO payroll_expense_links_v1 '
      '(business_id,payroll_operation_id,transaction_id) VALUES (?,?,?)',
      [businessId, operationId, transactionId],
    );
    final confirmed = await this.transactionId(businessId, operationId);
    if (confirmed != transactionId) {
      throw StateError('Conflicting payroll expense link.');
    }
  }

  /// Call inside the same transaction that remaps the financial cache and
  /// journal after the server returns its canonical transaction ID.
  Future<void> remap(String businessId, String localId, String serverId) async {
    if (businessId.isEmpty || localId.isEmpty || serverId.isEmpty) {
      throw ArgumentError('Missing financial remap identity.');
    }
    await prepare();
    await database.customStatement(
      'UPDATE payroll_expense_links_v1 SET transaction_id=? '
      'WHERE business_id=? AND transaction_id=?',
      [serverId, businessId, localId],
    );
  }
}
