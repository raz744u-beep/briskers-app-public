import 'package:briskers_app/core/payroll_payment_contract.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_draft_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PayrollPaymentDraft draft({
    String shop = 'shop-one',
    String operation = 'op-001',
    String method = 'check-1',
    String employee = 'employee-Kam-ID',
    int cents = 70000,
  }) =>
      PayrollPaymentDraft(
        businessId: shop,
        employeeId: employee,
        operationId: operation,
        methodId: method,
        methodLabelSnapshot: 'Check',
        amountCents: cents,
        paymentDate: DateTime(2026, 10, 22),
        payrollWeekKey: '2026-W43',
        sourceAccountId: 'business-bank',
        checkProofDurablyStored: false,
      );

  test('draft survives new store instance, but is never posted', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalPayrollDraftStore(database: db);
      await store.save(
        isOwner: true,
        ownerUserId: 'owner-one',
        draft: draft(),
      );
      final afterRestart = LocalPayrollDraftStore(database: db);
      final rows = await afterRestart.load(
        isOwner: true,
        businessId: 'shop-one',
        ownerUserId: 'owner-one',
      );
      expect(rows, hasLength(1));
      expect(rows.single.operationId, 'op-001');
      expect(rows.single.amountCents, 70000);
      expect(rows.single.methodId, 'check-1');
      expect(rows.single.checkProofDurablyStored, false);
      final outbox = await db.customSelect(
        "SELECT id FROM sync_outbox WHERE entity_type LIKE '%payroll%'",
      ).get();
      expect(outbox, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('one stable operation updates the same draft, never duplicates it',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalPayrollDraftStore(database: db);
      await store.save(
        isOwner: true, ownerUserId: 'owner-one', draft: draft(),
      );
      await store.save(
        isOwner: true, ownerUserId: 'owner-one',
        draft: draft(cents: 72000),
      );
      final rows = await store.load(
        isOwner: true, businessId: 'shop-one', ownerUserId: 'owner-one',
      );
      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 72000);
    } finally {
      await db.close();
    }
  });

  test('cannot leak payroll drafts across shops or Owners', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalPayrollDraftStore(database: db);
      await store.save(
        isOwner: true, ownerUserId: 'owner-one', draft: draft(),
      );
      expect(
        await store.load(
          isOwner: true, businessId: 'shop-two', ownerUserId: 'owner-one',
        ), isEmpty,
      );
      expect(
        await store.load(
          isOwner: true, businessId: 'shop-one', ownerUserId: 'owner-two',
        ), isEmpty,
      );
    } finally {
      await db.close();
    }
  });

  test('non-owner reads, saves and deletes are blocked', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalPayrollDraftStore(database: db);
      await expectLater(
        store.save(isOwner: false, ownerUserId: 'mechanic', draft: draft()),
        throwsStateError,
      );
      await expectLater(
        store.load(
          isOwner: false, businessId: 'shop-one', ownerUserId: 'mechanic',
        ), throwsStateError,
      );
      await expectLater(
        store.discard(
          isOwner: false, businessId: 'shop-one',
          ownerUserId: 'mechanic', operationId: 'op-001',
        ), throwsStateError,
      );
    } finally {
      await db.close();
    }
  });

  test('discard removes only the specified draft and no finances', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalPayrollDraftStore(database: db);
      await store.save(
        isOwner: true, ownerUserId: 'owner-one', draft: draft(),
      );
      await store.save(
        isOwner: true, ownerUserId: 'owner-one',
        draft: draft(operation: 'op-002'),
      );
      await store.discard(
        isOwner: true, businessId: 'shop-one',
        ownerUserId: 'owner-one', operationId: 'op-001',
      );
      final rows = await store.load(
        isOwner: true, businessId: 'shop-one', ownerUserId: 'owner-one',
      );
      expect(rows.map((r) => r.operationId), ['op-002']);
      expect(
        await db.customSelect(
          "SELECT id FROM sync_outbox WHERE entity_type LIKE '%payroll%'",
        ).get(),
        isEmpty,
      );
    } finally {
      await db.close();
    }
  });

  test('empty Owner or missing operation identity cannot be stored',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = LocalPayrollDraftStore(database: db);
      await expectLater(
        store.save(isOwner: true, ownerUserId: '', draft: draft()),
        throwsArgumentError,
      );
      await expectLater(
        store.save(
          isOwner: true, ownerUserId: 'owner-one', draft: draft(operation: ''),
        ),
        throwsArgumentError,
      );
    } finally {
      await db.close();
    }
  });
}
