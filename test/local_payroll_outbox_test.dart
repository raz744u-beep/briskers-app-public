import 'dart:io';
import 'dart:typed_data';

import 'package:briskers_app/core/payroll_payment_contract.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_draft_store.dart';
import 'package:briskers_app/services/local_payroll_outbox.dart';
import 'package:briskers_app/services/payroll_posting_gateway.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const employee = '00000000-0000-4000-8000-000000000001';
const account = '00000000-0000-4000-8000-000000000002';
const operation = '00000000-0000-4000-8000-000000000003';
const serverMethod = '00000000-0000-4000-8000-000000000004';
const transaction = '00000000-0000-4000-8000-000000000005';
const method = PayrollPaymentMethod(
  id: 'local-method',
  businessId: 'shop',
  label: 'Cash',
  kind: PayrollPaymentMethodKind.cash,
  enabled: true,
  sortOrder: 0,
  version: 1,
);
PayrollPaymentDraft draft({int amount = 50000, String source = account}) =>
    PayrollPaymentDraft(
      businessId: 'shop',
      employeeId: employee,
      operationId: operation,
      methodId: method.id,
      methodLabelSnapshot: 'Cash',
      amountCents: amount,
      sourceAccountId: source,
      paymentDate: DateTime(2026, 10, 23),
      payrollWeekKey: '2026-10-19',
    );

class FakeServer implements PayrollPostingGateway {
  bool supported = true;
  String status = 'posted';
  bool loseResponse = true;
  int ledgerInserts = 0;
  int calls = 0;
  int registrations = 0;
  Map<String, dynamic>? frozen;
  @override
  Future<bool> supportsReviewedPayrollV1(String businessId) async => supported;
  @override
  Future<String> registerMethod(PayrollPaymentMethod method) async {
    registrations++;
    return serverMethod;
  }

  @override
  Future<void> prepare(Map<String, dynamic> payload) async {
    expect(payload['method_id'], serverMethod);
    expect(payload.containsKey('local_method_id'), false);
    if (frozen != null) expect(payload, frozen);
    frozen ??= {...payload};
  }

  @override
  Future<void> uploadAndVerifyProof(Map<String, dynamic> payload) async {}
  @override
  Future<PayrollPostingReceipt> post(Map<String, dynamic> payload) async {
    calls++;
    if (ledgerInserts == 0) ledgerInserts++;
    if (loseResponse) {
      loseResponse = false;
      throw const SocketException('lost response');
    }
    return PayrollPostingReceipt(
      status: status,
      businessId: 'shop',
      operationId: operation,
      transactionId: transaction,
      amountCents: payload['amount_cents'] as int,
    );
  }
}

