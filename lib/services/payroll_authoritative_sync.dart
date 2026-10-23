import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_payroll_outbox.dart';

abstract interface class PayrollAuthoritativeGateway {
  Future<bool> supportsReviewedPayrollV1(String businessId);
  Future<Map<String, dynamic>> fetchPayrollState(String businessId);
  Future<void> applyCatalogMutation(
    String businessId,
    Map<String, dynamic> mutation,
  );
}

/// Confirmed server catalog/history and durable pending configuration changes.
/// Local draft methods never become server identities by matching their labels.
class PayrollAuthoritativeSync {
  PayrollAuthoritativeSync({
    required BriskersLocalDatabase database,
    required this.businessId,
    required this.ownerUserId,
    required this.isContextCurrent,
  }) : _db = database;
  final BriskersLocalDatabase _db;
  final String businessId;
  final String ownerUserId;
  final bool Function() isContextCurrent;
  bool _syncing = false;

  void _guard() {
    if (!isContextCurrent() || businessId.isEmpty || ownerUserId.isEmpty) {
      throw StateError('Authenticated Owner context changed.');
    }
  }

  List<Variable> get _scope => [Variable(businessId), Variable(ownerUserId)];
  Future<void> _prepare() async {
    _guard();
    await _db.customStatement(
      '''CREATE TABLE IF NOT EXISTS payroll_authoritative_cache (
      business_id TEXT NOT NULL, owner_id TEXT NOT NULL, revision INTEGER NOT NULL,
      catalog_json TEXT NOT NULL, PRIMARY KEY(business_id,owner_id))''',
    );
    await _db.customStatement(
      '''CREATE TABLE IF NOT EXISTS payroll_catalog_queue (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL, owner_id TEXT NOT NULL,
      operation_id TEXT NOT NULL, payload_json TEXT NOT NULL,
      UNIQUE(business_id,owner_id,operation_id))''',
    );
    await _db.customStatement(
      '''CREATE TABLE IF NOT EXISTS payroll_receipt_cache (
      business_id TEXT NOT NULL, owner_id TEXT NOT NULL, transaction_id TEXT NOT NULL,
      receipt_json TEXT NOT NULL, PRIMARY KEY(business_id,owner_id,transaction_id))''',
    );
    _guard();
  }

  Future<Map<String, dynamic>> catalog() async {
    await _prepare();
    final row = await _db
        .customSelect(
          'SELECT revision,catalog_json FROM payroll_authoritative_cache WHERE business_id=? AND owner_id=?',
          variables: _scope,
        )
        .getSingleOrNull();
    _guard();
    return row == null
        ? {
            'confirmed': false,
            'methods': <dynamic>[],
            'employee_defaults': <dynamic>[],
            'eligible_labor': <dynamic>[],
          }
        : {
            ...Map<String, dynamic>.from(
              jsonDecode(row.read<String>('catalog_json')) as Map,
            ),
            'revision': row.read<int>('revision'),
          };
  }

  Future<List<Map<String, dynamic>>> receipts({
    bool includePending = false,
  }) async {
    await _prepare();
    final rows = await _db
        .customSelect(
          'SELECT receipt_json FROM payroll_receipt_cache WHERE business_id=? AND owner_id=? ORDER BY transaction_id',
          variables: _scope,
        )
        .get();
    _guard();
    final receipts = rows
        .map(
          (r) => Map<String, dynamic>.from(
            jsonDecode(r.read<String>('receipt_json')) as Map,
          ),
        )
        .toList();
    receipts.sort(
      (a, b) => '${b['payment_date']}:${b['transaction_id']}'.compareTo(
        '${a['payment_date']}:${a['transaction_id']}',
      ),
    );
    return includePending
        ? receipts
        : receipts.where((r) => r['status'] != 'pending').toList();
  }

  Future<int> pendingCount() async {
    await _prepare();
    final row = await _db
        .customSelect(
          'SELECT count(*) AS n FROM payroll_catalog_queue WHERE business_id=? AND owner_id=?',
          variables: _scope,
        )
        .getSingle();
    _guard();
    return row.read<int>('n');
  }

