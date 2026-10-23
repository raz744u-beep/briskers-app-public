import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../core/payroll_payment_contract.dart';
import '../local/briskers_local_database.dart' show BriskersLocalDatabase;

/// No production implementation is installed. An approved backend must supply
/// this transport; neither a local UUID nor a UI preference enables posting.
abstract interface class PayrollPostingActivation {
  bool get canQueueOffline;
}

abstract interface class PayrollPostingGateway {
  Future<bool> supportsReviewedPayrollV1(String businessId);
  Future<String> registerMethod(PayrollPaymentMethod method);
  Future<void> prepare(Map<String, dynamic> frozenPayload);
  Future<void> uploadAndVerifyProof(Map<String, dynamic> frozenPayload);
  Future<PayrollPostingReceipt> post(Map<String, dynamic> frozenPayload);
}

class PayrollPostingReceipt {
  const PayrollPostingReceipt({
    required this.businessId,
    required this.operationId,
    required this.transactionId,
    required this.amountCents,
    this.status = 'posted',
  });
  final String businessId;
  final String operationId;
  final String transactionId;
  final int amountCents;
  final String status;
}

/// Independent, durable queue for the reviewed payroll adapter. The normal app
/// does NOT wire a gateway or expose enqueue/post actions yet. Frozen payloads
/// survive lost responses and restarts; only an authoritative receipt marks a
/// row posted. The draft store rejects edits/discard once a row is frozen.
class LocalPayrollOutbox {
  LocalPayrollOutbox({
    required BriskersLocalDatabase database,
    required this.businessId,
    required this.ownerUserId,
    required this.isContextCurrent,
    required this.verifyLocalProof,
  }) : _db = database;
  final BriskersLocalDatabase _db;
  final String businessId;
  final String ownerUserId;
  final bool Function() isContextCurrent;
  final Future<bool> Function(PayrollPaymentDraft) verifyLocalProof;

  static bool isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  void _guard() {
    if (!isContextCurrent() || businessId.isEmpty || ownerUserId.isEmpty) {
      throw StateError('Authenticated Owner context changed.');
    }
  }