void main() {
  test(
    'production adapter cannot activate before separate deployment approval',
    () async {
      final adapter = PayrollPostingGatewayV1(
        businessId: 'shop',
        isContextCurrent: () => true,
        readProofBytes: (_) async => Uint8List(0),
      );
      expect(await adapter.supportsReviewedPayrollV1('shop'), false);
      await expectLater(adapter.registerMethod(method), throwsStateError);
      await expectLater(adapter.prepare({}), throwsStateError);
      await expectLater(adapter.post({}), throwsStateError);
    },
  );
  test(
    'restart after lost response reuses frozen server identity and one transaction',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'payroll-outbox-',
      );
      final file = File('${directory.path}/db.sqlite');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      final server = FakeServer();
      LocalPayrollOutbox queue() => LocalPayrollOutbox(
        database: db,
        businessId: 'shop',
        ownerUserId: 'owner',
        isContextCurrent: () => true,
        verifyLocalProof: (_) async => true,
      );
      try {
        final drafts = LocalPayrollDraftStore(database: db);
        await drafts.save(isOwner: true, ownerUserId: 'owner', draft: draft());
        await queue().enqueue(draft(), method);
        await expectLater(
          queue().enqueue(draft(amount: 60000), method),
          throwsStateError,
        );
        await expectLater(
          drafts.save(
            isOwner: true,
            ownerUserId: 'owner',
            draft: draft(amount: 60000),
          ),
          throwsStateError,
        );
        await expectLater(
          drafts.discard(
            isOwner: true,
            businessId: 'shop',
            ownerUserId: 'owner',
            operationId: operation,
          ),
          throwsStateError,
        );
        await expectLater(
          queue().syncOne(operation, server),
          throwsA(isA<SocketException>()),
        );
        expect(
          (await db
                  .customSelect('SELECT state FROM local_payroll_outbox')
                  .getSingle())
              .read<String>('state'),
          'queued',
        );
        await db.close();
        db = BriskersLocalDatabase(NativeDatabase(file));
        expect(await queue().syncOne(operation, server), true);
        expect(await queue().syncOne(operation, server), true);
        expect(server.ledgerInserts, 1);
        expect(server.calls, 2);
        expect(server.registrations, 1);
        expect(
          (await db
                  .customSelect(
                    'SELECT transaction_id FROM local_payroll_outbox',
                  )
                  .getSingle())
              .read<String>('transaction_id'),
          transaction,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'void receipt is terminal and pending receipt never claims paid',
    () async {
      for (final status in ['void', 'pending']) {
        final db = BriskersLocalDatabase(NativeDatabase.memory());
        final queue = LocalPayrollOutbox(
          database: db,
          businessId: 'shop',
          ownerUserId: 'owner',
          isContextCurrent: () => true,
          verifyLocalProof: (_) async => true,
        );
        final server = FakeServer()
          ..loseResponse = false
          ..status = status;
        try {
          await queue.enqueue(draft(), method);
          if (status == 'void') {
            expect(await queue.syncOne(operation, server), false);
            expect(await queue.syncOne(operation, server), false);
            expect(server.calls, 1);
            expect((await queue.statuses()).single['state'], 'void');
          } else {
            await expectLater(
              queue.syncOne(operation, server),
              throwsStateError,
            );
            expect((await queue.statuses()).single['state'], 'queued');
          }
        } finally {
          await db.close();
        }
      }
    },
  );

  test(
    'missing capability, provisional source and revoked actor cannot post',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      var current = true;
      final queue = LocalPayrollOutbox(
        database: db,
        businessId: 'shop',
        ownerUserId: 'owner',
        isContextCurrent: () => current,
        verifyLocalProof: (_) async => false,
      );
      final server = FakeServer()..supported = false;
      try {
        await expectLater(
          queue.enqueue(draft(source: 'draft-bank'), method),
          throwsStateError,
        );
        await queue.enqueue(draft(), method);
        expect(await queue.syncOne(operation, server), false);
        expect(server.registrations, 0);
        expect(server.ledgerInserts, 0);
        current = false;
        await expectLater(queue.syncOne(operation, server), throwsStateError);
        expect(server.ledgerInserts, 0);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'Check proof and operation freeze commit together; missing bytes reject queue',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      var intact = false;
      final queue = LocalPayrollOutbox(
        database: db,
        businessId: 'shop',
        ownerUserId: 'owner',
        isContextCurrent: () => true,
        verifyLocalProof: (_) async => intact,
      );
      final check = const PayrollPaymentMethod(
        id: 'check',
        businessId: 'shop',
        label: 'Check',
        kind: PayrollPaymentMethodKind.check,
        enabled: true,
        sortOrder: 1,
        version: 1,
      );
      final payment = PayrollPaymentDraft(
        businessId: 'shop',
        employeeId: employee,
        operationId: operation,
        methodId: 'check',
        methodLabelSnapshot: 'Check',
        amountCents: 10000,
        sourceAccountId: account,
        paymentDate: DateTime(2026, 10, 23),
        payrollWeekKey: '2026-10-19',
        checkProofAttachmentId: 'local-check-${'a' * 64}',
        checkProofDurablyStored: true,
        checkProofSha256: 'a' * 64,
        checkProofSizeBytes: 100,
      );
      try {
        await expectLater(queue.enqueue(payment, check), throwsStateError);
        intact = true;
        await queue.enqueue(payment, check);
        await queue.enqueue(payment, check);
        expect(
          await db.customSelect('SELECT * FROM local_payroll_outbox').get(),
          hasLength(1),
        );
        expect(
          await db
              .customSelect('SELECT * FROM local_payroll_proof_outbox')
              .get(),
          hasLength(1),
        );
      } finally {
        await db.close();
      }
    },
  );
}