  /// Payload and operation UUID are immutable even when the network response
  /// is lost. Server mutation deduplication must precede version checks.
  Future<void> queueMutation(Map<String, dynamic> mutation) async {
    await _prepare();
    if (!LocalPayrollOutbox.isUuid(
          mutation['operation_id']?.toString() ?? '',
        ) ||
        !['register', 'edit', 'default'].contains(mutation['action'])) {
      throw ArgumentError(
        'A durable catalog operation and supported action are required.',
      );
    }
    mutation = Map<String, dynamic>.from(mutation);
    if (mutation['action'] == 'default') {
      final confirmed = await catalog();
      if (confirmed['confirmed'] != true) {
        throw StateError(
          'Refresh confirmed settings before choosing a default.',
        );
      }
      mutation.putIfAbsent('expected_revision', () => confirmed['revision']);
    }
    final action = mutation['action'];
    if (action == 'register') {
      if (!LocalPayrollOutbox.isUuid(
            mutation['client_key']?.toString() ?? '',
          ) ||
          mutation['label'] is! String ||
          (mutation['label'] as String).trim().isEmpty ||
          (mutation['label'] as String).length > 80 ||
          ![
            'cash',
            'check',
            'zelle',
            'ach',
            'custom',
          ].contains(mutation['kind'])) {
        throw ArgumentError(
          'A durable registration key, name and kind are required.',
        );
      }
    } else {
      final known = (await catalog())['methods'] as List;
      final matching = known
          .where((m) => m['id'] == mutation['method_id'])
          .toList();
      if (mutation['method_id'] != null && matching.length != 1) {
        throw StateError('Choose a registered shop method.');
      }
      if (action == 'edit' &&
          (matching.isEmpty ||
              mutation['expected_version'] != matching.single['version'])) {
        throw StateError('Method changed. Reload confirmed settings.');
      }
      if (action == 'default' &&
          (!LocalPayrollOutbox.isUuid(
                mutation['employee_id']?.toString() ?? '',
              ) ||
              (matching.isNotEmpty && matching.single['enabled'] != true))) {
        throw StateError('Employee and enabled registered method required.');
      }
      _guard();
    }
    final encoded = jsonEncode(mutation);
    await _db.transaction(() async {
      final old = await _db
          .customSelect(
            'SELECT payload_json FROM payroll_catalog_queue WHERE business_id=? AND owner_id=? AND operation_id=?',
            variables: [
              ..._scope,
              Variable(mutation['operation_id'] as String),
            ],
          )
          .getSingleOrNull();
      _guard();
      if (old != null) {
        if (old.read<String>('payload_json') != encoded) {
          throw StateError('Queued catalog operation is immutable.');
        }
        return;
      }
      await _db.customStatement(
        'INSERT INTO payroll_catalog_queue(business_id,owner_id,operation_id,payload_json) VALUES(?,?,?,?)',
        [businessId, ownerUserId, mutation['operation_id'], encoded],
      );
      _guard();
    });
  }

  /// Drops only unsent/unacknowledged catalog edits. A server-accepted edit is
  /// not undone; the next pull restores its authoritative result.
  Future<void> discardPendingEdits() async {
    await _prepare();
    await _db.transaction(() async {
      _guard();
      await _db.customStatement(
        'DELETE FROM payroll_catalog_queue WHERE business_id=? AND owner_id=?',
        [businessId, ownerUserId],
      );
      _guard();
    });
  }

  Future<bool> synchronize(PayrollAuthoritativeGateway gateway) async {
    if (_syncing) return false;
    _syncing = true;
    try {
      await _prepare();
      if (!await gateway.supportsReviewedPayrollV1(businessId)) return false;
      _guard();
      final pending = await _db
          .customSelect(
            'SELECT operation_id,payload_json FROM payroll_catalog_queue WHERE business_id=? AND owner_id=? ORDER BY sequence',
            variables: _scope,
          )
          .get();
      Object? mutationFailure;
      for (final row in pending) {
        try {
          _guard();
          await gateway.applyCatalogMutation(
            businessId,
            Map<String, dynamic>.from(
              jsonDecode(row.read<String>('payload_json')) as Map,
            ),
          );
          _guard();
          await _db.customStatement(
            'DELETE FROM payroll_catalog_queue WHERE business_id=? AND owner_id=? AND operation_id=?',
            [businessId, ownerUserId, row.read<String>('operation_id')],
          );
        } catch (error) {
          mutationFailure = error;
          break;
        }
      }
      final state = await gateway.fetchPayrollState(businessId);
      _guard();
      _validate(state);
      await _db.transaction(() async {
        _guard();
        final current = await _db
            .customSelect(
              'SELECT revision FROM payroll_authoritative_cache WHERE business_id=? AND owner_id=?',
              variables: _scope,
            )
            .getSingleOrNull();
        if (current != null &&
            current.read<int>('revision') > (state['revision'] as int)) {
          return;
        }
        _guard();
        await _db.customStatement(
          '''INSERT INTO payroll_authoritative_cache VALUES(?,?,?,?)
          ON CONFLICT(business_id,owner_id) DO UPDATE SET revision=excluded.revision,catalog_json=excluded.catalog_json
          WHERE excluded.revision>=payroll_authoritative_cache.revision''',
          [
            businessId,
            ownerUserId,
            state['revision'],
            jsonEncode({
              'confirmed': true,
              'methods': state['methods'],
              'employee_defaults': state['employee_defaults'],
              'eligible_labor': state['eligible_labor'] ?? <dynamic>[],
            }),
          ],
        );
        for (final receipt in state['receipts'] as List) {
          await _db.customStatement(
            '''INSERT INTO payroll_receipt_cache VALUES(?,?,?,?)
            ON CONFLICT(business_id,owner_id,transaction_id) DO UPDATE SET receipt_json=excluded.receipt_json''',
            [
              businessId,
              ownerUserId,
              receipt['transaction_id'],
              jsonEncode(receipt),
            ],
          );
        }
        _guard();
      });
      if (mutationFailure != null) throw mutationFailure;
      return true;
    } finally {
      _syncing = false;
    }
  }