  Future<void> _tables() async {
    _guard();
    await _db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_payroll_outbox (
      business_id TEXT NOT NULL, owner_user_id TEXT NOT NULL, operation_id TEXT NOT NULL,
      frozen_json TEXT NOT NULL, server_json TEXT, state TEXT NOT NULL DEFAULT 'queued',
      transaction_id TEXT, lease_token TEXT, lease_until INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (business_id, owner_user_id, operation_id))''',
    );
    await _db.customStatement(
      '''CREATE TABLE IF NOT EXISTS local_payroll_proof_outbox (
      business_id TEXT NOT NULL, owner_user_id TEXT NOT NULL, operation_id TEXT NOT NULL,
      attachment_id TEXT NOT NULL, sha256 TEXT NOT NULL, byte_size INTEGER NOT NULL,
      PRIMARY KEY (business_id, owner_user_id, operation_id))''',
    );
    _guard();
  }

  List<Variable> _key(String operationId) => [
    Variable(businessId),
    Variable(ownerUserId),
    Variable(operationId),
  ];

  Future<QueryRow?> _row(String id) => _db.customSelect(
    '''SELECT * FROM local_payroll_outbox
    WHERE business_id=? AND owner_user_id=? AND operation_id=?''',
    variables: _key(id),
  ).getSingleOrNull();

  Future<void> enqueue(
    PayrollPaymentDraft draft,
    PayrollPaymentMethod method,
  ) async {
    _guard();
    if (draft.businessId != businessId ||
        method.businessId != businessId ||
        draft.validateForSubmission(method).isNotEmpty ||
        !isUuid(draft.operationId) ||
        !isUuid(draft.employeeId) ||
        !isUuid(draft.sourceAccountId ?? '') ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(draft.payrollWeekKey)) {
      throw StateError(
        'Verified employee, source account, method and payment terms required.',
      );
    }
    if (method.requiresCheckPhoto && !await verifyLocalProof(draft)) {
      throw StateError('Check photo is missing or damaged.');
    }
    _guard();
    final date = draft.paymentDate.toLocal();
    final frozen = jsonEncode({
      'business_id': businessId,
      'operation_id': draft.operationId,
      'employee_id': draft.employeeId,
      'local_method_id': method.id,
      'method_label': draft.methodLabelSnapshot,
      'method_kind': method.kind.name,
      'method_version': method.version,
      'amount_cents': draft.amountCents,
      'source_account_id': draft.sourceAccountId,
      'payment_date':
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'payroll_week': draft.payrollWeekKey,
      if (draft.laborAllocations.isNotEmpty)
        'labor_allocations': draft.laborAllocations
            .map((a) => a.toJson())
            .toList(),
      'reference': draft.reference,
      'proof_id': method.requiresCheckPhoto
          ? draft.checkProofAttachmentId
          : null,
      'proof_sha256': method.requiresCheckPhoto ? draft.checkProofSha256 : null,
      'proof_size': method.requiresCheckPhoto
          ? draft.checkProofSizeBytes
          : null,
    });
    await _tables();
    await _db.transaction(() async {
      final existing = await _row(draft.operationId);
      _guard();
      if (existing != null) {
        if (existing.read<String>('frozen_json') != frozen) {
          throw StateError(
            'Submitted payment terms are immutable. Use a new operation.',
          );
        }
        return;
      }
      await _db.customStatement(
        '''INSERT INTO local_payroll_outbox
        (business_id, owner_user_id, operation_id, frozen_json) VALUES (?, ?, ?, ?)''',
        [businessId, ownerUserId, draft.operationId, frozen],
      );
      _guard();
      if (method.requiresCheckPhoto) {
        await _db.customStatement(
          'INSERT INTO local_payroll_proof_outbox VALUES (?, ?, ?, ?, ?, ?)',
          [
            businessId,
            ownerUserId,
            draft.operationId,
            draft.checkProofAttachmentId,
            draft.checkProofSha256,
            draft.checkProofSizeBytes,
          ],
        );
      }
      _guard();
    });
  }

  Future<List<Map<String, dynamic>>> statuses() async {
    await _tables();
    final rows = await _db
        .customSelect(
          'SELECT operation_id,frozen_json,state,transaction_id FROM local_payroll_outbox WHERE business_id=? AND owner_user_id=?',
          variables: [Variable(businessId), Variable(ownerUserId)],
        )
        .get();
    _guard();
    return rows
        .map(
          (row) => {
            ...Map<String, dynamic>.from(
              jsonDecode(row.read<String>('frozen_json')) as Map,
            ),
            'state': row.read<String>('state'),
            'transaction_id': row.readNullable<String>('transaction_id'),
          },
        )
        .toList();
  }

  /// Returns false when no reviewed capability exists, work is leased, or no
  /// authoritative receipt exists yet. Offline callers keep the local row.
  Future<bool> syncOne(
    String operationId,
    PayrollPostingGateway gateway,
  ) async {
    await _tables();
    if (!await gateway.supportsReviewedPayrollV1(businessId)) return false;
    _guard();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final lease = '$now-${Random.secure().nextInt(1 << 32)}';
    final claimed = await _db.customUpdate(
      '''UPDATE local_payroll_outbox
      SET lease_until=?, lease_token=? WHERE business_id=? AND owner_user_id=? AND operation_id=?
      AND state='queued' AND lease_until<?''',
      variables: [
        Variable(now + 120000),
        Variable(lease),
        ..._key(operationId),
        Variable(now),
      ],
    );
    if (claimed == 0) {
      final current = await _row(operationId);
      _guard();
      return current?.read<String>('state') == 'posted';
    }
    try {
      final row = (await _row(operationId))!;
      _guard();
      final frozen = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('frozen_json')) as Map,
      );
      final savedServer = row.readNullable<String>('server_json');
      late Map<String, dynamic> server;
      if (savedServer != null) {
        server = Map<String, dynamic>.from(jsonDecode(savedServer) as Map);
      } else {
        final id = await gateway.registerMethod(
          PayrollPaymentMethod(
            id: frozen['local_method_id'] as String,
            businessId: businessId,
            label: frozen['method_label'] as String,
            kind: PayrollPaymentMethodKind.values.byName(
              frozen['method_kind'] as String,
            ),
            enabled: true,
            sortOrder: 0,
            version: frozen['method_version'] as int,
          ),
        );
        _guard();
        if (!isUuid(id)) {
          throw StateError(
            'Server did not register a durable method identity.',
          );
        }
        server = {...frozen}
          ..remove('local_method_id')
          ..remove('method_version');
        server['method_id'] = id;
        await _db.customStatement(
          '''UPDATE local_payroll_outbox SET server_json=?
          WHERE business_id=? AND owner_user_id=? AND operation_id=? AND server_json IS NULL''',
          [jsonEncode(server), businessId, ownerUserId, operationId],
        );
        // Another lease holder may already have frozen the server mapping.
        final persisted = (await _row(
          operationId,
        ))!.read<String>('server_json');
        if (persisted != jsonEncode(server)) {
          throw StateError('Method mapping changed; review required.');
        }
      }
      _guard();
      await gateway.prepare(Map.unmodifiable(server));
      _guard();
      if (server['method_kind'] == 'check') {
        await gateway.uploadAndVerifyProof(Map.unmodifiable(server));
        _guard();
      }
      final receipt = await gateway.post(Map.unmodifiable(server));
      _guard();
      if (receipt.businessId != businessId ||
          receipt.operationId != operationId ||
          receipt.amountCents != server['amount_cents'] ||
          !isUuid(receipt.transactionId) ||
          !['posted', 'void', 'removed'].contains(receipt.status)) {
        throw StateError('Posting receipt does not match the frozen payment.');
      }
      await _db.customStatement(
        '''UPDATE local_payroll_outbox SET state=?,
        transaction_id=?, lease_until=0 WHERE business_id=? AND owner_user_id=? AND operation_id=?''',
        [
          receipt.status,
          receipt.transactionId,
          businessId,
          ownerUserId,
          operationId,
        ],
      );
      return receipt.status == 'posted';
    } finally {
      // A lost response remains queued and reuses the exact persisted payload.
      await _db.customStatement(
        '''UPDATE local_payroll_outbox SET lease_until=0
        WHERE business_id=? AND owner_user_id=? AND operation_id=? AND state='queued' AND lease_token=? ''',
        [businessId, ownerUserId, operationId, lease],
      );
    }
  }
}
