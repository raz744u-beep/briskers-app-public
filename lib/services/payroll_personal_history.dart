import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import 'local_payroll_outbox.dart';

abstract interface class PayrollRoleGateway {
  Future<Map<String, dynamic>> fetchAccess(String shop);
  Future<Map<String, dynamic>> fetchOwnHistory(String shop);
}

/// Own-pay projection only. Never caches accounts, proofs or company totals.
class PayrollPersonalHistory {
  PayrollPersonalHistory({
    required this.database,
    required this.businessId,
    required this.actorId,
    required this.isCurrent,
  });
  final BriskersLocalDatabase database;
  final String businessId, actorId;
  final bool Function() isCurrent;
  void _guard() {
    if (!isCurrent() || actorId.isEmpty) {
      throw StateError('Payroll session changed.');
    }
  }

  Future<void> _table() async {
    _guard();
    await database.customStatement(
      'CREATE TABLE IF NOT EXISTS payroll_own_history (business_id TEXT NOT NULL,actor_id TEXT NOT NULL,receipts_json TEXT NOT NULL,PRIMARY KEY(business_id,actor_id))',
    );
    _guard();
  }

  Future<List<Map<String, dynamic>>> read() async {
    await _table();
    final row = await database
        .customSelect(
          'SELECT receipts_json FROM payroll_own_history WHERE business_id=? AND actor_id=?',
          variables: [Variable(businessId), Variable(actorId)],
        )
        .getSingleOrNull();
    _guard();
    return row == null
        ? []
        : (jsonDecode(row.read<String>('receipts_json')) as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
  }

  Future<void> refresh(PayrollRoleGateway gateway) async {
    await _table();
    final result = await gateway.fetchOwnHistory(businessId);
    _guard();
    if (result['business_id'] != businessId ||
        result['actor_id'] != actorId ||
        result['receipts'] is! List) {
      throw StateError('Personal payroll scope mismatch.');
    }
    final clean = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final row in result['receipts'] as List) {
      if (row is! Map ||
          !LocalPayrollOutbox.isUuid(row['transaction_id']?.toString() ?? '') ||
          !ids.add(row['transaction_id'] as String) ||
          row['amount_cents'] is! int ||
          row['amount_cents'] <= 0 ||
          !['posted', 'void', 'pending'].contains(row['status']) ||
          DateTime.tryParse(row['payment_date']?.toString() ?? '') == null ||
          (row['method_label'] != null && row['method_label'] is! String)) {
        throw StateError('Invalid own-pay receipt.');
      }
      clean.add({
        for (final key in [
          'transaction_id',
          'amount_cents',
          'payment_date',
          'status',
          'method_label',
          'currency_code',
        ])
          key: row[key],
      });
    }
    await database.transaction(() async {
      _guard();
      await database.customStatement(
        'INSERT INTO payroll_own_history VALUES(?,?,?) ON CONFLICT(business_id,actor_id) DO UPDATE SET receipts_json=excluded.receipts_json',
        [businessId, actorId, jsonEncode(clean)],
      );
      _guard();
    });
  }
}