  void _validate(Map<String, dynamic> state) {
    if (state['business_id'] != businessId ||
        state['revision'] is! int ||
        (state['revision'] as int) < 0 ||
        state['methods'] is! List ||
        state['employee_defaults'] is! List ||
        state['receipts'] is! List) {
      throw StateError('Invalid authoritative payroll snapshot.');
    }
    final ids = <String>{}, keys = <String>{};
    for (final raw in state['methods'] as List) {
      if (raw is! Map ||
          raw['business_id'] != businessId ||
          !LocalPayrollOutbox.isUuid(raw['id']?.toString() ?? '') ||
          !LocalPayrollOutbox.isUuid(raw['client_key']?.toString() ?? '') ||
          !ids.add(raw['id'] as String) ||
          !keys.add(raw['client_key'] as String) ||
          raw['label'] is! String ||
          (raw['label'] as String).trim().isEmpty ||
          !['cash', 'check', 'zelle', 'ach', 'custom'].contains(raw['kind']) ||
          raw['enabled'] is! bool ||
          raw['sort_order'] is! int ||
          raw['version'] is! int ||
          (raw['version'] as int) < 1) {
        throw StateError('Invalid registered method catalog.');
      }
    }
    final employees = <String>{};
    for (final raw in state['employee_defaults'] as List) {
      if (raw is! Map ||
          !LocalPayrollOutbox.isUuid(raw['employee_id']?.toString() ?? '') ||
          !employees.add(raw['employee_id'] as String) ||
          !ids.contains(raw['method_id'])) {
        throw StateError('Invalid employee default identity.');
      }
    }
    final laborIds = <String>{};
    for (final raw in state['eligible_labor'] as List? ?? []) {
      if (raw is! Map ||
          raw['business_id'] != businessId ||
          !LocalPayrollOutbox.isUuid(raw['labor_id']?.toString() ?? '') ||
          !LocalPayrollOutbox.isUuid(raw['employee_id']?.toString() ?? '') ||
          !LocalPayrollOutbox.isUuid(raw['job_id']?.toString() ?? '') ||
          !laborIds.add(raw['labor_id'] as String) ||
          raw['available_cents'] is! int ||
          raw['available_cents'] < 0 ||
          DateTime.tryParse(raw['earned_on']?.toString() ?? '') == null) {
        throw StateError('Invalid earned labor identity.');
      }
    }
    final receipts = <String>{};
    for (final raw in state['receipts'] as List) {
      if (raw is! Map ||
          raw['business_id'] != businessId ||
          !['posted', 'pending', 'void'].contains(raw['status']) ||
          !LocalPayrollOutbox.isUuid(raw['transaction_id']?.toString() ?? '') ||
          !receipts.add(raw['transaction_id'] as String) ||
          raw['amount_cents'] is! int ||
          (raw['amount_cents'] as int) <= 0 ||
          DateTime.tryParse(raw['payment_date']?.toString() ?? '') == null) {
        throw StateError('Invalid authoritative receipt.');
      }
      // A historical unknown method is allowed; never infer its label or kind.
      if (raw['method_label'] != null && raw['method_label'] is! String) {
        throw StateError('Invalid historical method label.');
      }
    }
  }
}
