import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/payroll_payment_contract.dart';
import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import '../local/local_database_provider.dart';

/// Locally durable, explicitly NON-POSTED payroll drafts.
///
/// This does not write to sync_outbox, does not record an expense, and never
/// records payment confirmation. A reviewed payroll server RPC, role checks
/// and private proof upload must exist before any submission is possible.
///
/// The creating Owner's identity is part of the key to avoid sharing drafts
/// between users of the same physical device.
class LocalPayrollDraftStore {
  LocalPayrollDraftStore({BriskersLocalDatabase? database})
    : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  static void _requireScope(String businessId, String ownerUserId) {
    if (businessId.trim().isEmpty || ownerUserId.trim().isEmpty) {
      throw ArgumentError('A shop and authenticated Owner are required.');
    }
  }

  static void _requireOwner(bool isOwner) {
    if (!isOwner) {
      throw StateError('Only the Owner may access payroll payment drafts.');
    }
  }

  Future<void> _requireEditable(
    String shop,
    String owner,
    String operation,
  ) async {
    final exists = await _database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='local_payroll_outbox'",
        )
        .get();
    if (exists.isEmpty) return;
    final frozen = await _database
        .customSelect(
          '''SELECT operation_id FROM local_payroll_outbox
      WHERE business_id=? AND owner_user_id=? AND operation_id=?''',
          variables: [Variable(shop), Variable(owner), Variable(operation)],
        )
        .get();
    if (frozen.isNotEmpty) {
      throw StateError(
        'Queued payment is frozen; it cannot be edited or discarded.',
      );
    }
  }

  Future<void> _ensureTable() => _database.customStatement('''
    CREATE TABLE IF NOT EXISTS local_payroll_payment_drafts (
      business_id TEXT NOT NULL,
      owner_user_id TEXT NOT NULL,
      operation_id TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      PRIMARY KEY (business_id, owner_user_id, operation_id)
    )
  ''');

  static Map<String, dynamic> _toJson(PayrollPaymentDraft draft) => {
    'business_id': draft.businessId,
    'employee_id': draft.employeeId,
    'operation_id': draft.operationId,
    'method_id': draft.methodId,
    'method_label_snapshot': draft.methodLabelSnapshot,
    'amount_cents': draft.amountCents,
    'payment_date': draft.paymentDate.toUtc().toIso8601String(),
    'payroll_week_key': draft.payrollWeekKey,
    'labor_allocations': draft.laborAllocations.map((a) => a.toJson()).toList(),
    'source_account_id': draft.sourceAccountId,
    'reference': draft.reference,
    'check_proof_attachment_id': draft.checkProofAttachmentId,
    'check_proof_durably_stored': draft.checkProofDurablyStored,
    'check_proof_size_bytes': draft.checkProofSizeBytes,
    'check_proof_sha256': draft.checkProofSha256,
    'state': 'draft_only',
  };

  static PayrollPaymentDraft? _fromJson(
    Map<String, dynamic> json,
    String businessId,
    String operationId,
  ) {
    try {
      if (json['business_id'] != businessId ||
          json['operation_id'] != operationId ||
          json['state'] != 'draft_only') {
        return null;
      }
      final amount = json['amount_cents'];
      if (amount is! int) return null;
      final date = DateTime.tryParse(json['payment_date']?.toString() ?? '');
      if (date == null) return null;
      return PayrollPaymentDraft(
        businessId: businessId,
        employeeId: json['employee_id']?.toString() ?? '',
        operationId: operationId,
        methodId: json['method_id']?.toString() ?? '',
        methodLabelSnapshot: json['method_label_snapshot']?.toString() ?? '',
        amountCents: amount,
        paymentDate: date,
        payrollWeekKey: json['payroll_week_key']?.toString() ?? '',
        laborAllocations: (json['labor_allocations'] as List? ?? [])
            .map(
              (a) => PayrollLaborAllocation.fromJson(
                Map<String, dynamic>.from(a as Map),
              ),
            )
            .toList(),
        sourceAccountId: json['source_account_id']?.toString(),
        reference: json['reference']?.toString(),
        checkProofAttachmentId: json['check_proof_attachment_id']?.toString(),
        checkProofDurablyStored: json['check_proof_durably_stored'] == true,
        checkProofSizeBytes: json['check_proof_size_bytes'] is int
            ? json['check_proof_size_bytes'] as int
            : null,
        checkProofSha256: json['check_proof_sha256']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Save or edit the *same* draft by stable operation ID. No financial write.
  ///
  /// A Check draft can be saved before proof is staged, but cannot be submitted
  /// by the separate validation contract without durable proof metadata.
  Future<void> save({
    required bool isOwner,
    required String ownerUserId,
    required PayrollPaymentDraft draft,
    bool Function()? isContextCurrent,
  }) async {
    _requireOwner(isOwner);
    if (isContextCurrent?.call() == false) {
      throw StateError('Owner session changed.');
    }
    _requireScope(draft.businessId, ownerUserId);
    if (draft.operationId.trim().isEmpty || draft.employeeId.trim().isEmpty) {
      throw ArgumentError('Employee and stable operation ID are required.');
    }
    await _ensureTable();
    if (isContextCurrent?.call() == false) {
      throw StateError('Owner session changed.');
    }
    await _database.transaction(() async {
      await _requireEditable(draft.businessId, ownerUserId, draft.operationId);
      if (isContextCurrent?.call() == false) {
        throw StateError('Owner session changed.');
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await _database.customStatement(
        '''
      INSERT INTO local_payroll_payment_drafts
        (business_id, owner_user_id, operation_id, payload_json,
         created_at_utc, updated_at_utc)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (business_id, owner_user_id, operation_id)
      DO UPDATE SET payload_json=excluded.payload_json,
                    updated_at_utc=excluded.updated_at_utc
    ''',
        [
          draft.businessId,
          ownerUserId,
          draft.operationId,
          jsonEncode(_toJson(draft)),
          now,
          now,
        ],
      );
    });
  }

  /// Return drafts only to the same Owner and shop; never returns a paid state.
  Future<List<PayrollPaymentDraft>> load({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
  }) async {
    _requireOwner(isOwner);
    _requireScope(businessId, ownerUserId);
    await _ensureTable();
    final rows = await _database
        .customSelect(
          '''
      SELECT operation_id, payload_json
      FROM local_payroll_payment_drafts
      WHERE business_id = ? AND owner_user_id = ?
      ORDER BY updated_at_utc DESC, operation_id
    ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(ownerUserId),
          ],
        )
        .get();

    final result = <PayrollPaymentDraft>[];
    for (final row in rows) {
      try {
        final json = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map,
        );
        final draft = _fromJson(
          json,
          businessId,
          row.read<String>('operation_id'),
        );
        if (draft != null) result.add(draft);
      } catch (_) {
        // An invalid local row must never be treated as proof of payment.
      }
    }
    return result;
  }

  /// Explicitly abandon a *draft*. This does not delete posted payroll.
  Future<void> discard({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
    required String operationId,
    bool Function()? isContextCurrent,
  }) async {
    _requireOwner(isOwner);
    _requireScope(businessId, ownerUserId);
    if (operationId.trim().isEmpty) return;
    await _ensureTable();
    if (isContextCurrent?.call() == false) {
      throw StateError('Owner session changed.');
    }
    await _database.transaction(() async {
      await _requireEditable(businessId, ownerUserId, operationId);
      if (isContextCurrent?.call() == false) {
        throw StateError('Owner session changed.');
      }
      await _database.customStatement(
        '''
      DELETE FROM local_payroll_payment_drafts
      WHERE business_id=? AND owner_user_id=? AND operation_id=?
    ''',
        [businessId, ownerUserId, operationId],
      );
    });
  }
}
