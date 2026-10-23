import 'dart:math';

import 'package:drift/drift.dart';

import '../core/payroll_payment_contract.dart';
import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import '../local/local_database_provider.dart';

/// Device-local configuration, isolated by authenticated Owner and shop.
/// UUIDs are durable identities, NOT evidence of server registration. Nothing
/// in this store registers methods remotely or enables payroll submission.
class LocalPayrollMethodStore {
  LocalPayrollMethodStore({BriskersLocalDatabase? database})
    : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  static String newIdentity() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _prepare(bool isOwner, String shop, String owner) async {
    if (!isOwner) throw StateError('Owner access required.');
    if (shop.trim().isEmpty || owner.trim().isEmpty) {
      throw ArgumentError('Authenticated Owner and shop required.');
    }
    await _db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_payroll_methods (
      business_id TEXT NOT NULL, owner_user_id TEXT NOT NULL, id TEXT NOT NULL,
      label TEXT NOT NULL, kind TEXT NOT NULL, enabled INTEGER NOT NULL,
      sort_order INTEGER NOT NULL, version INTEGER NOT NULL,
      PRIMARY KEY (business_id, owner_user_id, id))''',
    );
    await _db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_payroll_defaults (
      business_id TEXT NOT NULL, owner_user_id TEXT NOT NULL,
      employee_id TEXT NOT NULL, method_id TEXT NOT NULL,
      PRIMARY KEY (business_id, owner_user_id, employee_id))''',
    );
  }

  Future<List<PayrollPaymentMethod>> load({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
  }) async {
    await _prepare(isOwner, businessId, ownerUserId);
    return _db.transaction(() async {
      var rows = await _rows(businessId, ownerUserId);
      if (rows.isEmpty) {
        final seeds = <(String, PayrollPaymentMethodKind)>[
          ('Cash', PayrollPaymentMethodKind.cash),
          ('Check', PayrollPaymentMethodKind.check),
          ('Zelle', PayrollPaymentMethodKind.zelle),
          ('ACH / Bank Transfer', PayrollPaymentMethodKind.ach),
        ];
        for (var i = 0; i < seeds.length; i++) {
          await _db.customStatement(
            '''INSERT INTO local_payroll_methods
            VALUES (?, ?, ?, ?, ?, 1, ?, 1)''',
            [
              businessId,
              ownerUserId,
              newIdentity(),
              seeds[i].$1,
              seeds[i].$2.name,
              i,
            ],
          );
        }
        rows = await _rows(businessId, ownerUserId);
      }
      return rows
          .map(
            (r) => PayrollPaymentMethod(
              id: r.read<String>('id'),
              businessId: businessId,
              label: r.read<String>('label'),
              kind: PayrollPaymentMethodKind.values.byName(
                r.read<String>('kind'),
              ),
              enabled: r.read<int>('enabled') == 1,
              sortOrder: r.read<int>('sort_order'),
              version: r.read<int>('version'),
            ),
          )
          .toList();
    });
  }

  Future<List<QueryRow>> _rows(String shop, String owner) => _db
      .customSelect(
        '''SELECT * FROM local_payroll_methods WHERE business_id=? AND owner_user_id=?
       ORDER BY sort_order, id''',
        variables: [Variable(shop), Variable(owner)],
      )
      .get();

  Future<void> add({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
    required String label,
    required PayrollPaymentMethodKind kind,
  }) async {
    final methods = await load(
      isOwner: isOwner,
      businessId: businessId,
      ownerUserId: ownerUserId,
    );
    _validateLabel(label);
    await _db.customStatement(
      '''INSERT INTO local_payroll_methods
      VALUES (?, ?, ?, ?, ?, 1, ?, 1)''',
      [
        businessId,
        ownerUserId,
        newIdentity(),
        label.trim(),
        kind.name,
        methods.length,
      ],
    );
  }

  static void _validateLabel(String label) {
    if (label.trim().isEmpty || label.trim().length > 80) {
      throw ArgumentError('Method name must be 1–80 characters.');
    }
  }

  /// Compare-and-swap prevents stale settings from overwriting a newer edit.
  /// Kind and identity are immutable; disabling never rewrites drafts/history.
  Future<void> update({
    required bool isOwner,
    required String ownerUserId,
    required PayrollPaymentMethod method,
    required String label,
    required bool enabled,
  }) async {
    await _prepare(isOwner, method.businessId, ownerUserId);
    _validateLabel(label);
    final changed = await _db.customUpdate(
      '''UPDATE local_payroll_methods
      SET label=?, enabled=?, version=version+1
      WHERE business_id=? AND owner_user_id=? AND id=? AND version=?''',
      variables: [
        Variable(label.trim()),
        Variable(enabled ? 1 : 0),
        Variable(method.businessId),
        Variable(ownerUserId),
        Variable(method.id),
        Variable(method.version),
      ],
    );
    if (changed != 1) throw StateError('Method changed. Reload settings.');
  }

  Future<void> reorder({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
    required List<String> ids,
  }) async {
    await _prepare(isOwner, businessId, ownerUserId);
    await _db.transaction(() async {
      final rows = await _rows(businessId, ownerUserId);
      final known = rows.map((r) => r.read<String>('id')).toSet();
      if (ids.length != known.length ||
          ids.toSet().length != ids.length ||
          !known.containsAll(ids)) {
        throw ArgumentError('Complete method order required.');
      }
      for (var i = 0; i < ids.length; i++) {
        await _db.customStatement(
          '''UPDATE local_payroll_methods
          SET sort_order=?, version=version+1
          WHERE business_id=? AND owner_user_id=? AND id=?''',
          [i, businessId, ownerUserId, ids[i]],
        );
      }
    });
  }

  Future<Map<String, String>> defaults({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
  }) async {
    await _prepare(isOwner, businessId, ownerUserId);
    final rows = await _db
        .customSelect(
          '''SELECT employee_id, method_id
      FROM local_payroll_defaults WHERE business_id=? AND owner_user_id=?''',
          variables: [Variable(businessId), Variable(ownerUserId)],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('employee_id'): r.read<String>('method_id'),
    };
  }

  Future<void> setDefault({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
    required String employeeId,
    required String? methodId,
  }) async {
    await _prepare(isOwner, businessId, ownerUserId);
    if (employeeId.trim().isEmpty) {
      throw ArgumentError('Employee identity required.');
    }
    await _db.transaction(() async {
      if (methodId != null) {
        final methods = await load(
          isOwner: isOwner,
          businessId: businessId,
          ownerUserId: ownerUserId,
        );
        if (PayrollPaymentMethodChoice.resolve(
              businessId: businessId,
              methods: methods,
              employeeDefaultId: methodId,
            ) ==
            null) {
          throw StateError('Choose an enabled method from this shop.');
        }
      }
      await _db.customStatement(
        '''DELETE FROM local_payroll_defaults
        WHERE business_id=? AND owner_user_id=? AND employee_id=?''',
        [businessId, ownerUserId, employeeId],
      );
      if (methodId != null) {
        await _db.customStatement(
          'INSERT INTO local_payroll_defaults VALUES (?, ?, ?, ?)',
          [businessId, ownerUserId, employeeId, methodId],
        );
      }
    });
  }
}
